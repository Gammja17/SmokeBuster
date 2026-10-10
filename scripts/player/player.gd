class_name Player
extends CharacterBody3D
## 1인칭 단속반원. WASD/Shift/Space, 좌클릭 발사, 1~5/휠 무기 교체, E 소화전에서 물 채우기, F 소방차.

signal ammo_changed(id: String, current: float, maximum: float)
signal weapon_changed(id: String)
signal mental_changed(current: int, maximum: int)
signal hydrant_nearby(near: bool)
signal hurt(amount: int)
signal call_truck

const WALK_SPEED := 5.0
const SPRINT_MULT := 1.55
const JUMP_VELOCITY := 4.8
const MOUSE_SENS := 0.0022

var water: WaterSystem
var hydrants: Array[Vector3] = []
var input_enabled := true
var slowed := false

var mental := 5
var current := "spray"
var ammo := {}

var camera: Camera3D
var _view: Node3D
var _models := {}
var _muzzles := {}
var _loop_players := {}
var _fire_cd := 0.0
var _stream_t := 0.0
var _bob_t := 0.0
var _step_dist := 0.0
var _sway := Vector2.ZERO
var _kick := 0.0
var _shake := 0.0
var _invuln := 0.0
var _knock := Vector3.ZERO
var _near_hydrant := false
var _refilling := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.875
	add_child(col)

	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.fov = 78
	camera.near = 0.03
	camera.far = 170
	add_child(camera)

	_view = Node3D.new()
	camera.add_child(_view)
	_build_models()

	mental = Game.max_mental()
	for id in Game.WEAPON_ORDER:
		ammo[id] = Game.weapon_stat(id, "tank")
	_loop_players["stream"] = Sfx.loop_player("stream", self, -4.0)
	_loop_players["hose"] = Sfx.loop_player("hose", self, -2.0)
	equip("spray")


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- 입력

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-88), deg_to_rad(88))
		_sway += event.relative * 0.0004
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode
		if k >= KEY_1 and k <= KEY_5:
			var id: String = Game.WEAPON_ORDER[k - KEY_1]
			if id in Game.owned:
				equip(id)
		elif k == KEY_F and Game.has_truck:
			call_truck.emit()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)
		elif event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_try_single_fire()


func _cycle(dir: int) -> void:
	var list: Array = []
	for id in Game.WEAPON_ORDER:
		if id in Game.owned:
			list.append(id)
	if list.size() <= 1:
		return
	var i := list.find(current)
	equip(list[(i + dir + list.size()) % list.size()])


func equip(id: String) -> void:
	_stop_loops()
	current = id
	for k in _models:
		_models[k].visible = k == id
	_models[id].position.y = -0.3
	var tw := create_tween()
	tw.tween_property(_models[id], "position:y", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("switch", -6.0)
	weapon_changed.emit(id)
	_emit_ammo()


# ---------------------------------------------------------------- 매 프레임

func _physics_process(delta: float) -> void:
	_fire_cd -= delta
	_invuln -= delta

	if not is_on_floor():
		velocity.y -= 16.0 * delta
	var input := Vector2.ZERO
	var sprint := false
	if input_enabled:
		if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = JUMP_VELOCITY
		if Input.is_key_pressed(KEY_W): input.y -= 1
		if Input.is_key_pressed(KEY_S): input.y += 1
		if Input.is_key_pressed(KEY_A): input.x -= 1
		if Input.is_key_pressed(KEY_D): input.x += 1
		sprint = Input.is_key_pressed(KEY_SHIFT) and input.y < 0
	var speed := WALK_SPEED * Game.move_speed_mult() * (SPRINT_MULT if sprint else 1.0) * (0.55 if slowed else 1.0)
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var accel := 14.0 if is_on_floor() else 4.0
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * speed * delta)
	velocity += _knock
	_knock = Vector3.ZERO
	move_and_slide()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspeed > 0.5:
		_step_dist += hspeed * delta
		if _step_dist > (2.6 if sprint else 2.0):
			_step_dist = 0.0
			Sfx.play("step", -14.0)
	camera.fov = lerp(camera.fov, 86.0 if sprint and hspeed > 4 else 78.0, 6.0 * delta)

	_update_hydrant(delta)
	_update_fire(delta)
	_update_view(delta, hspeed)


