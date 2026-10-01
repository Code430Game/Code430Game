class_name Synth
extends RefCounted
## Procedural audio helpers around AudioStreamGenerator: every sound in the game is made
## here at runtime, so the repo ships no audio assets. Each voice owns a generator stream
## and fills its playback buffer each frame from a small set of oscillators and noise.

const MIX_RATE := 22050.0
const BUFFER_S := 0.1


## A player with a generator stream on `bus`, ready to be fed.
static func make_player(bus: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_S
	p.stream = gen
	p.bus = bus
	p.volume_db = volume_db
	return p


## Engine pitch in Hz for a speed in m/s and throttle 0..1: an idle, rising with speed as
## if through gears, plus a little lift under throttle.
static func engine_hz(speed_mps: float, throttle: float) -> float:
	var gear := fmod(speed_mps, 9.0) / 9.0  # each "gear" spans 9 m/s and the revs climb within it
	var band := clampf(speed_mps / 9.0, 0.0, 4.0)
	return 55.0 + 25.0 * band + 70.0 * gear + 30.0 * throttle


## Impact loudness 0..1 for a collision speed in m/s.
static func impact_gain(speed_mps: float) -> float:
	return clampf((speed_mps - 1.5) / 14.0, 0.0, 1.0)


## A rolling-noise gain 0..1 for a speed in m/s.
static func tyre_gain(speed_mps: float) -> float:
	return clampf(speed_mps / 25.0, 0.0, 1.0)


## Pseudo-random noise sample in -1..1 from a running state (xorshift).
static func noise(state: Array) -> float:
	var x: int = state[0]
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	state[0] = x
	return float(x) / 2147483648.0 - 1.0
