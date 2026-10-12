class_name CityBuilder
extends RefCounted
## 4x4 블록 동네를 만든다 (가운데 2x2 가 처음 동네, 바깥 12블록이 승진하면 열리는 곳).
## 도로 5x5 격자, 블록마다 건물/골목 안뜰, 두 블록은 공원.
## 만든 뒤 보행자 길 그래프, 흡연 장소, 소화전 위치를 돌려준다.

const PITCH := 54.0          # 도로 중심 간격
const ROAD_W := 10.0
const BLOCK_HALF := 22.0     # 블록(인도 포함) 반 크기
const WALK := 20.0           # 보행자 길(인도 중앙) 반 크기
const INNER := 18.0          # 건물이 서는 안쪽 반 크기
const EDGE := 117.0          # 바깥 인도 끝 (2 * PITCH + 9)
const ROAD_LINES := [-108.0, -54.0, 0.0, 54.0, 108.0]   # 도로 중심선 (x 와 z 같음)

const GRAFFITI := ["흡연금지", "CCTV 작동중", "쓰레기 버리지 마시오", "XX 참교육", "민지 사랑해", "여기서 담배 피면 벌금"]
## 순찰차/소방차 자리 (x, z): 여기엔 주차된 차를 두지 않는다
const RESERVED := [Vector2(-13.0, -3.6), Vector2(-23.0, -3.6), Vector2(-32.0, -3.6)]
const PARKED := ["sedan", "suv", "taxi", "van", "hatchback-sports", "sedan-sports", "suv-luxury", "delivery", "truck"]

var root: Node3D
var nav_nodes: Array[Vector3] = []
var nav_edges := {}          # index -> Array[int]
var spots: Array = []        # {pos: Vector3, kind: String, busy: bool}
var hydrants: Array[Vector3] = []
var block_centers: Array[Vector2] = []
var park_center := Vector2.ZERO
var parks: Array[Vector2] = []
var ring_lanes: Array = []   # 자동차가 도는 사각 경로 [half, clockwise]
var shop_slots: Array = []   # 불법업소를 붙일 수 있는 건물 정면 {pos, normal, used}
var zone := Rect2(-EDGE, -EDGE, EDGE * 2, EDGE * 2)   # 관할 구역 (x, z)
var allowed_nodes: Array[int] = []
var _all := {}               # 구역으로 거르기 전 원본 (spots, hydrants, shop_slots, edges)
var _barrier_nodes: Array[Node] = []
var _block_turn := {}

var _aabb_cache := {}
var _tex_hash := {}
var _mats := {}
var rng := RandomNumberGenerator.new()


func build(parent: Node3D, seed_value := 1234) -> void:
	rng.seed = seed_value
	root = Node3D.new()
	root.name = "City"
	parent.add_child(root)

	_ground()
	_roads()
	# 가운데 2x2 를 먼저 (예전과 같은 순서/난수라 파출소 동네는 그대로), 그다음 바깥 12블록
	for bx in [-1, 1]:
		for bz in [-1, 1]:
			block_centers.append(Vector2(bx, bz) * PITCH / 2)
	for bx in [-3, -1, 1, 3]:
		for bz in [-3, -1, 1, 3]:
			if abs(bx) == 3 or abs(bz) == 3:
				block_centers.append(Vector2(bx, bz) * PITCH / 2)
	park_center = block_centers[2]
	parks = [park_center, Vector2(3, -1) * PITCH / 2]
	for c in block_centers:
		_block_slab(c)
		if c in parks:
			_park(c)
		else:
			var bi := block_centers.find(c)
			_building_block(c, 0 if bi <= 1 else rng.randi_range(0, 3), bi)
		_sidewalk_props(c)
	_outer_ring()
	_parked_cars()
	_nav_graph()
	ring_lanes = [[PITCH - 2.5, true], [PITCH + 2.5, false], [PITCH * 2 - 2.5, true], [PITCH * 2 + 2.5, false]]
	_merge_static()


# ---------------------------------------------------------------- 최적화

const MERGE_CELL := 60.0


func _merge_static() -> void:
	## 움직이지 않는 메시를 (구역, 재질) 별로 하나로 합친다. 그리는 횟수가 수백 → 수십으로 준다.
	## 구역으로 나누는 건 화면 밖 구역을 통째로 건너뛰게 하려고.
	var groups := {}
	var originals: Array = root.find_children("*", "MeshInstance3D", true, false)
	for mi in originals:
		var mesh: Mesh = mi.mesh
		if mesh == null or mi.has_meta("keep_lod"):
			continue
		var xf: Transform3D = mi.global_transform
		var center: Vector3 = xf * mesh.get_aabb().get_center()
		var cell := Vector2i(floori(center.x / MERGE_CELL), floori(center.z / MERGE_CELL))
		for si in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			var plain := _is_plain(mat)
			var key := "%d_%d_%s" % [cell.x, cell.y, "plain" if plain else _mat_key(mat)]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"st": st, "mat": _plain_mat() if plain else mat}
			if plain:
				_append_colored(groups[key].st, mesh, si, xf, mat.albedo_color)
			else:
				groups[key].st.append_from(mesh, si, xf)
	for mi in originals:
		if mi.has_meta("keep_lod"):
			continue
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var merged := Node3D.new()
	merged.name = "Merged"
	root.add_child(merged)
	for key in groups:
		var g: Dictionary = groups[key]
		var mi := MeshInstance3D.new()
		mi.mesh = g.st.commit()
		mi.material_override = g.mat
		merged.add_child(mi)


func _is_plain(mat: Material) -> bool:
	## 텍스처 없는 불투명 단색 재질 (상자, 원기둥 소품)
	return mat is StandardMaterial3D and mat.albedo_texture == null and mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED 		and not mat.emission_enabled and mat.metallic == 0.0


var _plain: StandardMaterial3D


func _plain_mat() -> StandardMaterial3D:
	if _plain == null:
		_plain = StandardMaterial3D.new()
		_plain.vertex_color_use_as_albedo = true
	return _plain