func _update_view(delta: float, hspeed: float) -> void:
	_bob_t += delta * (hspeed * 1.6 if is_on_floor() else 0.0)
	var bob: Vector3 = Vector3(sin(_bob_t) * 0.012, abs(cos(_bob_t)) * 0.015, 0) * clamp(hspeed / 5.0, 0, 1.5)
	_sway = _sway.lerp(Vector2.ZERO, 8.0 * delta)
	_kick = lerp(_kick, 0.0, 10.0 * delta)
	_view.position = Vector3(-_sway.x - bob.x, _sway.y - bob.y, _kick * 0.08)
	_view.rotation.x = _kick * 0.12
	_shake = max(_shake - delta * 2.0, 0.0)
	camera.h_offset = randf_range(-1, 1) * _shake * _shake * 0.15
	camera.v_offset = randf_range(-1, 1) * _shake * _shake * 0.15


# ---------------------------------------------------------------- 발사

func _wants_fire() -> bool:
	return input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _refilling


func _try_single_fire() -> void:
	if not input_enabled or _refilling or _fire_cd > 0.0:
		return
	var w: Dictionary = Game.WEAPONS[current]
	if w.mode == "stream":
		return
	if ammo[current] < w.cost:
		Sfx.play("error", -8.0)
		return
	ammo[current] -= w.cost
	_fire_cd = w.interval
	if w.mode == "pump":
		_fire_drops(w, w.drops)
		Sfx.play("spray", -2.0)
		_kick = 0.5
		_pump_anim()
	else:
		_throw_bucket(w)
	_emit_ammo()


func _update_fire(delta: float) -> void:
	var w: Dictionary = Game.WEAPONS[current]
	if w.mode != "stream":
		return
	var firing: bool = _wants_fire() and ammo[current] > 0.0
	var lp: AudioStreamPlayer = _loop_players.get(w.loop)
	if firing:
		if lp and not lp.playing:
			lp.play()
		ammo[current] = max(ammo[current] - w.cost * delta, 0.0)
		_stream_t += delta
		while _stream_t >= w.interval:
			_stream_t -= w.interval
			_fire_drops(w, w.drops)
		_kick = max(_kick, 0.25 if current == "hose" else 0.12)
		if current == "hose":
			_shake = max(_shake, 0.35)
			# 반동으로 살짝 뒤로 밀림
			_knock -= camera.global_basis.z * -0.02
		_emit_ammo()
	else:
		_stream_t = 0.0
		if lp and lp.playing:
			lp.stop()
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and ammo[current] <= 0.0 and _fire_cd <= 0.0 and input_enabled:
			_fire_cd = 0.6
			Sfx.play("error", -10.0)


func _stop_loops() -> void:
	for k in _loop_players:
		_loop_players[k].stop()


func _aim_point() -> Vector3:
	var from := camera.global_position
	var to := from - camera.global_basis.z * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else to


func _fire_drops(w: Dictionary, count: int) -> void:
	var muzzle: Vector3 = _muzzles[current].global_position
	var target := _aim_point()
	var base_dir := (target - muzzle).normalized()
	# 너무 가까운 곳을 볼 때 총구 방향이 꺾이지 않게
	if (target - muzzle).length() < 2.0:
		base_dir = -camera.global_basis.z
	var speed := Game.weapon_stat(current, "speed")
	var soak := Game.weapon_stat(current, "soak")
	var spread: float = deg_to_rad(w.spread)
	var thick := 0.06 if w.mode == "pump" else (0.13 if current == "hose" else 0.08)
	for i in count:
		var d := base_dir.rotated(camera.global_basis.x, randf_range(-spread, spread)).rotated(camera.global_basis.y, randf_range(-spread, spread))
		var v := d * speed * randf_range(0.9, 1.05) + Vector3(velocity.x, 0, velocity.z) * 0.3
		water.spawn(muzzle, v, soak, w.knock, w.gravity, 0.0, thick)
	if current == "hose" and randf() < 0.3:
		water.mist_at(muzzle + base_dir * 0.5, base_dir * 3.0)


