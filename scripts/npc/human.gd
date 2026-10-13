class_name Human
extends Node3D
## VARCO 로 만든 실사 캐릭터. 리깅된 모델 + 그 몸에 맞춰 구운 애니메이션 묶음.
## 모델은 키 1m 로 정규화되어 나오므로 height 로 키를 맞춘다.

const LIB := preload("res://assets/people/anim_lib.res")   # 원본 경찰 리그 기준 (구운 게 없을 때만)

var anim: AnimationPlayer
var model: Node3D


static func make(model_name: String, height := 1.75) -> Human:
	var h := Human.new()
	h.model = load("res://assets/people/%s.glb" % model_name).instantiate()
	h.model.scale = Vector3.ONE * height
	h.model.rotation.y = PI       # 모델은 +Z 를 본다, 게임은 -Z 가 앞
	h.add_child(h.model)
	h.anim = h.model.find_child("AnimationPlayer", true, false)
	if h.anim == null:
		h.anim = AnimationPlayer.new()
		h.model.add_child(h.anim)
	h.anim.add_animation_library("h", lib(model_name))
	return h


## 캐릭터 뼈대에 맞춰 구운 애니 (tools/build_char_anims.gd). 없으면 공용.
static func lib(model_name: String) -> AnimationLibrary:
	var p := "res://assets/people/baked/%s.res" % model_name
	return load(p) if ResourceLoader.exists(p) else LIB


func play(name: String, blend := 0.2, speed := 1.0) -> void:
	var key := "h/" + name
	if anim.has_animation(key) and anim.current_animation != key:
		anim.play(key, blend, speed)


func playing() -> String:
	return anim.current_animation.trim_prefix("h/")


func is_playing() -> bool:
	return anim.is_playing()


## 걷기/뛰기 애니가 키 1m 몸에서 발로 땅을 미는 속도 (m/s, tools/_stride.gd 로 잼)
const STRIDE := {"walk": 0.51, "walk_f": 0.52, "walk_old": 0.27, "stumble": 0.55, "jog": 0.86,
	"run": 1.73, "sprint": 2.46, "run_kid": 1.0}


## 실제로 움직이는 속도에 맞는 재생 배속 (발이 미끄러지지 않게). 걷기/뛰기가 아니면 1
static func stride_rate(anim_name: String, move_speed: float, height: float) -> float:
	if not STRIDE.has(anim_name) or move_speed < 0.05:
		return 1.0
	return clampf(move_speed / (STRIDE[anim_name] * height), 0.6, 2.4)