func _append_colored(st: SurfaceTool, mesh: Mesh, si: int, xf: Transform3D, color: Color) -> void:
	## 단색 재질 메시를 정점 색으로 바꿔 넣는다 → 색이 달라도 한 번에 그린다
	var arr := mesh.surface_get_arrays(si)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	var order: PackedInt32Array = idx if idx.size() > 0 else PackedInt32Array(range(verts.size()))
	for i in order:
		st.set_color(color)
		if normals.size() > i:
			st.set_normal((nb * normals[i]).normalized())
		st.add_vertex(xf * verts[i])


func _mat_key(mat: Material) -> String:
	# Kenney 모델은 파일마다 같은 colormap 텍스처를 따로 품고 있다 → 텍스처 내용으로 묶는다
	if mat is StandardMaterial3D and mat.albedo_texture:
		var tex: Texture2D = mat.albedo_texture
		var id := tex.get_rid().get_id()
		if not _tex_hash.has(id):
			var img := tex.get_image()
			_tex_hash[id] = str(hash(img.get_data())) if img else str(id)
		return "%s_%s_%d" % [_tex_hash[id], mat.albedo_color.to_html(), mat.transparency]
	return str(mat.get_instance_id()) if mat else "none"


# ---------------------------------------------------------------- 기본 바닥/도로

func _ground() -> void:
	_box_m(root, Vector3(EDGE * 2 + 40, 1, EDGE * 2 + 40), Vector3(0, -0.5, 0), Mats.asphalt(), true)
	# 보이지 않는 경계 벽
	for s in [-1, 1]:
		_wall(Vector3(1, 20, EDGE * 2 + 14), Vector3(s * (EDGE + 1), 10, 0))
		_wall(Vector3(EDGE * 2 + 14, 20, 1), Vector3(0, 10, s * (EDGE + 1)))


func _roads() -> void:
	_road_markings()


func _block_slab(c: Vector2) -> void:
	_box_m(root, Vector3(BLOCK_HALF * 2, 0.06, BLOCK_HALF * 2), Vector3(c.x, 0.03, c.y), Mats.pavement(), false)
	# 연석 테두리
	for s in [-1, 1]:
		_box(Vector3(BLOCK_HALF * 2 + 0.3, 0.16, 0.3), Vector3(c.x, 0.08, c.y + s * BLOCK_HALF), Color(0.8, 0.8, 0.78), false)
		_box(Vector3(0.3, 0.16, BLOCK_HALF * 2 + 0.3), Vector3(c.x + s * BLOCK_HALF, 0.08, c.y), Color(0.8, 0.8, 0.78), false)


# ---------------------------------------------------------------- 건물 블록

func _building_block(c: Vector2, turn: int, bi := -1) -> void:
	## 네 귀퉁이에 건물, 가운데를 T자 골목이 가른다 (남북으로 관통 + 동쪽 출구).
	## turn 만큼 90도씩 돌려서 블록마다 골목 방향이 다르다.
	var block := Node3D.new()
	block.position = Vector3(c.x, 0.06, c.y)
	block.rotation_degrees.y = turn * 90.0
	root.add_child(block)
	_block_turn[c] = turn

	var slot := 15.0
	for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var pos := Vector3(q.x * 10.0, 0, q.y * 10.0)
		var rot := 180.0 if q.y < 0 else 0.0
		_role_building(block, bi, q, pos, rot, 16.0 - 0.6)
		if ROLES.get("%d_%d_%d" % [bi, int(q.x), int(q.y)], "") == "":
			_shop_slot(block, pos, rot, 16.0)
	_alley(block)