func _throw_bucket(w: Dictionary) -> void:
	var model: Node3D = _models["bucket"]
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", deg_to_rad(-70), 0.12)
	tw.tween_property(model, "rotation:x", 0.0, 0.35)
	var muzzle: Vector3 = _muzzles["bucket"].global_position
	var dir := (_aim_point() - muzzle).normalized()
	var v := dir * Game.weapon_stat("bucket", "speed") + Vector3.UP * 3.0
	water.spawn(muzzle, v, Game.weapon_stat("bucket", "soak"), w.knock, w.gravity, w.radius, 0.3)
	Sfx.play("spray", 0.0, 0.6)
	_kick = 1.0


func _pump_anim() -> void:
	var trig: Node3D = _models["spray"].get_node_or_null("Trigger")
	if trig:
		var tw := create_tween()
		tw.tween_property(trig, "rotation:x", deg_to_rad(25), 0.05)
		tw.tween_property(trig, "rotation:x", 0.0, 0.12)


func _emit_ammo() -> void:
	ammo_changed.emit(current, ammo[current], Game.weapon_stat(current, "tank"))


# ---------------------------------------------------------------- 소화전

func _update_hydrant(delta: float) -> void:
	var near := false
	for h in hydrants:
		if Vector2(h.x - global_position.x, h.z - global_position.z).length() < 2.6:
			near = true
			break
	if near != _near_hydrant:
		_near_hydrant = near
		hydrant_nearby.emit(near)
	_refilling = near and input_enabled and Input.is_key_pressed(KEY_E)
	if _refilling:
		var any := false
		for id in Game.owned:
			var cap := Game.weapon_stat(id, "tank")
			if ammo[id] < cap:
				ammo[id] = min(ammo[id] + cap * 0.7 * delta, cap)
				any = true
		if any:
			if Engine.get_physics_frames() % 12 == 0:
				Sfx.play("refill", -10.0, randf_range(0.9, 1.3))
				water.mist_at(global_position + Vector3.UP * 0.8 - global_basis.z * 0.6, Vector3.UP)
			_emit_ammo()


func refill_all() -> void:
	for id in Game.WEAPON_ORDER:
		ammo[id] = Game.weapon_stat(id, "tank")
	_emit_ammo()


# ---------------------------------------------------------------- 피해

func take_hit(amount: int, from: Vector3) -> void:
	if _invuln > 0.0:
		return
	_invuln = 0.9
	mental = max(mental - amount, 0)
	var dir := global_position - from
	dir.y = 0
	_knock = dir.normalized() * 9.0 + Vector3.UP * 3.0
	_shake = 1.0
	mental_changed.emit(mental, Game.max_mental())
	hurt.emit(amount)


func shake(amount: float) -> void:
	_shake = max(_shake, amount)


# ---------------------------------------------------------------- 무기 모델

