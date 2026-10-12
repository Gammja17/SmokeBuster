class_name Vehicle
extends CharacterBody3D
## 직접 모는 차. kind: police(사이렌), firetruck(지붕 물대포), civilian(뺏은 차), excavator(포크레인 팔)
## W/S 가속·후진, A/D 조향, Space 핸드브레이크, H 사이렌/경적, 좌클릭 물대포(소방차)/팔 내려찍기(포크레인), F 내리기

signal hit_npc(npc: Node, speed: float)

const STATS := {
	"police": {"model": "police", "max": 22.0, "accel": 12.0, "steer": 2.3},
	"firetruck": {"model": "firetruck", "max": 15.0, "accel": 7.0, "steer": 1.7},
	"civilian": {"model": "sedan", "max": 19.0, "accel": 10.0, "steer": 2.1},
	"excavator": {"model": "", "max": 7.0, "accel": 5.0, "steer": 1.5},
}
const MOUSE_SENS := 0.0025

var kind := "police"
var model_name := ""
var water: WaterSystem
var driver: Node3D = null
var speed := 0.0
var speed_mult := 1.0

var camera: Camera3D
var _pivot: Node3D
var _model: Node3D
var _yaw := 0.0
var _pitch := -0.25
var _look_idle := 0.0
var _siren: AudioStreamPlayer3D
var _engine: AudioStreamPlayer3D
var _lights: Array[OmniLight3D] = []
var _siren_on := false
var _cannon: Node3D
var _spray_t := 0.0
var _honk_cd := 0.0
var _bump_cd := 0.0
var _stream: AudioStreamPlayer
var _boom: Node3D
var _swinging := false


func _ready() -> void:
	add_to_group("vehicle")
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.5
	var st: Dictionary = STATS[kind]
	if model_name == "":
		model_name = st.model
	if kind == "excavator":
		_model = _build_excavator()
	else:
		_model = load("res://assets/cars/%s.glb" % model_name).instantiate()
		var scl := 2.2 if kind == "firetruck" else 1.6
		_model.scale = Vector3.ONE * scl
		_model.rotation.y = PI
	add_child(_model)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = {"firetruck": Vector3(3.2, 3.2, 7.4), "excavator": Vector3(2.8, 2.8, 4.4)}.get(kind, Vector3(2.4, 2.0, 4.6))
	col.shape = box
	col.position.y = box.size.y / 2 + 0.1
	add_child(col)

	# 3인칭 추격 카메라: 차를 따라가지만 회전은 따로 (마우스로 둘러보기)
	_pivot = Node3D.new()
	_pivot.top_level = true
	add_child(_pivot)
	camera = Camera3D.new()
	camera.fov = 72
	camera.far = 170
	camera.position = Vector3(0, 1.0, 9.5 if kind in ["firetruck", "excavator"] else 7.0)
	_pivot.add_child(camera)

	if kind == "police":
		for side in [-1, 1]:
			var l := OmniLight3D.new()
			l.light_color = Color(1, 0.15, 0.1) if side < 0 else Color(0.2, 0.3, 1)
			l.light_energy = 0.0
			l.omni_range = 7.0
			l.position = Vector3(side * 0.5, 2.3, 0)
			add_child(l)
			_lights.append(l)
		_siren = Sfx.loop_player_3d("siren", self, 2.0)
	if kind == "firetruck":
		_cannon = Node3D.new()
		_cannon.position = Vector3(0, 3.9, -1.0)
		add_child(_cannon)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.18
		cm.height = 1.2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.65, 0.25)
		mat.metallic = 0.8
		cm.material = mat
		mi.mesh = cm
		mi.rotation_degrees.x = -90
		mi.position.z = -0.5
		_cannon.add_child(mi)
		_stream = Sfx.loop_player("hose", self, -2.0)