func _alley(block: Node3D) -> void:
	# 바닥 (남북 골목 + 동쪽 가지)
	_box_m(block, Vector3(4.0, 0.05, 36.0), Vector3(0, 0.03, 0), Mats.pbr("concrete", 3.0, Color(0.7, 0.7, 0.72)), false)
	_box_m(block, Vector3(16.0, 0.05, 4.0), Vector3(10.0, 0.03, 0), Mats.pbr("concrete", 3.0, Color(0.7, 0.7, 0.72)), false)
	# 배수구 줄
	_box_in(block, Vector3(0.3, 0.06, 36.0), Vector3(0, 0.04, 0), Color(0.18, 0.18, 0.2), false)

	# 골목 벽: [중심, 크기, 골목 쪽 방향]
	var walls := [
		[Vector3(-2.3, 0, 0), Vector3(0.6, 0, 36.0), Vector3.RIGHT],
		[Vector3(2.3, 0, -10.0), Vector3(0.6, 0, 16.0), Vector3.LEFT],
		[Vector3(2.3, 0, 10.0), Vector3(0.6, 0, 16.0), Vector3.LEFT],
		[Vector3(10.15, 0, -2.3), Vector3(15.7, 0, 0.6), Vector3.BACK],
		[Vector3(10.15, 0, 2.3), Vector3(15.7, 0, 0.6), Vector3.FORWARD],
	]
	for w in walls:
		var h := rng.randf_range(8.0, 13.0)
		var center: Vector3 = w[0]
		var size: Vector3 = w[1]
		var inward: Vector3 = w[2]
		_box_m(block, Vector3(size.x, h, size.z), center + Vector3(0, h / 2, 0), Mats.brick() if rng.randf() < 0.6 else Mats.facade(rng.randi() % 7), true)
		# 벽 장식: 뒷문, 실외기, 배관, 창문
		var length: float = max(size.x, size.z)
		var along := Vector3(0, 0, 1) if size.z > size.x else Vector3(1, 0, 0)
		var face := center + inward * 0.32
		var n := int(length / 4.0)
		for i in n:
			var t := -length / 2 + 2.0 + i * 4.0 + rng.randf_range(-0.6, 0.6)
			var p := face + along * t
			match rng.randi() % 5:
				0:
					_box_in(block, _orient(Vector3(1.2, 2.2, 0.12), along), p + Vector3(0, 1.1, 0), Color(0.22, 0.2, 0.2), false)
					_box_in(block, _orient(Vector3(1.4, 0.15, 0.3), along), p + Vector3(0, 2.3, 0) + inward * 0.1, Color(0.3, 0.3, 0.32), false)
				1, 2:
					var y := rng.randf_range(2.6, h - 1.5)
					_box_in(block, _orient(Vector3(0.9, 0.65, 0.55), along), p + Vector3(0, y, 0) + inward * 0.2, Color(0.82, 0.83, 0.85), false)
					var fan := _cyl_in(block, 0.22, 0.04, p + Vector3(0, y, 0) + inward * 0.49, Color(0.35, 0.36, 0.38), false)
					fan.rotation = _face_rot(inward) + Vector3(PI / 2, 0, 0)
				3:
					_cyl_in(block, 0.08, h, p + Vector3(0, h / 2, 0) + inward * 0.05, Color(0.4, 0.42, 0.44), false)
				_:
					for k in range(1, int(h / 3.2)):
						_box_in(block, _orient(Vector3(1.0, 1.2, 0.08), along), p + Vector3(0, 1.4 + k * 3.0, 0), Color(0.35, 0.5, 0.65), false)
		# 낙서
		if rng.randf() < 0.6:
			var g := Label3D.new()
			g.text = GRAFFITI[rng.randi() % GRAFFITI.size()]
			g.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
			g.font_size = 64
			g.pixel_size = 0.008
			g.outline_size = 0
			g.modulate = [Color(0.95, 0.2, 0.3), Color(0.2, 0.8, 0.9), Color(1, 0.85, 0.2), Color(0.95, 0.95, 0.95)][rng.randi() % 4]
			g.position = face + inward * 0.02 + along * rng.randf_range(-length / 3, length / 3) + Vector3(0, rng.randf_range(1.2, 2.2), 0)
			g.rotation = _face_rot(inward)
			g.rotate_object_local(Vector3.FORWARD, deg_to_rad(rng.randf_range(-8, 8)))
			g.visibility_range_end = 40.0
			block.add_child(g)

	# 머리 위 전구줄
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1, 0.85, 0.5)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1, 0.75, 0.4)
	bulb_mat.emission_energy_multiplier = 2.5
	for z in [-13.0, -5.0, 6.0, 14.0]:
		_box_in(block, Vector3(4.4, 0.03, 0.03), Vector3(0, 5.0, z), Color(0.1, 0.1, 0.1), false)
		for k in 5:
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.08
			sm.height = 0.16
			sm.radial_segments = 6
			sm.rings = 3
			sm.material = bulb_mat
			bulb.mesh = sm
			bulb.position = Vector3(-1.6 + k * 0.8, 4.88, z)
			block.add_child(bulb)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1, 0.8, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 10.0
	lamp.position = Vector3(0, 4.5, 0)
	block.add_child(lamp)
	lamp_lights.append(lamp)   # 골목 전구 불빛도 밤에 밝아진다

	# 바닥 소품: 쓰레기통, 박스, 쓰레기봉투, 물웅덩이
	_prop_in(block, "roads/dumpster", Vector3(13.5, 0, -1.25), 90.0, 6.0, true)
	_prop_in(block, "roads/dumpster", Vector3(-1.25, 0, 11.0), 0.0, 6.0, true)
	_prop_in(block, "cars/box", Vector3(1.3, 0, -15.5), 20.0, 1.1, true)
	_prop_in(block, "cars/box", Vector3(1.4, 0.78, -15.4), -10.0, 0.9, true)
	_prop_in(block, "cars/box", Vector3(12.5, 0, 1.3), 35.0, 1.0, true)
	for p in [Vector3(-1.4, 0, -8.0), Vector3(-1.5, 0, -7.4), Vector3(14.0, 0, 1.5), Vector3(1.4, 0, 7.5)]:
		_cyl_in(block, 0.32, 0.55, p + Vector3(0, 0.27, 0), Color(0.08, 0.08, 0.09), false)
	for p in [Vector3(0.4, 0, -3.0), Vector3(-0.6, 0, 9.0), Vector3(8.0, 0, 0.3)]:
		_box_in(block, Vector3(rng.randf_range(1.0, 1.8), 0.01, rng.randf_range(0.8, 1.5)), p + Vector3(0, 0.06, 0), Color(0.2, 0.25, 0.32), false)
	_no_smoking_sign(block, Vector3(-1.4, 0, -17.6), 0.0)

	# 골목 안 흡연 장소와 불법업소 자리
	for p in [Vector3(0.9, 0, -11.5), Vector3(-0.9, 0, 5.5), Vector3(1.0, 0, 12.5), Vector3(0.6, 0, -0.8), Vector3(12.0, 0, -0.9), Vector3(6.5, 0, 0.9)]:
		spots.append({"pos": _local_to_world(block, p), "kind": "alley", "busy": false})
	var basis := Basis.from_euler(block.rotation)
	shop_slots.append({"pos": _local_to_world(block, Vector3(-2.0, 0, -9.0)), "normal": basis * Vector3.RIGHT, "used": false})
	shop_slots.append({"pos": _local_to_world(block, Vector3(10.0, 0, 2.0)), "normal": basis * Vector3.FORWARD, "used": false})


func _orient(size: Vector3, along: Vector3) -> Vector3:
	## size 는 (벽을 따라, 높이, 두께) 기준 -> 벽 방향에 맞춰 x/z 를 바꾼다
	return size if along.x > 0.5 else Vector3(size.z, size.y, size.x)


func _face_rot(inward: Vector3) -> Vector3:
	## +Z 가 inward 를 보도록 하는 회전
	return Vector3(0, atan2(inward.x, inward.z), 0)


func _shop_slot(block: Node3D, pos: Vector3, rot: float, slot: float) -> void:
	var facing := Basis(Vector3.UP, deg_to_rad(rot)) * Vector3(0, 0, 1)
	var world_normal := Basis.from_euler(block.rotation) * facing
	shop_slots.append({"pos": _local_to_world(block, pos + facing * (slot / 2)), "normal": world_normal, "used": false})


func is_on_road(p: Vector3) -> bool:
	for c in ROAD_LINES:
		if abs(p.x - c) < ROAD_W / 2 - 0.3 or abs(p.z - c) < ROAD_W / 2 - 0.3:
			return true
	return false


func random_sidewalk_point() -> Vector3:
	## 블록 둘레 인도 위 아무 데나 (관할 구역 안)
	for tries in 12:
		var p := _sidewalk_point()
		if in_zone(p):
			return p
	return nav_nodes[allowed_nodes.pick_random()]


