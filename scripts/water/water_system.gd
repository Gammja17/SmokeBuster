class_name WaterSystem
extends Node3D
## 물방울을 직접 날린다. 매 프레임 이전 위치→새 위치로 레이캐스트해서 사람/벽에 맞으면 처리.
## 그리기는 MultiMesh 하나로 (속도 방향으로 늘린 물줄기 조각).

signal npc_hit(npc: Node, amount: float)

const MAX_DROPS := 400
const MASK := 1 | 2     # 1: 월드, 2: 사람

var exclude: Array[RID] = []

var _pos: Array[Vector3] = []
var _vel: Array[Vector3] = []
var _life: Array[float] = []
var _soak: Array[float] = []
var _knock: Array[float] = []
var _grav: Array[float] = []
var _radius: Array[float] = []
var _thick: Array[float] = []

var _mm: MultiMesh
var _blobs: MultiMesh
var _splash: FxPool
var _mist: FxPool
var _puddles: Array[MeshInstance3D] = []
var _puddle_i := 0
var _wet_spots: Array = []   # [위치, 반지름, 마를 시각] 사람이 미끄러지는 곳


func _ready() -> void:
	add_to_group("water_system")
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.55, 0.82, 1.0, 0.7)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.3, 0.55, 0.8)

	var streak := SphereMesh.new()
	streak.radius = 0.5
	streak.height = 1.0
	streak.radial_segments = 6
	streak.rings = 3
	streak.material = water_mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = streak
	_mm.instance_count = MAX_DROPS
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 200, 400))
	add_child(mmi)

	var drop := SphereMesh.new()
	drop.radius = 0.045
	drop.height = 0.09
	drop.radial_segments = 6
	drop.rings = 3
	var drop_mat: StandardMaterial3D = water_mat.duplicate()
	drop_mat.vertex_color_use_as_albedo = true
	drop.material = drop_mat
	_splash = FxPool.new()
	_splash.setup(drop, 500, Color(0.6, 0.85, 1.0, 0.9))
	_splash.lifetime = 0.55
	_splash.gravity = Vector3(0, -12, 0)
	add_child(_splash)

	# 양동이/호스 물보라 (하얀 안개)
	var mist_mat := StandardMaterial3D.new()
	mist_mat.albedo_texture = FxPool.soft_puff()
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mist_mat.billboard_keep_scale = true
	mist_mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	quad.material = mist_mat
	_mist = FxPool.new()
	_mist.setup(quad, 150, Color(0.88, 0.95, 1.0, 0.6))
	_mist.lifetime = 0.9
	_mist.gravity = Vector3(0, 0.5, 0)
	_mist.drag = 2.0
	_mist.grow = 2.2
	add_child(_mist)

	var puddle_mat := StandardMaterial3D.new()
	puddle_mat.albedo_texture = load("res://assets/fx/circle_05.png")
	puddle_mat.albedo_color = Color(0.25, 0.45, 0.7, 0.5)
	puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle_mat.metallic = 0.6
	puddle_mat.roughness = 0.05
	for i in 60:
		var p := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE
		p.mesh = pm
		p.material_override = puddle_mat.duplicate()
		p.visible = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_puddles.append(p)


func spawn(pos: Vector3, vel: Vector3, soak: float, knock: float, gravity: float, radius := 0.0, thick := 0.08) -> void:
	if _pos.size() >= MAX_DROPS:
		return
	_pos.append(pos)
	_vel.append(vel)
	_life.append(2.5)
	_soak.append(soak)
	_knock.append(knock)
	_grav.append(gravity)
	_radius.append(radius)
	_thick.append(thick)


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _pos.size():
		var p := _pos[i]
		var v := _vel[i]
		v.y -= _grav[i] * delta
		var np := p + v * delta
		_life[i] -= delta
		var q := PhysicsRayQueryParameters3D.create(p, np, MASK, exclude)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_on_hit(i, hit)
			_remove(i)
			continue
		if _life[i] <= 0.0 or np.y < -2.0:
			_remove(i)
			continue
		_pos[i] = np
		_vel[i] = v
		i += 1
	_draw()


