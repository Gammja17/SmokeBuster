class_name TrafficCar
extends AnimatableBody3D
## 바깥 순환 도로를 도는 차. 앞에 플레이어가 있으면 멈추고 빵빵.
## drunk = true 면 비틀비틀 달리는 음주운전 의심 차량. 사진 찍으면 갓길에 서고 경찰차가 온다.

signal resolved(car: TrafficCar, task: String)

const MODELS := ["sedan", "taxi", "suv", "van", "delivery", "hatchback-sports", "garbage-truck"]
const DRUNK_LIFETIME := 70.0

var half := 51.5
var clockwise := true
var player: Node3D
var speed := 9.0
var drunk := false
var police := false
var done := false

var _model: Node3D
var _corners: Array[Vector3] = []
var _next := 0
var _cur_speed := 0.0
var _honk_cd := 0.0
var _t := 0.0
var _label: Label3D
var _stopped := false


func setup(p_half: float, p_clockwise: bool, start_index: int, p_player: Node3D) -> void:
	half = p_half
	clockwise = p_clockwise
	player = p_player
	var c := [Vector3(-half, 0.02, -half), Vector3(half, 0.02, -half), Vector3(half, 0.02, half), Vector3(-half, 0.02, half)]
	if not clockwise:
		c.reverse()
	for p in c:
		_corners.append(p)
	var a := _corners[start_index % 4]
	var b := _corners[(start_index + 1) % 4]
	position = a.lerp(b, randf_range(0.1, 0.8))
	_next = (start_index + 1) % 4
	speed = randf_range(8.0, 11.0)


func _ready() -> void:
	sync_to_physics = false
	var model_name: String = "police" if police else MODELS.pick_random()
	_model = load("res://assets/cars/%s.glb" % model_name).instantiate()
	_model.scale = Vector3.ONE * 1.6
	_model.rotation.y = PI
	add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mi.visibility_range_end = 110.0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.0, 4.6)
	col.shape = box
	col.position.y = 1.0
	add_child(col)
	var target := _corners[_next]
	look_at(Vector3(target.x, position.y, target.z), Vector3.UP)

	if drunk:
		add_to_group("incident")
		_label = Label3D.new()
		_label.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
		_label.text = "비틀비틀 (음주운전 의심)"
		_label.font_size = 56
		_label.pixel_size = 0.008
		_label.outline_size = 12
		_label.modulate = Game.TASKS.drunk.color
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.position.y = 3.4
		add_child(_label)
		speed = 10.0
	if police:
		var light := OmniLight3D.new()
		light.light_energy = 3.0
		light.omni_range = 8.0
		light.position = Vector3(0, 2.6, 0)
		add_child(light)
		var tw := create_tween().set_loops()
		tw.tween_property(light, "light_color", Color(0.2, 0.3, 1), 0.2)
		tw.tween_property(light, "light_color", Color(1, 0.15, 0.1), 0.2)
		Sfx.loop_player_3d("siren", self, 0.0).play()


func _physics_process(delta: float) -> void:
	_t += delta
	_honk_cd -= delta
	if drunk and not done and _t > DRUNK_LIFETIME:
		# 못 잡고 놓쳤다
		queue_free()
		return
	var target := _corners[_next]
	var to := target - global_position
	to.y = 0
	if to.length() < 0.5:
		_next = (_next + 1) % 4
		return
	var dir := to.normalized()
	var want := speed
	if drunk and not done:
		# 속도도 들쭉날쭉
		want = speed * (0.7 + 0.5 * abs(sin(_t * 0.7)))
		if _honk_cd <= 0.0 and randf() < 0.01:
			_honk_cd = 2.0
			Sfx.play_at("horn", global_position, -2.0, 0.85)
	if _stopped:
		want = 0.0
	elif player:
		var rel := player.global_position - global_position
		var ahead := rel.dot(dir)
		var lateral := (rel - dir * ahead).length()
		if ahead > 0.0 and ahead < 8.0 and lateral < 2.0:
			want = 0.0
			if _honk_cd <= 0.0:
				_honk_cd = 3.0
				Sfx.play_at("horn", global_position, -2.0)
	_cur_speed = move_toward(_cur_speed, want, 14.0 * delta)
	global_position += dir * min(_cur_speed * delta, to.length())
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, 6.0 * delta)

	if drunk:
		# 차체만 좌우로 비틀 (충돌 박스는 차선 그대로)
		var weave := 0.0 if _stopped else sin(_t * 1.4) * 1.3 + sin(_t * 3.7) * 0.3
		_model.position.x = lerp(_model.position.x, weave, 4.0 * delta)
		_model.rotation.y = PI + (0.0 if _stopped else cos(_t * 1.4) * 0.22)


# ---------------------------------------------------------------- 사건 인터페이스

func task() -> String:
	return "drunk" if drunk else ""


func is_active_incident() -> bool:
	return drunk and not done


func incident_pos() -> Vector3:
	return global_position + Vector3.UP * 1.2


func photo_task() -> String:
	return "drunk" if is_active_incident() else ""


func wants_water() -> bool:
	return false


func on_photographed() -> void:
	if done:
		return
	done = true
	_stopped = true
	remove_from_group("incident")
	_label.text = "신고 접수! 경찰 출동"
	_label.modulate = Color(0.6, 1, 0.6)
	resolved.emit(self, "drunk")
	# 뒤에서 경찰차가 와서 세운다
	var cop := TrafficCar.new()
	cop.police = true
	cop.half = half
	cop.clockwise = clockwise
	cop.player = player
	cop._corners = _corners
	cop._next = _next
	cop.speed = 16.0
	get_parent().add_child(cop)
	var back := -(_corners[_next] - global_position).normalized()
	cop.global_position = global_position + back * 18.0
	cop.look_at(global_position, Vector3.UP)
	cop.call_deferred("_chase", self)
	get_tree().create_timer(9.0).timeout.connect(_fade)


func _chase(target_car: TrafficCar) -> void:
	# 경찰차는 음주 차 6m 뒤에서 멈춘다
	while is_instance_valid(target_car) and is_inside_tree():
		if global_position.distance_to(target_car.global_position) < 6.0:
			_stopped = true
		await get_tree().physics_frame
	_fade()


func _fade() -> void:
	if not is_inside_tree():
		return
	collision_layer = 0
	var tw := create_tween()
	tw.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.5)
	tw.tween_callback(queue_free)
