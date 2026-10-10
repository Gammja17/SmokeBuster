class_name CityBuilder
extends RefCounted
## 2x2 블록 동네를 만든다. 도로 3x3 격자, 블록마다 건물/골목 안뜰, 한 블록은 공원.
## 만든 뒤 보행자 길 그래프, 흡연 장소, 소화전 위치를 돌려준다.

const PITCH := 54.0          # 도로 중심 간격
const ROAD_W := 10.0
const BLOCK_HALF := 22.0     # 블록(인도 포함) 반 크기
const WALK := 20.0           # 보행자 길(인도 중앙) 반 크기
const INNER := 18.0          # 건물이 서는 안쪽 반 크기
const EDGE := 63.0           # 바깥 인도 끝

const BUILDINGS := [
	"building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g",
	"building-h", "building-i", "building-j", "building-k", "building-l", "building-m", "building-n",
]
const TALL := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-e"]
const PARKED := ["sedan", "suv", "taxi", "van", "hatchback-sports", "sedan-sports", "suv-luxury", "delivery", "truck"]

var root: Node3D
var nav_nodes: Array[Vector3] = []
var nav_edges := {}          # index -> Array[int]
var spots: Array = []        # {pos: Vector3, kind: String, busy: bool}
var hydrants: Array[Vector3] = []
var block_centers: Array[Vector2] = []
var park_center := Vector2.ZERO
var ring_lanes: Array = []   # 자동차가 도는 사각 경로 [half, clockwise]

var _aabb_cache := {}
var _mats := {}
var rng := RandomNumberGenerator.new()


func build(parent: Node3D, seed_value := 1234) -> void:
	rng.seed = seed_value
	root = Node3D.new()
	root.name = "City"
	parent.add_child(root)

	_ground()
	_roads()
	for bx in [-1, 1]:
		for bz in [-1, 1]:
			block_centers.append(Vector2(bx, bz) * PITCH / 2)
	park_center = block_centers[2]
	for c in block_centers:
		_block_slab(c)
		if c == park_center:
			_park(c)
		else:
			_building_block(c, rng.randi_range(0, 3))
		_sidewalk_props(c)
	_outer_ring()
	_parked_cars()
	_nav_graph()
	ring_lanes = [[PITCH - 2.5, true], [PITCH + 2.5, false]]


# ---------------------------------------------------------------- 기본 바닥/도로

func _ground() -> void:
	_box(Vector3(260, 1, 260), Vector3(0, -0.5, 0), Color(0.24, 0.25, 0.27), true)
	# 보이지 않는 경계 벽
	for s in [-1, 1]:
		_wall(Vector3(1, 20, 140), Vector3(s * (EDGE + 1), 10, 0))
		_wall(Vector3(140, 20, 1), Vector3(0, 10, s * (EDGE + 1)))


func _roads() -> void:
	var lines := [-PITCH, 0.0, PITCH]
	var seg := PITCH - ROAD_W     # 교차로 사이 길이 (44)
	var tiles := 4
	var tile_len := seg / tiles
	for c in lines:
		for k in range(2):
			var start: float = lines[k] + ROAD_W / 2
			for i in tiles:
				var along: float = start + tile_len * (i + 0.5)
				var model := "road-crossing" if (i == 0 or i == tiles - 1) else "road-straight"
				# 도로 타일은 X 방향으로 뻗어 있다. 세로 도로 (x = c) 는 90도 돌린다
				_prop("roads/" + model, Vector3(c, 0.01, along), 90.0, Vector3(tile_len, ROAD_W, ROAD_W), false)
				# 가로 도로 (z = c)
				_prop("roads/" + model, Vector3(along, 0.01, c), 0.0, Vector3(tile_len, ROAD_W, ROAD_W), false)
	for x in lines:
		for z in lines:
			_prop("roads/road-square", Vector3(x, 0.01, z), 0.0, Vector3.ONE * ROAD_W, false)


func _block_slab(c: Vector2) -> void:
	_box(Vector3(BLOCK_HALF * 2, 0.06, BLOCK_HALF * 2), Vector3(c.x, 0.03, c.y), Color(0.66, 0.64, 0.6), false)
	# 연석 테두리
	for s in [-1, 1]:
		_box(Vector3(BLOCK_HALF * 2 + 0.3, 0.16, 0.3), Vector3(c.x, 0.08, c.y + s * BLOCK_HALF), Color(0.8, 0.8, 0.78), false)
		_box(Vector3(0.3, 0.16, BLOCK_HALF * 2 + 0.3), Vector3(c.x + s * BLOCK_HALF, 0.08, c.y), Color(0.8, 0.8, 0.78), false)


