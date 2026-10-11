extends Node
## 효과음/BGM 재생. play("splash"), play_at("sizzle", pos), loop 소리는 loop_player()로 받는다.

const SOUNDS := {
	"spray": ["res://assets/sfx/spray.wav"],
	"splash": ["res://assets/sfx/splash.wav"],
	"bucket": ["res://assets/sfx/bucket.wav"],
	"sizzle": ["res://assets/sfx/sizzle.wav"],
	"coin": ["res://assets/sfx/coin.wav"],
	"horn": ["res://assets/sfx/horn.wav"],
	"hit": ["res://assets/sfx/impactSoft_medium_000.ogg", "res://assets/sfx/impactSoft_medium_001.ogg"],
	"kick": ["res://assets/sfx/impactPunch_medium_000.ogg"],
	"thud": ["res://assets/sfx/impactSoft_heavy_000.ogg"],
	"step": [
		"res://assets/sfx/footstep_concrete_000.ogg", "res://assets/sfx/footstep_concrete_001.ogg",
		"res://assets/sfx/footstep_concrete_002.ogg", "res://assets/sfx/footstep_concrete_003.ogg",
	],
	"click": ["res://assets/sfx/click_001.ogg"],
	"buy": ["res://assets/sfx/confirmation_002.ogg"],
	"good": ["res://assets/sfx/confirmation_001.ogg"],
	"error": ["res://assets/sfx/error_004.ogg"],
	"switch": ["res://assets/sfx/switch_002.ogg"],
	"select": ["res://assets/sfx/select_002.ogg"],
	"bong": ["res://assets/sfx/bong_001.ogg"],
	"refill": ["res://assets/sfx/drop_002.ogg"],
	"fanfare": ["res://assets/sfx/maximize_006.ogg"],
	"shutter": ["res://assets/sfx/shutter.wav"],
	"spark": ["res://assets/sfx/spark.wav"],
	"voice_adult": ["res://assets/sfx/voice_ah.wav", "res://assets/sfx/voice_ugh.wav", "res://assets/sfx/voice_hey.wav", "res://assets/sfx/voice_ow.wav"],
	"voice_kid": ["res://assets/sfx/voice_kid.wav", "res://assets/sfx/voice_kid2.wav"],
	"voice_scream": ["res://assets/sfx/voice_scream.wav"],
	"voice_boss": ["res://assets/sfx/voice_boss.wav"],
	"voice_achoo": ["res://assets/sfx/voice_achoo.wav"],
	"slip": ["res://assets/sfx/impactSoft_heavy_000.ogg"],
}
const LOOPS := {
	"stream": "res://assets/sfx/stream_loop.wav",
	"hose": "res://assets/sfx/hose_loop.wav",
	"siren": "res://assets/sfx/siren_loop.wav",
	"city": "res://assets/sfx/city_loop.wav",
	"bgm": "res://assets/music/bgm.wav",
	"club": "res://assets/music/club.wav",
	"karaoke": "res://assets/music/karaoke.wav",
	"lounge": "res://assets/music/lounge.wav",
}

var _cache := {}
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.volume_db = -9.0
	add_child(_music)


func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


func _loop_stream(name: String) -> AudioStream:
	var s: AudioStream = _stream(LOOPS[name])
	if s is AudioStreamWAV and s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(SOUNDS[name].pick_random())
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var tree := get_tree()
	if tree.current_scene == null or not tree.current_scene is Node3D:
		play(name, volume_db, pitch)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(SOUNDS[name].pick_random())
	p.volume_db = volume_db
	p.unit_size = 8.0
	p.max_distance = 60.0
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	tree.current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


## 반복 소리를 내는 플레이어를 만들어 parent에 붙인다. 재생/정지는 호출한 쪽이 한다.
func loop_player(name: String, parent: Node, volume_db := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _loop_stream(name)
	p.volume_db = volume_db
	parent.add_child(p)
	return p


func loop_player_3d(name: String, parent: Node3D, volume_db := 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _loop_stream(name)
	p.volume_db = volume_db
	p.unit_size = 10.0
	p.max_distance = 80.0
	parent.add_child(p)
	return p


func music(on: bool) -> void:
	if on and not _music.playing:
		_music.stream = _loop_stream("bgm")
		_music.play()
	elif not on:
		_music.stop()