func _sidewalk_point() -> Vector3:
	var c: Vector2 = block_centers.pick_random()
	var side := randi() % 4
	var along := randf_range(-17.0, 17.0)
	var out := randf_range(18.8, 21.4)
	var local := Vector3(along, 0, out)
	var p := Basis(Vector3.UP, side * PI / 2) * local
	return Vector3(c.x + p.x, 0.1, c.y + p.z)


func random_crossing() -> Array:
	## 가운데 도로를 블록 중간에서 가로지르는 [시작, 끝]
	var along := randf_range(12.0, 42.0) * (1 if randf() < 0.5 else -1)
	var a: Vector3
	var b: Vector3
	if randf() < 0.5:
		a = Vector3(-6.5, 0.1, along)
		b = Vector3(6.5, 0.1, along)
	else:
		a = Vector3(along, 0.1, -6.5)
		b = Vector3(along, 0.1, 6.5)
	return [a, b] if randf() < 0.5 else [b, a]


const SHOPS := [
	["편의점", Color(0.1, 0.55, 0.3)], ["약국", Color(0.1, 0.5, 0.25)], ["치킨", Color(0.95, 0.55, 0.05)],
	["PC방", Color(0.15, 0.25, 0.7)], ["노래방", Color(0.6, 0.15, 0.6)], ["부동산", Color(0.75, 0.15, 0.15)],
	["카페", Color(0.35, 0.22, 0.12)], ["분식", Color(0.9, 0.3, 0.2)], ["미용실", Color(0.85, 0.35, 0.55)],
	["세탁소", Color(0.2, 0.55, 0.8)], ["휴대폰", Color(0.95, 0.75, 0.05)], ["빵집", Color(0.75, 0.5, 0.2)],
	["안경", Color(0.25, 0.25, 0.3)], ["학원", Color(0.2, 0.4, 0.75)], ["꽃집", Color(0.55, 0.75, 0.25)],
	["치과", Color(0.15, 0.6, 0.65)], ["국밥", Color(0.7, 0.2, 0.15)], ["당구장", Color(0.1, 0.45, 0.2)],
]

var buildings: Array = []      # 건물 정보 {pos(정면 가운데), normal, name, node}


func _building(parent: Node3D, pos: Vector3, rot: float, slot: float, shop := "") -> Node3D:
	## 실사 소재로 지은 건물: 1층 상가(쇼윈도, 간판, 차양), 위층 유리창, 옥상 실외기/물탱크
	var b := Node3D.new()
	b.position = pos
	b.rotation_degrees.y = rot
	parent.add_child(b)
	var w := slot - 0.3
	var d := slot - 0.3
	var floors := rng.randi_range(3, 7)
	var h := 4.2 + (floors - 1) * 3.2
	var wall: Material = Mats.facade(rng.randi() % 7)
	_box_m(b, Vector3(w, h, d), Vector3(0, h / 2, 0), wall, false)
	# 1층과 2층 사이 띠, 옥상 난간
	var trim: Material = Mats.flat(Color(0.82, 0.82, 0.8), 0.6)
	_box_m(b, Vector3(w + 0.2, 0.3, d + 0.2), Vector3(0, 4.2, 0), trim, false)
	for s in [-1, 1]:
		_box_m(b, Vector3(w + 0.2, 0.7, 0.25), Vector3(0, h + 0.35, s * (d / 2)), trim, false)
		_box_m(b, Vector3(0.25, 0.7, d + 0.2), Vector3(s * (w / 2), h + 0.35, 0), trim, false)

	# 1층 상가
	var info: Array = SHOPS[rng.randi() % SHOPS.size()]
	var shop_name: String = shop if shop != "" else info[0]
	var sign_col: Color = info[1]
	var fz := d / 2
	_box_m(b, Vector3(w - 1.2, 2.7, 0.08), Vector3(0, 1.55, fz + 0.03), Mats.shop_glass(), false)
	var frame: Material = Mats.flat(Color(0.15, 0.15, 0.17), 0.4, 0.6)
	for x in [-(w - 1.2) / 2, 0.0, (w - 1.2) / 2]:
		_box_m(b, Vector3(0.12, 2.8, 0.14), Vector3(x, 1.5, fz + 0.05), frame, false)
	_box_m(b, Vector3(w - 1.0, 0.12, 0.14), Vector3(0, 2.9, fz + 0.05), frame, false)
	# 간판
	_box_m(b, Vector3(w - 0.4, 1.0, 0.25), Vector3(0, 3.55, fz + 0.14), Mats.sign_board(sign_col), false)
	var l := Label3D.new()
	l.text = shop_name
	l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	l.font_size = 120
	l.pixel_size = 0.0065
	l.outline_size = 0
	l.modulate = Color(1, 1, 1)
	l.position = Vector3(0, 3.55, fz + 0.28)
	l.visibility_range_end = 70.0
	b.add_child(l)
	if shop == "":
		shop_signs.append({"label": l, "name": shop_name, "pos": b.to_global(Vector3(0, 0, fz))})
	# 차양
	if rng.randf() < 0.5:
		var aw := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(w - 1.4, 0.08, 1.3)
		am.material = Mats.flat(sign_col.lightened(0.2), 0.8)
		aw.mesh = am
		aw.position = Vector3(0, 2.95, fz + 0.62)
		aw.rotation_degrees.x = 14
		b.add_child(aw)
	# 세로 간판 (한국 상가 느낌)
	if rng.randf() < 0.45:
		var vs: Array = SHOPS[rng.randi() % SHOPS.size()]
		var vx := (w / 2 - 0.5) * (1 if rng.randf() < 0.5 else -1)
		_box_m(b, Vector3(0.9, 3.6, 0.3), Vector3(vx, 6.6, fz + 0.4), Mats.sign_board(vs[1]), false)
		var vl := Label3D.new()
		vl.text = "\n".join(Array(vs[0].split("")))
		vl.font = l.font
		vl.font_size = 96
		vl.pixel_size = 0.0065
		vl.outline_size = 0
		vl.line_spacing = -18
		vl.position = Vector3(vx, 6.6, fz + 0.57)
		vl.visibility_range_end = 70.0
		b.add_child(vl)

	# 위층 창문 (앞면과 양옆)
	var glass: Material = Mats.glass()
	var lit: Material = Mats.glass_lit()
	var lit_cool: Material = Mats.glass_lit(true)
	var sill: Material = Mats.flat(Color(0.85, 0.85, 0.83), 0.6)
	for f in range(1, floors):
		var y := 4.2 + (f - 1) * 3.2 + 1.65
		var cols := int((w - 1.0) / 2.6)
		for c in cols:
			var x := -((cols - 1) * 2.6) / 2 + c * 2.6
			var rw := rng.randf()
			_box_m(b, Vector3(1.6, 1.7, 0.1), Vector3(x, y, fz + 0.02), lit if rw < 0.22 else (lit_cool if rw < 0.32 else glass), false)
			_box_m(b, Vector3(1.8, 0.12, 0.28), Vector3(x, y - 0.9, fz + 0.1), sill, false)
		for s in [-1, 1]:
			var rows := int((d - 1.0) / 2.6)
			for c in rows:
				var z := -((rows - 1) * 2.6) / 2 + c * 2.6
				var rs := rng.randf()
				_box_m(b, Vector3(0.1, 1.7, 1.6), Vector3(s * (w / 2 + 0.02), y, z), lit if rs < 0.22 else (lit_cool if rs < 0.32 else glass), false)
	# 옥상
	var ac: Material = Mats.flat(Color(0.8, 0.82, 0.84), 0.5, 0.3)
	for i in rng.randi_range(1, 3):
		_box_m(b, Vector3(1.2, 0.9, 0.9), Vector3(rng.randf_range(-w / 3, w / 3), h + 0.45, rng.randf_range(-d / 3, d / 3)), ac, false)
	if rng.randf() < 0.5:
		var tank := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.9
		tm.bottom_radius = 0.9
		tm.height = 1.8
		tm.material = Mats.flat(Color(0.25, 0.45, 0.75), 0.4)
		tank.mesh = tm
		tank.position = Vector3(rng.randf_range(-w / 4, w / 4), h + 0.9, rng.randf_range(-d / 4, d / 4))
		b.add_child(tank)

	# 충돌
	var body := StaticBody3D.new()
	body.position = Vector3(0, h / 2, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, d)
	shape.shape = box
	body.add_child(shape)
	b.add_child(body)
	buildings.append({"node": b, "name": shop_name, "height": h})
	return b