func _build_excavator() -> Node3D:
	## 포크레인: 궤도, 노란 몸통, 운전석, 앞으로 뻗은 붐-암-버킷 (팔은 _boom 을 돌려 휘두른다)
	var root := Node3D.new()
	var yellow := Mats.flat(Color(0.98, 0.72, 0.08), 0.45, 0.2)
	var dark := Mats.flat(Color(0.12, 0.12, 0.13), 0.8)
	var steel := Mats.flat(Color(0.35, 0.35, 0.37), 0.4, 0.7)
	for side in [-1, 1]:
		_part(root, Vector3(0.8, 0.8, 4.2), Vector3(side * 1.05, 0.45, 0), dark)
	_part(root, Vector3(2.6, 1.1, 3.0), Vector3(0, 1.4, 0.4), yellow)
	_part(root, Vector3(2.4, 0.9, 0.7), Vector3(0, 1.3, 1.9), Mats.flat(Color(0.3, 0.3, 0.3), 0.6))
	var cab := _part(root, Vector3(1.2, 1.4, 1.3), Vector3(-0.55, 2.6, -0.3), yellow)
	_part(cab, Vector3(1.0, 0.9, 0.05), Vector3(0, 0.15, -0.66), Mats.glass())
	_boom = Node3D.new()
	_boom.position = Vector3(0.45, 2.1, -0.9)
	_boom.rotation_degrees.x = 28.0
	root.add_child(_boom)
	_part(_boom, Vector3(0.45, 0.5, 3.6), Vector3(0, 0, -1.8), yellow)
	var stick := Node3D.new()
	stick.position = Vector3(0, 0, -3.6)
	stick.rotation_degrees.x = -70.0
	_boom.add_child(stick)
	_part(stick, Vector3(0.35, 0.4, 2.6), Vector3(0, 0, -1.3), yellow)
	var bucket := _part(stick, Vector3(1.1, 0.7, 0.7), Vector3(0, -0.2, -2.7), steel)
	for i in 4:
		_part(bucket, Vector3(0.12, 0.12, 0.3), Vector3(-0.4 + i * 0.27, -0.35, -0.3), steel)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.6, 0.1)
	light.light_energy = 1.2
	light.omni_range = 4.0
	light.position = Vector3(-0.55, 3.45, -0.3)
	root.add_child(light)
	_lights.append(light)
	return root


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _swing() -> void:
	## 팔을 들었다가 콱 내려찍는다. 찍힌 자리 근처 불법업소 간판은 떨어지고 소품은 날아간다
	if _swinging:
		return
	_swinging = true
	var tw := create_tween()
	tw.tween_property(_boom, "rotation_degrees:x", 48.0, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_boom, "rotation_degrees:x", 2.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_arm_hit)
	tw.tween_interval(0.25)
	tw.tween_property(_boom, "rotation_degrees:x", 28.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): _swinging = false)
	Sfx.play_at("switch", global_position, 0.0, 0.5)


func _arm_hit() -> void:
	var fwd := -global_basis.z
	var hit := global_position + fwd * 5.5 + Vector3.UP * 2.5
	Sfx.play_at("thud", hit, 8.0, 0.6)
	Sfx.play_at("kick", hit, 4.0, 0.5)
	if driver and driver.has_method("shake"):
		driver.shake(0.7)
	for shop in get_tree().get_nodes_in_group("illegal_shop"):
		if not shop.done and shop.incident_pos().distance_to(hit) < 5.5:
			shop.on_rammed()
	for body in get_parent().get_children():
		if body is RigidBody3D and body.global_position.distance_to(hit) < 4.0:
			body.apply_central_impulse((body.global_position - global_position).normalized() * 30.0 + Vector3.UP * 12.0)


func can_enter(p: Node3D) -> bool:
	return driver == null and global_position.distance_to(p.global_position) < 3.6 + (1.5 if kind == "firetruck" else 0.0)


func enter(p: Node3D) -> void:
	driver = p
	_yaw = rotation.y
	_pitch = -0.25
	camera.current = true
	Sfx.play("switch", -4.0, 0.8)


func exit() -> Vector3:
	## 내리면 운전석 옆자리 위치를 돌려준다
	driver = null
	speed = 0.0
	if _stream:
		_stream.stop()
	var side := global_basis.x * -(2.2 if kind != "firetruck" else 2.8)
	return global_position + side + Vector3.UP * 0.3


func _unhandled_input(event: InputEvent) -> void:
	if driver == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENS, -0.9, 0.35)
		_look_idle = 0.0
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and kind == "excavator":
		_swing()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		if kind == "police":
			_siren_on = not _siren_on
			if _siren_on:
				_siren.play()
			else:
				_siren.stop()
		elif _honk_cd <= 0.0:
			_honk_cd = 0.6
			Sfx.play_at("horn", global_position, 0.0)