# ---------------------------------------------------------------- 건물 블록

func _building_block(c: Vector2, turn: int) -> void:
	## 북/남 줄에 3채씩, 서쪽 1채, 동쪽은 골목 입구. turn 만큼 90도씩 돌린다.
	var block := Node3D.new()
	block.position = Vector3(c.x, 0.06, c.y)
	block.rotation_degrees.y = turn * 90.0
	root.add_child(block)

	var slot := 12.0
	for i in 3:
		var x := -slot + i * slot
		_building(block, Vector3(x, 0, -slot), 180.0, slot)   # 북쪽 줄, 정면이 -Z
		_building(block, Vector3(x, 0, slot), 0.0, slot)      # 남쪽 줄, 정면이 +Z
	_building(block, Vector3(-slot, 0, 0), -90.0, slot)

	# 안뜰 바닥과 소품
	_box_in(block, Vector3(24, 0.05, 12), Vector3(6, 0.02, 0), Color(0.42, 0.4, 0.38), false)
	_prop_in(block, "roads/dumpster", Vector3(-2.5, 0, -4.6), 0.0, 6.5, true)
	_prop_in(block, "roads/dumpster", Vector3(1.0, 0, -4.6), 0.0, 6.5, true)
	_prop_in(block, "cars/box", Vector3(-4.5, 0, 4.2), 20.0, 1.2, true)
	_prop_in(block, "cars/box", Vector3(-4.0, 0.85, 4.5), -15.0, 1.0, true)
	_prop_in(block, "roads/construction-light", Vector3(5.5, 0, 5.2), 0.0, 6.0, false)
	_no_smoking_sign(block, Vector3(17.5, 0, -6.2), 0.0)

	for p in [Vector3(-1.0, 0, -2.5), Vector3(3.0, 0, 1.5), Vector3(-3.5, 0, 1.8), Vector3(9.0, 0, -3.5)]:
		spots.append({"pos": _local_to_world(block, p), "kind": "alley", "busy": false})


func _building(parent: Node3D, pos: Vector3, rot: float, slot: float) -> void:
	var tall := rng.randf() < 0.25
	var name: String = (TALL if tall else BUILDINGS)[rng.randi_range(0, (TALL if tall else BUILDINGS).size() - 1)]
	var aabb := _model_aabb("commercial/" + name)
	var sx := aabb.size.x
	var sz := aabb.size.z
	var s: float = min(slot / sx, slot / sz) * 0.98
	if tall:
		s = min(s, 9.0)
	var node := _instance("commercial/" + name)
	node.scale = Vector3.ONE * s
	node.rotation_degrees.y = rot
	# 건물 바닥 중심이 slot 중심에 오도록
	var center := Vector3(aabb.get_center().x, 0, aabb.get_center().z) * s
	node.position = pos - Basis(Vector3.UP, deg_to_rad(rot)) * center
	parent.add_child(node)
	# 충돌 박스는 slot 전체
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, aabb.size.y * s / 2, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(slot, aabb.size.y * s, slot)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


# ---------------------------------------------------------------- 공원

func _park(c: Vector2) -> void:
	var park := Node3D.new()
	park.position = Vector3(c.x, 0.06, c.y)
	root.add_child(park)
	_box_in(park, Vector3(INNER * 2, 0.06, INNER * 2), Vector3(0, 0.03, 0), Color(0.36, 0.62, 0.3), false)
	# 십자 산책로
	_box_in(park, Vector3(INNER * 2, 0.07, 3.0), Vector3(0, 0.035, 0), Color(0.78, 0.7, 0.55), false)
	_box_in(park, Vector3(3.0, 0.07, INNER * 2), Vector3(0, 0.035, 0), Color(0.78, 0.7, 0.55), false)
	# 가운데 분수
	var fountain := _cyl_in(park, 3.0, 0.7, Vector3(0, 0.35, 0), Color(0.7, 0.72, 0.75), true)
	fountain.name = "Fountain"
	_cyl_in(park, 2.6, 0.1, Vector3(0, 0.66, 0), Color(0.35, 0.6, 0.9), false)
	_cyl_in(park, 0.4, 2.0, Vector3(0, 1.4, 0), Color(0.7, 0.72, 0.75), false)

	for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		for i in 3:
			var p := Vector3(q.x * rng.randf_range(5, 16), 0, q.y * rng.randf_range(5, 16))
			_tree(park, p)
		var bench_p := Vector3(q.x * 6.5, 0, q.y * 3.0)
		_bench(park, bench_p, 0.0 if q.y > 0 else 180.0)
		spots.append({"pos": _local_to_world(park, bench_p + Vector3(0, 0, -q.y * 1.2)), "kind": "bench", "busy": false})
		spots.append({"pos": _local_to_world(park, Vector3(q.x * 10, 0, q.y * 10)), "kind": "park", "busy": false})