func _box_m(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	if collide:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		parent.add_child(body)
	return mesh


func _road_markings() -> void:
	## 도로 위 노란 중앙선, 흰 가장자리선, 교차로 앞 횡단보도
	var yellow := Color(0.95, 0.75, 0.1)
	var white := Color(0.92, 0.92, 0.9)
	var lines := ROAD_LINES
	for c in lines:
		for k in range(lines.size() - 1):
			var a: float = lines[k] + ROAD_W / 2
			var b: float = lines[k + 1] - ROAD_W / 2
			var mid := (a + b) / 2
			var len := b - a
			for off in [-0.15, 0.15]:
				_box(Vector3(0.12, 0.02, len - 6.0), Vector3(c + off, 0.012, mid), yellow, false)
				_box(Vector3(len - 6.0, 0.02, 0.12), Vector3(mid, 0.012, c + off), yellow, false)
			for off in [-4.5, 4.5]:
				_box(Vector3(0.15, 0.02, len), Vector3(c + off, 0.012, mid), white, false)
				_box(Vector3(len, 0.02, 0.15), Vector3(mid, 0.012, c + off), white, false)
			# 횡단보도 (교차로 양쪽)
			for end in [a + 1.6, b - 1.6]:
				for i in 9:
					var x := -4.0 + i * 1.0
					_box(Vector3(0.5, 0.02, 2.6), Vector3(c + x, 0.013, end), white, false)
					_box(Vector3(2.6, 0.02, 0.5), Vector3(end, 0.013, c + x), white, false)


# ---------------------------------------------------------------- 공원

func _park(c: Vector2) -> void:
	var park := Node3D.new()
	park.position = Vector3(c.x, 0.06, c.y)
	root.add_child(park)
	_box_m(park, Vector3(INNER * 2, 0.06, INNER * 2), Vector3(0, 0.03, 0), Mats.grass(), false)
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
	_proc_tree(parent, p, rng.randf_range(1.2, 1.6))
	var body := StaticBody3D.new()
	body.position = p + Vector3(0, 1.5, 0)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 3.0
	shape.shape = cyl
	body.add_child(shape)
	parent.add_child(body)


func _bench(parent: Node3D, p: Vector3, rot: float) -> void:
	_ph(parent, "painted_wooden_bench", p, rot + 180.0, 1.6)
	var body := StaticBody3D.new()
	body.position = p + Vector3(0, 0.4, 0)
	body.rotation_degrees.y = rot
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.8, 0.7)
	shape.shape = bs
	body.add_child(shape)
	parent.add_child(body)


# ---------------------------------------------------------------- 인도 소품

func _sidewalk_props(c: Vector2) -> void:
	var cw := Vector3(c.x, 0.06, c.y)
	# 가로등: 모서리마다
	for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_ph(root, "street_lamp_01", cw + Vector3(q.x * 21.2, 0, q.y * 21.2), 45.0 + _quad_angle(q) + 180.0, 1.7)
	# 변마다 가로수/벤치/쓰레기통/소화전
	for side in 4:
		var ang := side * 90.0
		var basis := Basis(Vector3.UP, deg_to_rad(ang))
		# 변 한가운데(-3~3)는 골목 입구라서 비워 둔다
		for i in [-1, 1]:
			var tp := cw + basis * Vector3(i * 14.0, 0, BLOCK_HALF - 0.55)
			_planter_tree(tp)
		var kind := rng.randi_range(0, 3)
		var off := 8.5 * (1 if rng.randf() < 0.5 else -1)
		match kind:
			0:
				_bus_stop(cw + basis * Vector3(off, 0, 19.9), ang)
				spots.append({"pos": cw + basis * Vector3(off + 2.6, 0, 19.6), "kind": "busstop", "busy": false})
			1:
				_cafe(cw + basis * Vector3(off, 0, 19.0), ang)
				spots.append({"pos": cw + basis * Vector3(off - 2.5, 0, 19.8), "kind": "cafe", "busy": false})
			_:
				_trash_can(cw + basis * Vector3(off, 0, 21.45))
				spots.append({"pos": cw + basis * Vector3(off + 1.2, 0, 20.2), "kind": "street", "busy": false})
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
	_proc_tree(root, p + Vector3(0, 0.35, 0), rng.randf_range(0.9, 1.1))


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
	sign.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
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
	_ph(root, "fire_hydrant", p, rng.randf() * 360.0, 1.1)
	var body := StaticBody3D.new()
	body.position = p + Vector3(0, 0.4, 0)
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.2
	cs.height = 0.8
	shape.shape = cs
	body.add_child(shape)
	root.add_child(body)
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
	l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
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
		_box_m(root, Vector3(EDGE * 2, 0.06, ow), Vector3(0, 0.03, s * (EDGE - ow / 2)), Mats.pavement(), false)
		_box_m(root, Vector3(ow, 0.06, EDGE * 2 - ow * 2), Vector3(s * (EDGE - ow / 2), 0.03, 0), Mats.pavement(), false)
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
		for i in 10:
			var z := -100.0 + i * 22.0
			_ph(root, "street_lamp_01", Vector3(s * (EDGE - 0.6), 0.06, z), -90.0 * s + 180.0, 1.7)


