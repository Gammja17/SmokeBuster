extends CanvasLayer
## 대화창 (킹덤컴처럼): 카메라가 말하는 사람 얼굴 앞으로 가고, 위아래 검은 띠, 아래에 이름과 대사.
## start(대화, 말하는 사람) 으로 시작. 대화는 [{who, text, anim?}, {choices: [[문구, [이어질 대화...]], ...]}, ...]
## E / 스페이스 / 엔터 / 클릭으로 넘기고, 선택지는 숫자키나 마우스.

signal finished

const BAR_H := 92.0
const CPS := 38.0      # 글자/초

var player: Node3D
var active := false

var _queue: Array = []
var _speaker: Node3D
var _cam: Camera3D
var _prev_cam: Camera3D
var _typing := 0.0
var _choosing := false
var _cool := 0.0

@onready var _top: ColorRect = $Top
@onready var _bottom: ColorRect = $Bottom
@onready var _box: Control = $Box
@onready var _name: Label = $Box/V/Name
@onready var _line: Label = $Box/V/Line
@onready var _choices: VBoxContainer = $Box/V/Choices
@onready var _cont: Label = $Box/V/Cont


func start(convo: Array, speaker: Node3D) -> void:
	if active:
		return
	active = true
	_queue = convo.duplicate(true)
	_speaker = speaker
	visible = true
	player.input_enabled = false
	player.set_camera_mode(false)
	_set_hud(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_frame_camera()
	var tw := create_tween().set_parallel()
	_top.offset_bottom = 0.0
	_bottom.offset_top = 0.0
	tw.tween_property(_top, "offset_bottom", BAR_H, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bottom, "offset_top", -BAR_H, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_box.modulate.a = 0.0
	tw.tween_property(_box, "modulate:a", 1.0, 0.3).set_delay(0.15)
	_cool = 0.3
	_next()


func _set_hud(on: bool) -> void:
	## 대화(컷씬) 동안엔 화면 UI 를 숨긴다
	var hud = player.get_parent().get("hud")
	if hud:
		hud.visible = on


func _frame_camera(keep := false) -> void:
	## 말하는 사람 얼굴을 플레이어 쪽 어깨 너머로 비춘다 (keep: 대화 중 다른 사람으로 옮길 때)
	if not keep:
		_prev_cam = get_viewport().get_camera_3d()
	if _speaker == null or _prev_cam == null:
		return
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 42.0
		player.get_parent().add_child(_cam)
	var head: Vector3 = _speaker.global_position + Vector3.UP * 1.55
	var to_player: Vector3 = player.global_position - _speaker.global_position
	to_player.y = 0
	if to_player.length() < 0.1:
		to_player = -_speaker.global_basis.z
	to_player = to_player.normalized()
	var right := to_player.cross(Vector3.UP).normalized()
	# 눈높이에서 살짝 위, 1.9m 떨어져 어깨 너머로 (얼굴이 화면 위 1/3 쯤에 오게 조금 아래를 본다)
	var cam_pos := head + to_player * 1.9 + right * 0.5 + Vector3.UP * 0.12
	# 사이에 벽이나 정류장 같은 게 있으면 그 앞으로 당긴다 (카메라가 물건 속에 박히지 않게)
	var ex: Array[RID] = [player.get_rid()]
	if _speaker is CollisionObject3D:
		ex.append(_speaker.get_rid())
	var q := PhysicsRayQueryParameters3D.create(head, cam_pos, 1 | 2, ex)
	var hit := _speaker.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		cam_pos = head + (hit.position - head) * 0.85
	var target := Transform3D(Basis(), cam_pos)
	target = target.looking_at(head - right * 0.15 - Vector3.UP * 0.32, Vector3.UP)
	if not keep:
		_cam.global_transform = _prev_cam.global_transform
	_cam.make_current()
	create_tween().tween_property(_cam, "global_transform", target, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _next() -> void:
	_clear_choices()
	if _queue.is_empty():
		_end()
		return
	var item: Dictionary = _queue.pop_front()
	if item.has("choices"):
		_show_choices(item.choices)
		return
	if item.has("do"):
		(item.do as Callable).call()
		_next()
		return
	# 여러 사람이 말하면 말하는 사람 쪽으로 카메라를 옮긴다
	if item.has("at") and item.at != _speaker and is_instance_valid(item.at):
		_speaker = item.at
		_frame_camera(true)
	_name.text = item.get("who", "")
	_line.text = item.text
	_line.visible_ratio = 0.0
	_typing = 0.0
	_cont.visible = false
	if _speaker and _speaker.has_method("gesture"):
		_speaker.gesture(item.get("anim", ["talk", "explain", "talk"].pick_random()))
	Sfx.play("select", -18.0, 0.8)


func _show_choices(list: Array) -> void:
	_choosing = true
	_cont.visible = false
	var style: Button = $ChoiceStyle
	for i in list.size():
		var b := style.duplicate() as Button
		b.visible = true
		b.text = "%d.  %s" % [i + 1, list[i][0]]
		b.pressed.connect(_pick.bind(list[i]))
		_choices.add_child(b)
	(_choices.get_child(0) as Button).grab_focus()


func _pick(choice: Array) -> void:
	if not _choosing:
		return
	_choosing = false
	Sfx.play("click", -6.0)
	var follow: Array = choice[1] if choice.size() > 1 and choice[1] != null else []
	_queue = follow.duplicate(true) + _queue
	_next()


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()


func _process(delta: float) -> void:
	if not active:
		return
	_cool -= delta
	if _line.visible_ratio < 1.0:
		_typing += delta * CPS
		_line.visible_characters = int(_typing)
		if _line.visible_characters >= _line.get_total_character_count():
			_line.visible_ratio = 1.0
	else:
		_cont.visible = not _choosing
	# 말하는 사람이 플레이어를 본다
	if _speaker and is_instance_valid(_speaker):
		var to := player.global_position - _speaker.global_position
		_speaker.rotation.y = lerp_angle(_speaker.rotation.y, atan2(-to.x, -to.z), 6.0 * delta)


func _input(event: InputEvent) -> void:
	if not active or _cool > 0.0:
		return
	var advance := false
	if event is InputEventKey and event.pressed and not event.echo:
		if _choosing and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var i: int = event.keycode - KEY_1
			if i < _choices.get_child_count():
				(_choices.get_child(i) as Button).pressed.emit()
			get_viewport().set_input_as_handled()
			return
		advance = event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _choosing:
		advance = true
	if not advance or _choosing:
		return
	get_viewport().set_input_as_handled()
	if _line.visible_ratio < 1.0:
		_line.visible_ratio = 1.0
	else:
		_next()


func _end() -> void:
	active = false
	_choosing = false
	var tw := create_tween().set_parallel()
	tw.tween_property(_top, "offset_bottom", 0.0, 0.3)
	tw.tween_property(_bottom, "offset_top", 0.0, 0.3)
	tw.tween_property(_box, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(func():
		visible = false
		if _prev_cam and is_instance_valid(_prev_cam):
			_prev_cam.make_current()
		player.input_enabled = true
		_set_hud(true)
		player.capture_mouse()
		finished.emit())