func _tree(parent: Node3D, p: Vector3) -> void:
	var t := _prop_in(parent, "suburban/tree-large" if rng.randf() < 0.6 else "suburban/tree-small", p, rng.randf() * 360.0, rng.randf_range(8.0, 10.0), false)
	var body := StaticBody3D.new()
	body.position = p + Vector3(0, 1.5, 0)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 3.0
	shape.shape = cyl
	body.add_child(shape)
	parent.add_child(body)


func _bench(parent: Node3D, p: Vector3, rot: float) -> void:
	var b := Node3D.new()
	b.position = p
	b.rotation_degrees.y = rot
	parent.add_child(b)
	_box_in(b, Vector3(2.0, 0.1, 0.55), Vector3(0, 0.48, 0), Color(0.55, 0.35, 0.2), true)
	_box_in(b, Vector3(2.0, 0.5, 0.08), Vector3(0, 0.78, 0.25), Color(0.55, 0.35, 0.2), false)
	for s in [-1, 1]:
		_box_in(b, Vector3(0.08, 0.45, 0.5), Vector3(s * 0.85, 0.22, 0), Color(0.2, 0.2, 0.22), false)


# ---------------------------------------------------------------- 인도 소품

func _sidewalk_props(c: Vector2) -> void:
	var cw := Vector3(c.x, 0.06, c.y)
	# 가로등: 모서리마다
	for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_prop("roads/light-square", cw + Vector3(q.x * 21.2, 0, q.y * 21.2), 45.0 + _quad_angle(q), Vector3.ONE * 7.0, false)
	# 변마다 가로수/벤치/쓰레기통/소화전
	for side in 4:
		var ang := side * 90.0
		var basis := Basis(Vector3.UP, deg_to_rad(ang))
		for i in [-1, 1]:
			var tp := cw + basis * Vector3(i * 9.0, 0, BLOCK_HALF - 0.55)
			_planter_tree(tp)
		var kind := rng.randi_range(0, 3)
		match kind:
			0:
				_bus_stop(cw + basis * Vector3(0, 0, 19.9), ang)
				spots.append({"pos": cw + basis * Vector3(2.6, 0, 19.6), "kind": "busstop", "busy": false})
			1:
				_cafe(cw + basis * Vector3(3.0, 0, 19.0), ang)
				spots.append({"pos": cw + basis * Vector3(0.0, 0, 19.8), "kind": "cafe", "busy": false})
			_:
				_trash_can(cw + basis * Vector3(2.0, 0, 21.45))
				spots.append({"pos": cw + basis * Vector3(3.2, 0, 20.2), "kind": "street", "busy": false})
		if side % 2 == 0:
			var hp := cw + basis * Vector3(-15.0, 0, 21.3)
			_hydrant(hp)
	# 모서리 흡연 장소
	for q in [Vector2(-1, -1), Vector2(1, 1)]:
		spots.append({"pos": cw + Vector3(q.x * 19.6, 0, q.y * 19.6), "kind": "corner", "busy": false})


func _quad_angle(q: Vector2) -> float:
	return rad_to_deg(atan2(q.x, q.y))


func _planter_tree(p: Vector3) -> void:
	_box(Vector3(0.9, 0.35, 0.9), p + Vector3(0, 0.17, 0), Color(0.45, 0.42, 0.4), true)
	_box(Vector3(0.75, 0.05, 0.75), p + Vector3(0, 0.36, 0), Color(0.3, 0.22, 0.15), false)
	_prop("suburban/tree-small", p + Vector3(0, 0.35, 0), rng.randf() * 360.0, Vector3.ONE * 7.0, false)


func _bus_stop(p: Vector3, ang: float) -> void:
	var b := Node3D.new()
	b.position = p
	b.rotation_degrees.y = ang
	root.add_child(b)
	_box_in(b, Vector3(4.0, 0.12, 1.6), Vector3(0, 2.6, -0.6), Color(0.2, 0.45, 0.8), false)
	_box_in(b, Vector3(4.0, 2.5, 0.06), Vector3(0, 1.3, -1.35), Color(0.75, 0.85, 0.95, 0.5), true)
	for s in [-1, 1]:
		_box_in(b, Vector3(0.1, 2.6, 0.1), Vector3(s * 1.95, 1.3, -1.35), Color(0.25, 0.25, 0.28), false)
	_bench(b, Vector3(0, 0, -0.95), 180.0)
	var sign := Label3D.new()
	sign.text = "버스 정류장"
	sign.font = load("res://assets/fonts/BlackHanSans-Regular.ttf")
	sign.font_size = 48
	sign.pixel_size = 0.006
	sign.position = Vector3(0, 2.82, -0.6)
	sign.rotation_degrees.x = -90
	b.add_child(sign)