func _physics_process(delta: float) -> void:
	_honk_cd -= delta
	_bump_cd -= delta
	var st: Dictionary = STATS[kind]
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false
	if driver:
		if Input.is_key_pressed(KEY_W): throttle += 1.0
		if Input.is_key_pressed(KEY_S): throttle -= 1.0
		if Input.is_key_pressed(KEY_A): steer += 1.0
		if Input.is_key_pressed(KEY_D): steer -= 1.0
		handbrake = Input.is_key_pressed(KEY_SPACE)

	if throttle > 0.0:
		speed = move_toward(speed, st.max * speed_mult, st.accel * delta * (1.0 if speed >= 0.0 else 2.0))
	elif throttle < 0.0:
		speed = move_toward(speed, -st.max * 0.4, st.accel * delta * (2.0 if speed > 0.0 else 1.0))
	else:
		speed = move_toward(speed, 0.0, 4.0 * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, 18.0 * delta)

	# 속도에 비례해서 꺾인다 (서 있으면 안 돎)
	var turn: float = steer * st.steer * clamp(abs(speed) / 6.0, 0.0, 1.0) * sign(speed if speed != 0.0 else 1.0)
	if handbrake:
		turn *= 1.6
	rotation.y += turn * delta

	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5
	var fwd := -global_basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	var before := speed
	move_and_slide()
	_handle_collisions(before)

	# 차체 기울기 (꺾을 때 살짝 기운다)
	_model.rotation.z = lerp(_model.rotation.z, -turn * 0.06, 6.0 * delta)

	_hit_people()
	_update_lights(delta)
	if kind == "firetruck":
		_update_cannon(delta)


func _process(delta: float) -> void:
	if driver == null:
		return
	# 카메라는 차를 부드럽게 따라가고, 마우스를 놓고 있으면 차 뒤로 돌아온다
	_look_idle += delta
	if _look_idle > 1.2 and abs(speed) > 2.0:
		_yaw = lerp_angle(_yaw, rotation.y, 2.5 * delta)
	_pivot.global_position = _pivot.global_position.lerp(global_position + Vector3.UP * (3.2 if kind == "firetruck" else 2.0), 12.0 * delta)
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	camera.fov = lerp(camera.fov, 72.0 + clamp(abs(speed) - 10.0, 0.0, 12.0), 4.0 * delta)


func _handle_collisions(before: float) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other is RigidBody3D:
			other.apply_central_impulse(-c.get_normal() * max(abs(before), 2.0) * 1.5)
			continue
		if other and other.has_method("on_rammed") and abs(before) > 4.0:
			other.on_rammed()
			if driver and driver.has_method("shake"):
				driver.shake(0.8)
		# 벽에 세게 부딪치면 튕긴다
		if abs(c.get_normal().y) < 0.5 and abs(before) > 6.0 and _bump_cd <= 0.0:
			_bump_cd = 0.4
			speed = -before * 0.25
			Sfx.play_at("thud", global_position, 4.0)
			if driver and driver.has_method("shake"):
				driver.shake(0.6)


func _hit_people() -> void:
	if abs(speed) < 3.0:
		return
	var fwd: Vector3 = -global_basis.z * sign(speed)
	var reach := 3.4 if kind == "firetruck" else 2.6
	for n in get_tree().get_nodes_in_group("npc"):
		var to: Vector3 = n.global_position - global_position
		to.y = 0
		if to.length() > reach + 1.0:
			continue
		var ahead := to.dot(fwd)
		var side: float = abs(to.dot(global_basis.x))
		if ahead > 0.0 and ahead < reach and side < 1.4:
			hit_npc.emit(n, abs(speed))


func _update_lights(delta: float) -> void:
	if _lights.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.008
	if kind == "excavator":
		_lights[0].light_energy = (2.0 if sin(t * 0.8) > 0.0 else 0.2) if driver else 0.0
		return
	for i in _lights.size():
		_lights[i].light_energy = (3.0 if sin(t + i * PI) > 0.0 else 0.0) if _siren_on else 0.0


func _update_cannon(delta: float) -> void:
	if driver == null:
		return
	# 물대포는 카메라가 보는 곳을 향한다
	var from := camera.global_position
	var to := from - camera.global_basis.z * 70.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit.position if not hit.is_empty() else to
	_cannon.look_at(target, Vector3.UP)
	var firing := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if firing:
		if not _stream.playing:
			_stream.play()
		_spray_t += delta
		while _spray_t > 0.018:
			_spray_t -= 0.018
			var muzzle := _cannon.global_position - _cannon.global_basis.z * 1.1
			var dir := (target - muzzle).normalized().rotated(Vector3.UP, randf_range(-0.03, 0.03))
			water.spawn(muzzle, dir * 30.0 + Vector3.UP * 1.5, 0.09, 3.0, 9.0, 0.0, 0.2)
		if driver.has_method("shake"):
			driver.shake(0.2)
	elif _stream.playing:
		_stream.stop()
