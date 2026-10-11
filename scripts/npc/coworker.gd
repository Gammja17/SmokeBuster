class_name Coworker
extends StaticBody3D
## 파출소 동료. 가만히 서서 자기 일을 하다가, 플레이어가 오면 돌아보고 인사한다. E 로 말을 걸 수 있다.

const DATA := {
	"chief": {"name": "소장님", "idle": "cross_arms", "greet": "salute", "lines": [
		"오늘도 동네 평화를 부탁하네!", "민원은 줄이고 실적은 올리고! 허허", "승진 심사 때 잘 봐주지.", "무전 오면 지체 말고 출동하게!"]},
	"ops": {"name": "상황실 요원", "idle": "talk", "greet": "wave", "lines": [
		"파란 빛기둥이 출동 현장이에요.", "상황실 업그레이드하면 출동 보상이 올라가요.", "지금도 신고 전화가 계속 와요...", "음주운전 차는 순찰차로 들이받아도 돼요."]},
	"mechanic": {"name": "정비 담당", "idle": "breathe", "greet": "wave", "lines": [
		"순찰차 기름 가득 넣어놨어!", "정비고 업그레이드하면 차가 확 빨라지지.", "소방차 키는 장비실에서 팔아. 물대포가 끝내줘!", "차 부수고 오지 마라잉."]},
	"rookie": {"name": "신입 순경", "idle": "idle", "greet": "salute", "lines": [
		"서, 선배님! 오늘도 화이팅입니다!", "도둑은 달리다 부딪히면 태클로 잡힌대요!", "저도 언젠가 소방호스 써보고 싶어요...", "학생들한텐 물 말고 사진이요! 저번에 혼났어요."]},
}

var role := "chief"
var human: Human
var _label: Label3D
var _greeted := false
var _say_t := 0.0
var _player: Node3D


func _ready() -> void:
	add_to_group("coworker")
	collision_layer = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	human = Human.make(role, 1.72 if role != "rookie" else 1.62)
	add_child(human)
	human.play(DATA[role].idle, 0.0)
	_label = Label3D.new()
	_label.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.05
	_label.text = DATA[role].name
	_label.modulate = Color(0.6, 0.85, 1)
	add_child(_label)


func display_name() -> String:
	return DATA[role].name


func _process(delta: float) -> void:
	_say_t -= delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		return
	var to := _player.global_position - global_position
	to.y = 0
	var near := to.length() < 5.0
	if near:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 4.0 * delta)
		if not _greeted:
			_greeted = true
			human.play(DATA[role].greet, 0.2)
			_later(2.0, func(): human.play(DATA[role].idle, 0.3))
	elif to.length() > 9.0:
		_greeted = false
	if _say_t <= 0.0 and _label.text != DATA[role].name:
		_label.text = DATA[role].name
		_label.modulate = Color(0.6, 0.85, 1)


func talk() -> void:
	_label.text = DATA[role].lines.pick_random()
	_label.modulate = Color.WHITE
	_say_t = 3.5
	human.play("talk", 0.2)
	_later(3.0, func(): human.play(DATA[role].idle, 0.3))


func _later(t: float, fn: Callable) -> void:
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_callback(fn)