func _cafe(p: Vector3, ang: float) -> void:
	for i in 2:
		var tp := p + Basis(Vector3.UP, deg_to_rad(ang)) * Vector3(i * 3.2 - 1.6, 0, 0)
		_prop("commercial/detail-parasol-" + ("a" if i == 0 else "b"), tp, ang, Vector3.ONE * 6.0, false)
		_cyl(0.45, 0.06, tp + Vector3(0, 0.75, 0), Color(0.95, 0.95, 0.95), false)
		_cyl(0.07, 0.75, tp + Vector3(0, 0.37, 0), Color(0.3, 0.3, 0.3), true)


func _trash_can(p: Vector3) -> void:
	_cyl(0.32, 0.9, p + Vector3(0, 0.45, 0), Color(0.2, 0.45, 0.3), true)
	_cyl(0.36, 0.08, p + Vector3(0, 0.92, 0), Color(0.15, 0.3, 0.2), false)


func _hydrant(p: Vector3) -> void:
	var red := Color(0.85, 0.12, 0.1)
	_cyl(0.18, 0.75, p + Vector3(0, 0.37, 0), red, true)
	_cyl(0.22, 0.08, p + Vector3(0, 0.76, 0), red, false)
	_cyl(0.12, 0.18, p + Vector3(0, 0.88, 0), red, false)
	var nub := _box(Vector3(0.5, 0.12, 0.12), p + Vector3(0, 0.5, 0), Color(0.75, 0.1, 0.08), false)
	nub.name = "HydrantNub"
	hydrants.append(p)


func _no_smoking_sign(parent: Node3D, p: Vector3, rot: float) -> void:
	var s := Node3D.new()
	s.position = p
	s.rotation_degrees.y = rot
	parent.add_child(s)
	_box_in(s, Vector3(0.08, 2.0, 0.08), Vector3(0, 1.0, 0), Color(0.3, 0.3, 0.3), false)
	_box_in(s, Vector3(1.4, 0.7, 0.05), Vector3(0, 2.2, 0), Color(0.95, 0.95, 0.95), false)
	var l := Label3D.new()
	l.text = "금연구역"
	l.font = load("res://assets/fonts/BlackHanSans-Regular.ttf")
	l.font_size = 64
	l.pixel_size = 0.005
	l.modulate = Color(0.85, 0.1, 0.1)
	l.outline_size = 0
	l.position = Vector3(0, 2.2, 0.03)
	s.add_child(l)
	var l2 := l.duplicate()
	l2.position = Vector3(0, 2.2, -0.03)
	l2.rotation_degrees.y = 180
	s.add_child(l2)


# ---------------------------------------------------------------- 바깥 둘레

func _outer_ring() -> void:
	# 바깥 인도
	var ow := EDGE - (PITCH + ROAD_W / 2)   # 4
	for s in [-1, 1]:
		_box(Vector3(EDGE * 2, 0.06, ow), Vector3(0, 0.03, s * (EDGE - ow / 2)), Color(0.66, 0.64, 0.6), false)
		_box(Vector3(ow, 0.06, EDGE * 2 - ow * 2), Vector3(s * (EDGE - ow / 2), 0.03, 0), Color(0.66, 0.64, 0.6), false)
	# 바깥 건물 벽 (안쪽을 바라봄)
	var slot := 12.0
	var count := int((EDGE * 2 + slot * 2) / slot)
	for side in 4:
		var ang := side * 90.0
		var basis := Basis(Vector3.UP, deg_to_rad(ang))
		for i in count:
			var along := -EDGE - slot + slot * (i + 0.5)
			var p := basis * Vector3(along, 0.06, EDGE + slot / 2)
			var holder := Node3D.new()
			holder.position = p
			holder.rotation_degrees.y = ang
			root.add_child(holder)
			_building(holder, Vector3.ZERO, 180.0, slot)
	for s in [-1, 1]:
		for i in 6:
			var z := -50.0 + i * 20.0
			_prop("roads/light-square", Vector3(s * (EDGE - 0.6), 0.06, z), -90.0 * s, Vector3.ONE * 7.0, false)