func _parked_cars() -> void:
	for c in [-PITCH, 0.0, PITCH]:
		for along in range(-104, 105, 7):
			if ROAD_LINES.any(func(l): return abs(along - l) < 10):
				continue
			for side in [-1, 1]:
				if rng.randf() < 0.45:
					continue
				var model: String = PARKED[rng.randi_range(0, PARKED.size() - 1)]
				var off: float = side * 3.6
				if not _reserved(Vector2(c + off, along)):
					_prop("cars/" + model, Vector3(c + off, 0.02, along), 0.0 if side > 0 else 180.0, Vector3.ONE * 1.6, true)
				if rng.randf() < 0.5 and not _reserved(Vector2(along, c + off)):
					_prop("cars/" + PARKED[rng.randi_range(0, PARKED.size() - 1)], Vector3(along, 0.02, c + off), 90.0 if side > 0 else -90.0, Vector3.ONE * 1.6, true)


func _reserved(p: Vector2) -> bool:
	for r in RESERVED:
		if p.distance_to(r) < 6.0:
			return true
	return false


## 불법주차 자리 후보: 가운데 도로 횡단보도 위 [위치, 방향(도)]
func parking_candidates() -> Array:
	var list := []
	for inter in ROAD_LINES:
		for s in [-1, 1]:
			var along: float = inter + s * 10.5
			if abs(along) > PITCH * 2:
				continue
			for lane in [-2.0, 2.0]:
				list.append([Vector3(lane, 0.02, along), 0.0 if lane > 0 else 180.0])
				list.append([Vector3(along, 0.02, lane), 90.0 if lane > 0 else -90.0])
	return list.filter(func(c): return in_zone(c[0]))


# ---------------------------------------------------------------- 보행자 길

func _nav_graph() -> void:
	## 블록마다 인도 둘레 + (건물 블록이면) 골목 입구 3곳과 골목 한가운데.
	## 이웃 블록 모서리끼리는 횡단보도로 잇는다.
	var corners: Array[int] = []
	var w := WALK
	for c in block_centers:
		var has_alley := _block_turn.has(c)
		var turn: int = _block_turn.get(c, 0)
		var b := Basis(Vector3.UP, turn * PI / 2)
		var ring := [Vector3(-w, 0, -w), Vector3(0, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, 0), Vector3(w, 0, w), Vector3(0, 0, w), Vector3(-w, 0, w)]
		if not has_alley:
			ring = [Vector3(-w, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w)]
		var ids := []
		for lp in ring:
			var p: Vector3 = b * lp
			ids.append(_add_node(Vector3(c.x + p.x, 0.12, c.y + p.z)))
			if abs(abs(lp.x) - w) < 0.1 and abs(abs(lp.z) - w) < 0.1:
				corners.append(ids[-1])
		for k in ids.size():
			_link(ids[k], ids[(k + 1) % ids.size()])
		if has_alley:
			var center := _add_node(Vector3(c.x, 0.12, c.y))
			_link(center, ids[1])   # 북쪽 입구
			_link(center, ids[3])   # 동쪽 입구
			_link(center, ids[5])   # 남쪽 입구
	# 횡단보도: 가운데 도로를 사이에 둔 모서리끼리
	for i in corners:
		for j in corners:
			if j <= i:
				continue
			var a := nav_nodes[i]
			var bb := nav_nodes[j]
			var dx: float = abs(a.x - bb.x)
			var dz: float = abs(a.z - bb.z)
			if (dx < 0.1 and abs(dz - 14.0) < 0.5) or (dz < 0.1 and abs(dx - 14.0) < 0.5):
				_link(i, j)
	for i in nav_nodes.size():
		allowed_nodes.append(i)


func _add_node(p: Vector3) -> int:
	nav_nodes.append(p)
	nav_edges[nav_nodes.size() - 1] = []
	return nav_nodes.size() - 1


# ---------------------------------------------------------------- 관할 구역

func in_zone(p: Vector3) -> bool:
	return zone.has_point(Vector2(p.x, p.z))


func apply_zone(rect: Rect2) -> void:
	## 관할 구역 밖은 못 가게 막고, 사람/사건이 구역 안에서만 생기게 거른다.
	if _all.is_empty():
		_all = {"spots": spots, "hydrants": hydrants.duplicate(), "shop_slots": shop_slots, "edges": nav_edges.duplicate(true)}
	zone = rect
	allowed_nodes.clear()
	for i in nav_nodes.size():
		if in_zone(nav_nodes[i]):
			allowed_nodes.append(i)
	var edges: Dictionary = _all.edges
	for i in edges:
		nav_edges[i] = edges[i].filter(func(j): return in_zone(nav_nodes[j]) and in_zone(nav_nodes[i]))
	spots = _all.spots.filter(func(sp): return in_zone(sp.pos))
	hydrants.clear()
	for h in _all.hydrants:
		if in_zone(h):
			hydrants.append(h)
	shop_slots = _all.shop_slots.filter(func(sl): return in_zone(sl.pos))
	for n in _barrier_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_barrier_nodes.clear()
	_zone_barriers()


