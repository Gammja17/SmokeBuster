class_name FxPool
extends MultiMeshInstance3D
## 원하는 위치/속도로 하나씩 뿌리는 간단한 파티클. MultiMesh 하나로 그린다.
## (Godot 4 의 CPUParticles3D 는 개별 입자를 쏠 수 없어서 직접 만든다)

var gravity := Vector3(0, -10, 0)
var lifetime := 0.5
var grow := 1.0           # 수명 끝에 크기 배율
var drag := 0.0
var max_count := 300

var _pos: PackedVector3Array = []
var _vel: PackedVector3Array = []
var _age: PackedFloat32Array = []
var _size: PackedFloat32Array = []
var _color: Color = Color.WHITE

static var _puff_tex: Texture2D


## 가장자리로 갈수록 투명해지는 하얀 동그라미 (연기/물보라용)
static func soft_puff() -> Texture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_puff_tex = t
	return _puff_tex


func setup(mesh: Mesh, count: int, color: Color) -> void:
	max_count = count
	_color = color
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 200, 400))


func emit(pos: Vector3, vel: Vector3, size := 1.0) -> void:
	if _pos.size() >= max_count:
		return
	_pos.append(pos)
	_vel.append(vel)
	_age.append(0.0)
	_size.append(size)


func _process(delta: float) -> void:
	var i := 0
	while i < _pos.size():
		_age[i] += delta
		if _age[i] >= lifetime:
			var last := _pos.size() - 1
			_pos[i] = _pos[last]; _vel[i] = _vel[last]; _age[i] = _age[last]; _size[i] = _size[last]
			_pos.resize(last); _vel.resize(last); _age.resize(last); _size.resize(last)
			continue
		_vel[i] = _vel[i] * (1.0 - drag * delta) + gravity * delta
		_pos[i] += _vel[i] * delta
		i += 1
	var n := _pos.size()
	multimesh.visible_instance_count = n
	for k in n:
		var t := _age[k] / lifetime
		var s: float = _size[k] * lerp(1.0, grow, t)
		multimesh.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * s), _pos[k]))
		var c := _color
		c.a *= 1.0 - t
		multimesh.set_instance_color(k, c)