func _parked_cars() -> void:
	for c in [0.0]:
		for along in range(-50, 51, 7):
			if abs(along) < 10 or abs(abs(along) - PITCH) < 10:
				continue
			for side in [-1, 1]:
				if rng.randf() < 0.45:
					continue
				var model: String = PARKED[rng.randi_range(0, PARKED.size() - 1)]
				var off: float = side * 3.6
				_prop("cars/" + model, Vector3(c + off, 0.02, along), 0.0 if side > 0 else 180.0, Vector3.ONE * 1.6, true)
				if rng.randf() < 0.5:
					_prop("cars/" + PARKED[rng.randi_range(0, PARKED.size() - 1)], Vector3(along, 0.02, c + off), 90.0 if side > 0 else -90.0, Vector3.ONE * 1.6, true)


# ---------------------------------------------------------------- 보행자 길

func _nav_graph() -> void:
	## 블록마다 인도 모서리 4개. 블록 둘레 + 이웃 블록으로 건너는 횡단보도.
	var corner_index := {}
	for c in block_centers:
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := Vector3(c.x + q.x * WALK, 0.12, c.y + q.y * WALK)
			corner_index[_key(p)] = nav_nodes.size()
			nav_nodes.append(p)
			nav_edges[nav_nodes.size() - 1] = []
	for bi in block_centers.size():
		for k in 4:
			_link(bi * 4 + k, bi * 4 + (k + 1) % 4)
	# 횡단보도: 가운데 도로를 사이에 둔 모서리끼리
	for i in nav_nodes.size():
		for j in range(i + 1, nav_nodes.size()):
			var a := nav_nodes[i]
			var b := nav_nodes[j]
			var dx: float = abs(a.x - b.x)
			var dz: float = abs(a.z - b.z)
			if (dx < 0.1 and abs(dz - 14.0) < 0.5) or (dz < 0.1 and abs(dx - 14.0) < 0.5):
				_link(i, j)


func _link(a: int, b: int) -> void:
	nav_edges[a].append(b)
	nav_edges[b].append(a)


func _key(p: Vector3) -> String:
	return "%d_%d" % [roundi(p.x), roundi(p.z)]


func nearest_nav(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in nav_nodes.size():
		var d := nav_nodes[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


# ---------------------------------------------------------------- 도우미

func _local_to_world(node: Node3D, p: Vector3) -> Vector3:
	var xf := Transform3D(Basis.from_euler(node.rotation), node.position)
	return xf * p


func _model_aabb(path: String) -> AABB:
	if _aabb_cache.has(path):
		return _aabb_cache[path]
	var inst := _instance(path)
	var acc := [null]
	_collect_aabb(inst, Transform3D.IDENTITY, acc)
	inst.free()
	var a: AABB = acc[0] if acc[0] != null else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	_aabb_cache[path] = a
	return a


func _collect_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * n.transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = t * n.mesh.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for ch in n.get_children():
		_collect_aabb(ch, t, acc)


func _instance(path: String) -> Node3D:
	return load("res://assets/%s.glb" % path).instantiate()


func _prop(path: String, pos: Vector3, rot: float, scl: Vector3, collide: bool) -> Node3D:
	return _place(root, path, pos, rot, scl, collide)


func _prop_in(parent: Node3D, path: String, pos: Vector3, rot: float, scl: float, collide: bool) -> Node3D:
	return _place(parent, path, pos, rot, Vector3.ONE * scl, collide)


func _place(parent: Node3D, path: String, pos: Vector3, rot: float, scl: Vector3, collide: bool) -> Node3D:
	var n := _instance(path)
	n.position = pos
	n.rotation_degrees.y = rot
	n.scale = scl
	parent.add_child(n)
	if collide:
		# 충돌체는 스케일 없는 형제 노드로 둔다 (물리 노드는 스케일을 싫어한다)
		var a := _model_aabb(path)
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation_degrees.y = rot
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = a.size * scl
		shape.shape = box
		shape.position = a.get_center() * scl
		body.add_child(shape)
		parent.add_child(body)
	return n


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool) -> Node3D:
	return _box_in(root, size, pos, color, collide)


func _box_in(parent: Node3D, size: Vector3, pos: Vector3, color: Color, collide: bool) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color)
	mesh.mesh = bm
	mesh.position = pos
	parent.add_child(mesh)
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


func _cyl(radius: float, height: float, pos: Vector3, color: Color, collide: bool) -> Node3D:
	return _cyl_in(root, radius, height, pos, color, collide)


func _cyl_in(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, collide: bool) -> Node3D:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	cm.material = _mat(color)
	mesh.mesh = cm
	mesh.position = pos
	parent.add_child(mesh)
	if collide:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = radius
		cs.height = height
		shape.shape = cs
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


func _wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	root.add_child(body)