func _zone_barriers() -> void:
	## 구역 경계에 경찰 바리케이드 + 보이지 않는 벽
	var edges := []   # [시작, 끝, 안쪽 방향]
	var x0 := zone.position.x
	var z0 := zone.position.y
	var x1 := zone.end.x
	var z1 := zone.end.y
	if x1 < EDGE:
		edges.append([Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3.LEFT])
	if z1 < EDGE:
		edges.append([Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.FORWARD])
	if x0 > -EDGE:
		edges.append([Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3.RIGHT])
	if z0 > -EDGE:
		edges.append([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3.BACK])
	if edges.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var inward: Vector3 = e[2]
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		var wall := StaticBody3D.new()
		wall.position = (a + b) / 2 + Vector3(0, 5, 0) - inward * 0.3
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(length if abs(dir.x) > 0.5 else 0.4, 10, length if abs(dir.z) > 0.5 else 0.4)
		shape.shape = bs
		wall.add_child(shape)
		root.add_child(wall)
		_barrier_nodes.append(wall)
		var n := int(length / 2.6)
		for i in n:
			var p := a + dir * (1.3 + i * 2.6) - inward * 0.3
			_barricade(st, p, dir)
		# 안내판
		for i in range(1, int(length / 18.0) + 1):
			var sp := a + dir * (i * 18.0 - 9.0) + inward * 0.1
			var l := Label3D.new()
			l.text = "관할 구역 밖\n실적을 쌓아 승진하면 열려요"
			l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
			l.font_size = 48
			l.pixel_size = 0.008
			l.outline_size = 10
			l.modulate = Color(1, 0.85, 0.2)
			l.position = sp + Vector3(0, 2.0, 0)
			l.rotation = _face_rot(inward)
			root.add_child(l)
			_barrier_nodes.append(l)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _plain_mat()
	root.add_child(mi)
	_barrier_nodes.append(mi)


func _barricade(st: SurfaceTool, p: Vector3, dir: Vector3) -> void:
	## 노랑/검정 줄무늬 바리케이드 하나를 정점 색으로 그려 넣는다
	var side := dir.cross(Vector3.UP)
	var xf := Transform3D(Basis(dir, Vector3.UP, side), p)
	var parts := [
		[Vector3(0, 0.9, 0), Vector3(2.4, 0.35, 0.1), Color(1, 0.8, 0.1)],
		[Vector3(-0.6, 0.9, 0.06), Vector3(0.35, 0.36, 0.02), Color(0.1, 0.1, 0.1)],
		[Vector3(0.3, 0.9, 0.06), Vector3(0.35, 0.36, 0.02), Color(0.1, 0.1, 0.1)],
		[Vector3(-0.6, 0.9, -0.06), Vector3(0.35, 0.36, 0.02), Color(0.1, 0.1, 0.1)],
		[Vector3(0.3, 0.9, -0.06), Vector3(0.35, 0.36, 0.02), Color(0.1, 0.1, 0.1)],
		[Vector3(-1.0, 0.45, 0), Vector3(0.1, 0.9, 0.5), Color(0.85, 0.85, 0.85)],
		[Vector3(1.0, 0.45, 0), Vector3(0.1, 0.9, 0.5), Color(0.85, 0.85, 0.85)],
	]
	for part in parts:
		var bm := BoxMesh.new()
		bm.size = part[1]
		_append_colored(st, bm, 0, xf * Transform3D(Basis(), part[0]), part[2])


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
		body.position = pos
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		parent.add_child(body)
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
		body.position = pos
		var shape := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = radius
		cs.height = height
		shape.shape = cs
		body.add_child(shape)
		parent.add_child(body)
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


# ---------------------------------------------------------------- 거점, 역할 건물

## 블록 번호, 사분면 -> 역할 (블록 0 = 첫 블록, 블록 1 = 학교가 있는 블록)
const ROLES := {
	"0_1_1": "station", "0_-1_1": "store", "0_1_-1": "hospital",
	"1_1_-1": "school",
}
const ROLE_NAMES := {"store": "편의점", "hospital": "병원", "school": "물대포중학교"}

var shop_signs: Array = []    # 가게 간판 {label, name, pos} (동네가 더러우면 "임대문의"로 바뀐다)
var lamp_lights: Array[OmniLight3D] = []   # 밤에 켜지는 가로등 불빛
var doors: Array = []          # 들어갈 수 있는 건물 {role, pos, normal, name}
var station_front := Vector3.ZERO
var station_node: Node3D


func _role_building(block: Node3D, bi: int, q: Vector2, pos: Vector3, rot: float, slot: float) -> void:
	var role: String = ROLES.get("%d_%d_%d" % [bi, int(q.x), int(q.y)], "")
	var facing := Basis(Vector3.UP, deg_to_rad(rot)) * Vector3(0, 0, 1)
	var front := _local_to_world(block, pos + facing * (slot / 2 + 0.6))
	var normal := Basis.from_euler(block.rotation) * facing
	match role:
		"station":
			station_node = _police_station(block, pos, rot, slot)
			station_front = front
			doors.append({"role": "station", "pos": front, "normal": normal, "name": "파출소"})
		"store", "hospital", "school":
			var b := _building(block, pos, rot, slot, ROLE_NAMES[role])
			doors.append({"role": role, "pos": front, "normal": normal, "name": ROLE_NAMES[role]})
			if role == "hospital":
				# 병원: 빨간 십자가
				var cross := Mats.sign_board(Color(0.9, 0.1, 0.1))
				_box_m(b, Vector3(1.6, 0.45, 0.2), Vector3(slot / 2 - 2.0, 6.0, slot / 2 + 0.2), cross, false)
				_box_m(b, Vector3(0.45, 1.6, 0.2), Vector3(slot / 2 - 2.0, 6.0, slot / 2 + 0.2), cross, false)
			if role == "school":
				for p in [Vector3(-3, 0, 2.5), Vector3(3, 0, 3.5), Vector3(0, 0, 4.5)]:
					spots.append({"pos": _local_to_world(block, pos + Basis(Vector3.UP, deg_to_rad(rot)) * (p + Vector3(0, 0, slot / 2))), "kind": "school", "busy": false})
		_:
			_building(block, pos, rot, slot)


