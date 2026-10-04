class_name ChipSong
extends RefCounted
## Renders a chip-music track (docs/pack-format/music.schema.v0.json) to samples.
##
## Approach: up to four channels, each a list of step tokens: a note (`C4`, `F#3`, `Bb2`, with an
## optional `:v` volume 0..15), `~` to hold, `.` to release. Steps are timed from a running sample
## counter, so tempo never drifts. Each channel has a pulse, triangle or noise oscillator and an
## attack-decay-sustain-release envelope. A new note restarts the attack from the envelope's
## current level, never from zero, so notes and the loop point do not click. Channels repeat
## independently; the song loops at its longest channel. An optional echo adds a delayed, quieter
## copy of the mix (the dungeon's repeats).

const MAX_CHANNELS := 4
const MASTER_GAIN := 0.22  # four full channels sum to under 1.0
const NOTE_NAMES := {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

var mix_rate: float
var tempo_bpm: float
var steps_per_beat: int
var step_samples: float
var length_steps: int = 0
var channels: Array[Channel] = []
var echo_samples: int = 0
var echo_gain: float = 0.0
var _echo: PackedFloat32Array = PackedFloat32Array()
var _echo_pos: int = 0
var _sample: int = 0  # samples rendered since the start
var _noise_state: Array = [0x2545F491]


class Channel:
	extends RefCounted
	var wave: String = "pulse"
	var duty: float = 0.5
	var attack: float = 0.01
	var decay: float = 0.1
	var sustain: float = 0.7
	var release: float = 0.05
	var vibrato_hz: float = 0.0
	var vibrato_cents: float = 0.0
	var steps: Array = []  # [kind, hz, volume]: kind "note", "hold" or "rest"
	# Running state.
	var hz: float = 0.0
	var volume: float = 1.0
	var phase: float = 0.0
	var level: float = 0.0
	var stage: int = 3  # 0 attack, 1 decay, 2 sustain, 3 release
	var note_time: float = 0.0
	var noise_value: float = 0.0
	var noise_count: float = 0.0
	var last_step: int = -1


## Parses a track dictionary. Raises nothing: bad tokens become rests, logged once.
static func from_dict(track: Dictionary, rate: float = Synth.MIX_RATE) -> ChipSong:
	var song := ChipSong.new()
	song.mix_rate = rate
	song.tempo_bpm = float(track.get("tempo_bpm", 120))
	song.steps_per_beat = int(track.get("steps_per_beat", 4))
	song.step_samples = rate * 60.0 / (song.tempo_bpm * song.steps_per_beat)
	var instruments: Dictionary = track.get("instruments", {})
	for ch_data in (track.get("channels", []) as Array).slice(0, MAX_CHANNELS):
		var ch := Channel.new()
		var inst: Dictionary = instruments.get(ch_data.get("instrument", ""), {})
		ch.wave = str(inst.get("wave", "pulse"))
		ch.duty = float(inst.get("duty", 0.5))
		ch.attack = maxf(float(inst.get("attack", 0.01)), 0.001)
		ch.decay = maxf(float(inst.get("decay", 0.1)), 0.001)
		ch.sustain = float(inst.get("sustain", 0.7))
		ch.release = maxf(float(inst.get("release", 0.05)), 0.001)
		ch.vibrato_hz = float(inst.get("vibrato_hz", 0.0))
		ch.vibrato_cents = float(inst.get("vibrato_cents", 0.0))
		for token in str(ch_data.get("pattern", "")).split(" ", false):
			ch.steps.append(parse_token(token))
		if not ch.steps.is_empty():
			song.channels.append(ch)
			song.length_steps = maxi(song.length_steps, ch.steps.size())
	var echo: Dictionary = track.get("echo", {})
	if not echo.is_empty():
		song.echo_samples = maxi(1, int(float(echo.get("delay_s", 0.3)) * rate))
		song.echo_gain = clampf(float(echo.get("gain", 0.35)), 0.0, 0.9)
		song._echo.resize(song.echo_samples)
	return song


## [kind, hz, volume 0..1] for one step token.
static func parse_token(token: String) -> Array:
	if token == "~":
		return ["hold", 0.0, 0.0]
	if token == ".":
		return ["rest", 0.0, 0.0]
	var vol := 1.0
	var name := token
	if token.contains(":"):
		name = token.get_slice(":", 0)
		vol = clampf(float(token.get_slice(":", 1)) / 15.0, 0.0, 1.0)
	var hz := note_hz(name)
	if hz <= 0.0:
		return ["rest", 0.0, 0.0]
	return ["note", hz, vol]


## Frequency of a note name like A4, C#3 or Bb2 (A4 = 440 Hz); 0 when it is not a note.
static func note_hz(name: String) -> float:
	if name.length() < 2 or not NOTE_NAMES.has(name[0].to_upper()):
		return 0.0
	var semis: int = NOTE_NAMES[name[0].to_upper()]
	var rest := name.substr(1)
	while rest.begins_with("#") or rest.begins_with("b"):
		semis += 1 if rest[0] == "#" else -1
		rest = rest.substr(1)
	if not rest.is_valid_int():
		return 0.0
	var midi := 12 * (int(rest) + 1) + semis
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## The song's loop length in seconds.
func length_s() -> float:
	return length_steps * step_samples / mix_rate


## Renders `frames` stereo samples, continuing where the last call stopped.
func render(frames: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	var dt := 1.0 / mix_rate
	for i in range(frames):
		var global_step := int(floor(_sample / step_samples))
		var mix := 0.0
		for ch in channels:
			var step := global_step % length_steps % ch.steps.size()
			if step != ch.last_step:
				_enter_step(ch, ch.steps[step])
				ch.last_step = step
			mix += _channel_sample(ch, dt)
		var s := mix * MASTER_GAIN
		if echo_samples > 0:
			var delayed := _echo[_echo_pos]
			_echo[_echo_pos] = s + delayed * echo_gain
			_echo_pos = (_echo_pos + 1) % echo_samples
			s += delayed * echo_gain
		s = clampf(s, -1.0, 1.0)
		out[i] = Vector2(s, s)
		_sample += 1
	return out


## Envelope level of each channel right now (tests check the loop seam with it).
func levels() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for ch in channels:
		out.append(ch.level)
	return out


## Samples per loop, rounded.
func loop_samples() -> int:
	return int(round(length_steps * step_samples))


func _enter_step(ch: Channel, step: Array) -> void:
	match step[0]:
		"note":
			ch.hz = step[1]
			ch.volume = step[2]
			ch.stage = 0  # attack from the current level: no click
			ch.note_time = 0.0
		"rest":
			ch.stage = 3
		_:
			pass  # hold: keep going


func _channel_sample(ch: Channel, dt: float) -> float:
	# Envelope.
	match ch.stage:
		0:
			ch.level += dt / ch.attack
			if ch.level >= 1.0:
				ch.level = 1.0
				ch.stage = 1
		1:
			ch.level -= dt / ch.decay * (1.0 - ch.sustain)
			if ch.level <= ch.sustain:
				ch.level = ch.sustain
				ch.stage = 2
		3:
			ch.level = maxf(0.0, ch.level - dt / ch.release)
	if ch.level <= 0.0 or ch.hz <= 0.0:
		return 0.0
	ch.note_time += dt
	var hz := ch.hz
	if ch.vibrato_cents > 0.0 and ch.vibrato_hz > 0.0:
		hz *= pow(2.0, ch.vibrato_cents * sin(TAU * ch.vibrato_hz * ch.note_time) / 1200.0)
	ch.phase = fposmod(ch.phase + hz / mix_rate, 1.0)
	var v := 0.0
	match ch.wave:
		"pulse":
			v = 1.0 if ch.phase < ch.duty else -1.0
		"triangle":
			v = 4.0 * absf(ch.phase - 0.5) - 1.0
		"noise":
			# Sample-and-hold noise: a higher note changes value more often (a brighter hiss).
			ch.noise_count += hz / mix_rate * 8.0
			if ch.noise_count >= 1.0:
				ch.noise_count -= floor(ch.noise_count)
				ch.noise_value = Synth.noise(_noise_state)
			v = ch.noise_value
	return v * ch.level * ch.volume