func _on_hit(i: int, hit: Dictionary) -> void:
	var point: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var v := _vel[i]
	var collider: Object = hit.collider
	if _radius[i] > 0.0:
		_area_splash(point, _radius[i], _soak[i], _knock[i])
		return
	if collider and collider.is_in_group("soakable"):
		collider.soak(_soak[i], v.normalized(), _knock[i])
		npc_hit.emit(collider, _soak[i])
		_burst(point, -v.normalized() * 0.5 + Vector3.UP, 4, 2.5)
	else:
		_burst(point, normal + v.normalized() * 0.3, 2, 2.0)
		if normal.y > 0.7 and randf() < 0.18:
			_puddle(point, randf_range(0.8, 1.6))


func _area_splash(point: Vector3, radius: float, soak: float, knock: float) -> void:
	Sfx.play_at("bucket", point, 2.0)
	_burst(point, Vector3.UP, 60, 5.0)
	for k in 12:
		_mist.emit(point + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * radius * 0.5,
			Vector3(randf_range(-1, 1), randf_range(0.5, 2), randf_range(-1, 1)), randf_range(1.0, 2.0))
	_puddle(Vector3(point.x, 0.13, point.z), radius * 1.4)
	for n in get_tree().get_nodes_in_group("soakable"):
		var center: Vector3 = n.incident_pos() if n.has_method("incident_pos") else n.global_position + Vector3.UP
		if n is Npc:
			center = n.global_position + Vector3.UP
		var d: float = center.distance_to(point)
		if d <= radius:
			var dir: Vector3 = n.global_position - point
			dir.y = 0
			var amount: float = soak * (1.0 - 0.4 * d / radius)
			n.soak(amount, dir.normalized(), knock)
			npc_hit.emit(n, amount)


func _burst(point: Vector3, dir: Vector3, count: int, speed: float) -> void:
	for k in count:
		var rv := (dir.normalized() + Vector3(randf_range(-0.8, 0.8), randf_range(-0.2, 0.8), randf_range(-0.8, 0.8))) * speed * randf_range(0.4, 1.0)
		_splash.emit(point, rv, randf_range(0.6, 1.4))


func mist_at(point: Vector3, vel: Vector3) -> void:
	_mist.emit(point, vel, randf_range(0.5, 1.0))


func is_wet(p: Vector3) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_wet_spots.size() - 1, -1, -1):
		var w: Array = _wet_spots[i]
		if now > w[2]:
			_wet_spots.remove_at(i)
			continue
		if Vector2(p.x - w[0].x, p.z - w[0].z).length() < w[1]:
			return true
	return false


func _puddle(point: Vector3, size: float) -> void:
	_wet_spots.append([point, size * 0.5, Time.get_ticks_msec() / 1000.0 + 8.0])
	if _wet_spots.size() > 80:
		_wet_spots.pop_front()
	var p := _puddles[_puddle_i]
	_puddle_i = (_puddle_i + 1) % _puddles.size()
	p.visible = true
	p.global_position = Vector3(point.x, point.y + 0.015 + randf() * 0.01, point.z)
	p.rotation.y = randf() * TAU
	p.scale = Vector3.ONE * size * 0.3
	var mat: StandardMaterial3D = p.material_override
	mat.albedo_color.a = 0.55
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector3.ONE * size, 0.25)
	tw.tween_interval(6.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 3.0)
	tw.tween_callback(func(): p.visible = false)


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	for arr in [_pos, _vel, _life, _soak, _knock, _grav, _radius, _thick]:
		arr[i] = arr[last]
		arr.remove_at(last)


func _draw() -> void:
	var n := _pos.size()
	_mm.visible_instance_count = n
	for i in n:
		var v := _vel[i]
		var speed := v.length()
		var t := _thick[i]
		var xf := Transform3D()
		if _radius[i] > 0.0:
			xf.basis = Basis().scaled(Vector3.ONE * 0.7)
		elif speed > 0.01:
			var z := v / speed
			var x := z.cross(Vector3.UP)
			if x.length_squared() < 0.001:
				x = Vector3.RIGHT
			x = x.normalized()
			var y := x.cross(z)
			var length: float = clamp(speed * 0.045, t, 1.4)
			xf.basis = Basis(x * t, y * t, z * length)
		xf.origin = _pos[i]
		_mm.set_instance_transform(i, xf)
