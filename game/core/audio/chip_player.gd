class_name ChipPlayer
extends Node
## Plays a ChipSong on its own generator stream on the Music bus, filling the buffer each frame.
## Pausing the tree pauses the fill (and so the song) unless the node runs always.

var song: ChipSong
var playing: bool = false
var _player: AudioStreamPlayer


func _ready() -> void:
	_player = Synth.make_player("Music" if AudioServer.get_bus_index("Music") >= 0 else "Master", -6.0)
	add_child(_player)


## Starts or resumes `new_song` (null stops). The same song resumes where it was.
func play_song(new_song: ChipSong) -> void:
	song = new_song
	playing = song != null
	if playing and not _player.playing:
		_player.play()
	elif not playing:
		_player.stop()


## Pauses without losing the song's position.
func pause() -> void:
	playing = false
	_player.stop()


func _process(_delta: float) -> void:
	if not playing or song == null:
		return
	var pb: AudioStreamGeneratorPlayback = _player.get_stream_playback()
	if pb == null:
		return
	var frames := pb.get_frames_available()
	if frames > 0:
		pb.push_buffer(song.render(frames))