func _police_station(parent: Node3D, pos: Vector3, rot: float, slot: float) -> Node3D:
	## 파란 1층, 흰 위층, 경광등, '파출소' 간판, 셔터 내린 차고
	var b := Node3D.new()
	b.position = pos
	b.rotation_degrees.y = rot
	b.name = "PoliceStation"
	parent.add_child(b)
	var w := slot - 0.3
	var d := slot - 0.3
	var h := 4.2 + 2 * 3.2
	var blue := Mats.pbr("plaster", 3.0, Color(0.25, 0.4, 0.75))
	var white := Mats.pbr("plaster", 3.0, Color(0.95, 0.96, 0.97))
	_box_m(b, Vector3(w, 4.2, d), Vector3(0, 2.1, 0), blue, false)
	_box_m(b, Vector3(w, h - 4.2, d), Vector3(0, 4.2 + (h - 4.2) / 2, 0), white, false)
	var fz := d / 2
	# 정문 (유리문), 차고 셔터
	_box_m(b, Vector3(3.0, 2.8, 0.08), Vector3(-2.5, 1.5, fz + 0.03), Mats.shop_glass(), false)
	var shutter := Mats.flat(Color(0.7, 0.72, 0.75), 0.4, 0.6)
	for i in 8:
		_box_m(b, Vector3(4.2, 0.3, 0.1), Vector3(3.2, 0.2 + i * 0.36, fz + 0.04), shutter, false)
	# 간판
	_box_m(b, Vector3(w - 0.4, 1.1, 0.3), Vector3(0, 3.6, fz + 0.16), Mats.sign_board(Color(0.08, 0.18, 0.45)), false)
	var l := Label3D.new()
	l.text = "물대포 파출소  POLICE"
	l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	l.font_size = 120
	l.pixel_size = 0.0065
	l.outline_size = 0
	l.position = Vector3(0, 3.6, fz + 0.32)
	b.add_child(l)
	# 지붕 경광등 (빨강/파랑)
	for s in [-1, 1]:
		var lm := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1.2, 0.4, 0.4)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(1, 0.15, 0.1) if s < 0 else Color(0.2, 0.35, 1)
		lmat.emission_enabled = true
		lmat.emission = lmat.albedo_color
		lmat.emission_energy_multiplier = 3.0
		lb.material = lmat
		lm.mesh = lb
		lm.position = Vector3(s * 0.7, h + 0.2, fz - 0.6)
		b.add_child(lm)
	# 위층 창문
	for f in range(1, 3):
		var y := 4.2 + (f - 1) * 3.2 + 1.65
		for c in 5:
			var x := -5.2 + c * 2.6
			_box_m(b, Vector3(1.6, 1.7, 0.1), Vector3(x, y, fz + 0.02), Mats.glass(), false)
	# 국기 게양대
	_cyl_in(b, 0.05, 6.0, Vector3(w / 2 - 0.5, 3.0, fz + 1.5), Color(0.8, 0.8, 0.82), false)
	_box_m(b, Vector3(1.2, 0.8, 0.02), Vector3(w / 2 - 1.1, 5.5, fz + 1.5), Mats.flat(Color(0.95, 0.95, 0.95)), false)
	var body := StaticBody3D.new()
	body.position = Vector3(0, h / 2, 0)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, d)
	shape.shape = bs
	body.add_child(shape)
	b.add_child(body)
	return b


# ---------------------------------------------------------------- 실사 소품 (Poly Haven)

func _ph(parent: Node3D, name: String, pos: Vector3, rot: float, scl: float) -> Node3D:
	var n: Node3D = load("res://assets/ph/%s/%s.gltf" % [name, name]).instantiate()
	n.position = pos
	n.rotation_degrees.y = rot
	n.scale = Vector3.ONE * scl
	parent.add_child(n)
	# 고해상도 소품(가로등 3만, 소화전 9천 삼각형)은 합치지 않고 그대로 둬서 엔진 LOD 가 멀수록 줄이게 한다
	var far := {"street_lamp_01": 110.0, "fire_hydrant": 60.0}.get(name, 70.0) as float
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.set_meta("keep_lod", true)
		mi.visibility_range_end = far
		if name == "fire_hydrant":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if name == "street_lamp_01":
		# 밤에 켜지는 등 (DayCycle 이 밝기를 조절한다)
		var light := OmniLight3D.new()
		light.light_color = Color(1, 0.78, 0.5)
		light.light_energy = 0.0
		light.omni_range = 9.0
		light.position = Vector3(0, 3.45, 0)
		light.distance_fade_enabled = true
		light.distance_fade_begin = 60.0
		light.distance_fade_length = 20.0
		n.add_child(light)
		lamp_lights.append(light)
	return n


func _proc_tree(parent: Node3D, p: Vector3, size := 1.0) -> void:
	## 줄기 + 잎 덩어리 여러 개 (잎은 잔디 질감으로 우툴두툴하게)
	var t := Node3D.new()
	t.position = p
	t.rotation.y = rng.randf() * TAU
	t.scale = Vector3.ONE * size
	parent.add_child(t)
	var bark := Mats.flat(Color(0.33, 0.24, 0.17), 0.9)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.1
	tm.bottom_radius = 0.17
	tm.height = 2.6
	tm.radial_segments = 8
	trunk.mesh = tm
	trunk.material_override = bark
	trunk.position.y = 1.3
	t.add_child(trunk)
	var leaf := Mats.pbr("grass", 1.2, [Color(0.55, 0.85, 0.45), Color(0.45, 0.75, 0.35), Color(0.6, 0.8, 0.4)][rng.randi() % 3])
	for i in 7:
		var c := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.7, 1.15)
		sm.radius = r
		sm.height = r * 1.7
		sm.radial_segments = 10
		sm.rings = 6
		c.mesh = sm
		c.material_override = leaf
		var a := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var rad := 0.0 if i == 0 else rng.randf_range(0.55, 0.95)
		c.position = Vector3(cos(a) * rad, (3.6 if i == 0 else rng.randf_range(2.6, 3.4)), sin(a) * rad)
		t.add_child(c)