func _build_models() -> void:
	_models["spray"] = _make_spray()
	_models["pistol"] = _make_blaster("res://assets/blaster/blaster-b.glb", 0.9, Vector3(0.2, -0.2, -0.42))
	_models["bucket"] = _make_bucket()
	_models["soaker"] = _make_soaker()
	_models["hose"] = _make_hose()
	for k in _models:
		_view.add_child(_models[k])
		_models[k].visible = false
		for m in _models[k].find_children("*", "GeometryInstance3D", true, false):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mat(c: Color, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = 0.4
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _cyl(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 16
	return c


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _add_muzzle(id: String, holder: Node3D, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.position = pos
	holder.add_child(m)
	_muzzles[id] = m


func _make_spray() -> Node3D:
	var h := Node3D.new()
	var root := Node3D.new()
	root.position = Vector3(0.24, -0.26, -0.45)
	root.rotation_degrees = Vector3(0, 8, 0)
	h.add_child(root)
	_mesh(root, _cyl(0.05, 0.055, 0.2), Vector3(0, 0, 0), _mat(Color(0.7, 0.9, 1.0, 0.55)))
	_mesh(root, _cyl(0.045, 0.045, 0.12), Vector3(0, -0.03, 0), _mat(Color(0.3, 0.6, 1.0, 0.7)))
	_mesh(root, _cyl(0.03, 0.04, 0.04), Vector3(0, 0.12, 0), _mat(Color(0.95, 0.95, 0.95)))
	_mesh(root, _boxm(Vector3(0.05, 0.06, 0.14)), Vector3(0, 0.17, -0.035), _mat(Color(0.2, 0.75, 0.5)))
	_mesh(root, _cyl(0.012, 0.012, 0.03), Vector3(0, 0.18, -0.115), _mat(Color(0.1, 0.1, 0.1)), Vector3(90, 0, 0))
	var trig := Node3D.new()
	trig.name = "Trigger"
	trig.position = Vector3(0, 0.15, -0.08)
	root.add_child(trig)
	_mesh(trig, _boxm(Vector3(0.025, 0.08, 0.02)), Vector3(0, -0.04, 0), _mat(Color(0.15, 0.6, 0.4)))
	_add_muzzle("spray", root, Vector3(0, 0.18, -0.14))
	return h


func _make_blaster(path: String, scl: float, pos: Vector3) -> Node3D:
	var h := Node3D.new()
	var m: Node3D = load(path).instantiate()
	m.scale = Vector3.ONE * scl
	m.position = pos
	m.rotation_degrees.y = 180
	h.add_child(m)
	var a := _aabb(m)
	_add_muzzle("pistol" if path.ends_with("-b.glb") else "soaker", h, pos + Vector3(0, (a.position.y + a.size.y * 0.72) * scl, -(a.size.z * 0.55) * scl))
	return h


func _make_soaker() -> Node3D:
	var h := _make_blaster("res://assets/blaster/blaster-d.glb", 0.75, Vector3(0.2, -0.2, -0.45))
	# 등에 메는 물통 대신 총 위에 큰 물탱크
	_mesh(h, _cyl(0.07, 0.07, 0.28), Vector3(0.2, -0.04, -0.4), _mat(Color(0.4, 0.75, 1.0, 0.75)), Vector3(90, 0, 0))
	return h


func _make_bucket() -> Node3D:
	var h := Node3D.new()
	var root := Node3D.new()
	root.position = Vector3(0.22, -0.32, -0.5)
	h.add_child(root)
	_mesh(root, _cyl(0.17, 0.13, 0.28), Vector3.ZERO, _mat(Color(0.6, 0.63, 0.68), 0.7))
	_mesh(root, _cyl(0.155, 0.155, 0.01), Vector3(0, 0.11, 0), _mat(Color(0.35, 0.65, 1.0, 0.85)))
	var handle := TorusMesh.new()
	handle.inner_radius = 0.16
	handle.outer_radius = 0.175
	_mesh(root, handle, Vector3(0, 0.14, 0), _mat(Color(0.3, 0.3, 0.32), 0.8), Vector3(0, 0, 90))
	_add_muzzle("bucket", root, Vector3(0, 0.2, -0.1))
	return h


func _make_hose() -> Node3D:
	var h := Node3D.new()
	var root := Node3D.new()
	root.position = Vector3(0.18, -0.25, -0.5)
	h.add_child(root)
	var brass := _mat(Color(0.85, 0.65, 0.25), 0.9)
	_mesh(root, _cyl(0.035, 0.05, 0.28), Vector3(0, 0, -0.1), brass, Vector3(-90, 0, 0))
	_mesh(root, _cyl(0.055, 0.055, 0.06), Vector3(0, 0, 0.06), _mat(Color(0.15, 0.15, 0.15)), Vector3(-90, 0, 0))
	_mesh(root, _boxm(Vector3(0.04, 0.12, 0.05)), Vector3(0, -0.08, 0.02), _mat(Color(0.15, 0.15, 0.15)))
	_mesh(root, _cyl(0.05, 0.05, 0.5), Vector3(0.02, -0.1, 0.3), _mat(Color(0.75, 0.12, 0.1)), Vector3(-60, 0, 0))
	_add_muzzle("hose", root, Vector3(0, 0, -0.26))
	return h


func _aabb(n: Node) -> AABB:
	var acc := [null]
	_collect(n, Transform3D.IDENTITY, acc, true)
	return acc[0] if acc[0] != null else AABB()


func _collect(n: Node, xf: Transform3D, acc: Array, is_root: bool) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * n.transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = t * n.mesh.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for c in n.get_children():
		_collect(c, t, acc, false)
