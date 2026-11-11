extends Node
## Sound effects player: a small pool of non-positional players fed by
## assets/data/audio_sfx.json (volume, pitch jitter, looping per sound).
## Files live in res://assets/audio/sfx/<name>.mp3.

const SFX_DIR := "res://assets/audio/sfx/"

var _cfg: Dictionary = {}
var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}


## Loads [param config_path] and every sound it lists. Missing files are
## skipped with a warning so the game still runs silent.
func setup(config_path: String) -> void:
	_cfg = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	for sound_name: String in _cfg.sounds:
		var path: String = SFX_DIR + sound_name + ".mp3"
		if not ResourceLoader.exists(path):
			push_warning("sfx missing: " + path)
			continue
		var stream: AudioStream = load(path)
		if _cfg.sounds[sound_name].get("loop", false) and stream is AudioStreamMP3:
			stream = stream.duplicate()
			stream.loop = true
		_streams[sound_name] = stream
	for i in int(_cfg.get("voices", 12)):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


## Plays [param sound_name] once on a free voice (steals the oldest if all busy).
func play(sound_name: String, volume_offset_db: float = 0.0) -> void:
	if not _streams.has(sound_name):
		return
	var p: AudioStreamPlayer = _free_voice()
	_configure(p, sound_name, volume_offset_db)
	p.play()


## Starts a looping sound; calling it again while playing does nothing.
func start_loop(sound_name: String) -> void:
	if _loops.has(sound_name) or not _streams.has(sound_name):
		return
	var p := AudioStreamPlayer.new()
	add_child(p)
	_configure(p, sound_name, 0.0)
	p.play()
	_loops[sound_name] = p


## Stops a loop started with [method start_loop].
func stop_loop(sound_name: String) -> void:
	if _loops.has(sound_name):
		_loops[sound_name].queue_free()
		_loops.erase(sound_name)


func _configure(p: AudioStreamPlayer, sound_name: String, offset_db: float) -> void:
	var entry: Dictionary = _cfg.sounds[sound_name]
	var jitter: float = float(entry.get("jitter", _cfg.get("pitch_jitter", 0.0)))
	p.stream = _streams[sound_name]
	p.volume_db = float(entry.get("db", 0.0)) + offset_db
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)


func _free_voice() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	var oldest: AudioStreamPlayer = _pool.pop_front()
	_pool.append(oldest)
	return oldest
