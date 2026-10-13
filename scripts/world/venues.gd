class_name Venues
extends Node3D
## 퇴근 후 놀 곳: 포장마차(길가 천막, 한잔하면 멘탈 회복 + 단골과 합석), PC방(건물 안, 물총 에임 연습).
## 파출소 근처 빈 상가 자리에 붙인다. 방 만드는 도구는 Interiors 것을 빌려 쓴다.

const PC_ORIGIN := Vector3(660, -100, 0)

var world: Node
var pocha_pos := Vector3.ZERO


func build(w: Node) -> void:
	world = w
	var slots: Array = world.city.shop_slots.filter(func(sl): return not sl.used and world.city.in_zone(sl.pos))
	slots.sort_custom(func(a, b): return a.pos.distance_to(world.SPAWN) < b.pos.distance_to(world.SPAWN))
	if slots.size() < 2:
		return
	# 파출소에서 가까운 두 자리 (바로 옆 자리는 너무 붙어 보이니 하나 건너서)
	var a: Dictionary = slots[0]
	var b: Dictionary = slots[min(2, slots.size() - 1)]
	a.used = true
	b.used = true
	_build_pocha(a)
	_build_pcbang(b)


# ---------------------------------------------------------------- 포장마차

func _build_pocha(sl: Dictionary) -> void:
	var it: Interiors = world.interiors
	var root := Node3D.new()
	root.name = "Pocha"
	add_child(root)
	var n: Vector3 = sl.normal
	root.global_position = sl.pos + n * 3.2
	root.rotation.y = atan2(n.x, n.z)
	pocha_pos = root.global_position
	var tarp := Mats.flat(Color(0.95, 0.42, 0.12), 0.8)
	var steel := Mats.flat(Color(0.45, 0.45, 0.47), 0.5, 0.5)
	for x in [-1.8, 1.8]:
		for z in [-1.4, 1.4]:
			it._box(root, Vector3(0.08, 2.4, 0.08), Vector3(x, 1.2, z), steel, false)
	it._box(root, Vector3(3.9, 0.08, 3.1), Vector3(0, 2.45, 0), tarp, false)
	for x in [-1.95, 1.95]:
		it._box(root, Vector3(0.04, 1.0, 3.1), Vector3(x, 1.95, 0), tarp, false)
	# 조리대, 탁자, 의자
	it._box(root, Vector3(2.4, 0.9, 0.6), Vector3(0, 0.45, -1.1), Mats.flat(Color(0.75, 0.75, 0.78), 0.4, 0.6))
	it._box(root, Vector3(1.2, 0.7, 0.8), Vector3(0, 0.35, 0.4), Mats.flat(Color(0.2, 0.45, 0.85), 0.6))
	for x in [-0.9, 0.9]:
		it._box(root, Vector3(0.35, 0.42, 0.35), Vector3(x, 0.21, 0.4), Mats.flat(Color(0.9, 0.3, 0.25), 0.6), false)
	var l := it._label(root, "포장마차", Vector3(0, 2.75, 1.56), 72, Color(1, 0.85, 0.35))
	l.outline_modulate = Color(0.35, 0.1, 0.0)
	var lamp := it._light(root, Vector3(0, 2.2, 0), Color(1, 0.7, 0.4), 1.4, 6.0)
	lamp.shadow_enabled = false
	# 이모
	var owner := Coworker.new()
	owner.role = "f_mom"
	world.add_child(owner)
	owner.global_position = root.global_position + root.global_basis * Vector3(0, 0.06, -1.6)
	owner.rotation.y = root.rotation.y + PI   # 손님(길) 쪽을 본다
	world.city.doors.append({"role": "pocha", "pos": root.global_position + root.global_basis * Vector3(0, 0, 1.0),
		"normal": n, "label": "E  한잔하기 (₩30 · 멘탈 회복, 단골과 합석)", "name": "포장마차"})


# ---------------------------------------------------------------- PC방

func _build_pcbang(sl: Dictionary) -> void:
	var it: Interiors = world.interiors
	var n: Vector3 = sl.normal
	# 바깥: 원래 있던 "임대문의" 간판을 덮는 검은 판 + 네온 간판
	var face := Node3D.new()
	world.add_child(face)
	face.global_position = sl.pos + n * 0.7
	face.rotation.y = atan2(n.x, n.z)
	it._box(face, Vector3(6.4, 1.3, 0.12), Vector3(0, 3.4, 0), Mats.flat(Color(0.04, 0.05, 0.08), 0.6), false)
	var sign := it._label(face, "PC방  GAME ZONE", Vector3(0, 3.4, 0.08), 96, Color(0.4, 0.95, 1.0))
	sign.outline_modulate = Color(0.0, 0.15, 0.3)
	world.city.doors.append({"role": "pcbang", "pos": sl.pos + n * 0.6, "normal": n, "label": "E  PC방 들어가기", "name": "PC방"})
	# 안
	var r := Node3D.new()
	r.name = "pcbang"
	r.position = PC_ORIGIN
	world.interiors.add_child(r)
	var w := 12.0
	var d := 9.0
	it._room(r, w, d, Mats.flat(Color(0.12, 0.12, 0.15), 0.8), Mats.flat(Color(0.16, 0.17, 0.22), 0.9), Color(0.25, 0.28, 0.4))
	var desk := Mats.flat(Color(0.1, 0.1, 0.12), 0.5)
	var screen := Mats.flat(Color(0.3, 0.6, 1.0), 0.2)
	screen.emission_enabled = true
	screen.emission = Color(0.35, 0.65, 1.0)
	screen.emission_energy_multiplier = 1.6
	var chair := Mats.flat(Color(0.75, 0.12, 0.15), 0.6)
	for row in 2:
		for k in 5:
			var x := -4.0 + k * 2.0
			var z := -2.8 + row * 2.6
			it._box(r, Vector3(1.6, 0.75, 0.7), Vector3(x, 0.375, z), desk)
			it._box(r, Vector3(0.9, 0.55, 0.05), Vector3(x, 1.1, z - 0.25), screen, false)
			it._box(r, Vector3(0.55, 0.9, 0.55), Vector3(x, 0.45, z + 0.75), chair, false)
	it._box(r, Vector3(2.6, 1.0, 0.7), Vector3(3.8, 0.5, 2.6), Mats.flat(Color(0.2, 0.22, 0.3), 0.5))
	it._label(r, "PC방 · 24시", Vector3(0, 2.9, -4.3), 80, Color(0.4, 0.95, 1.0))
	for x in [-3.5, 3.5]:
		it._light(r, Vector3(x, 3.0, 0), Color(0.55, 0.65, 1.0), 1.2, 8.0)
	world.interiors.rooms["pcbang"] = {
		"name": "PC방", "spawn": r.position + Vector3(0, 0.2, d / 2 - 1.8), "yaw": 0.0, "root": r,
		"points": [it._exit_point(r, d), it._point(r, "pc", Vector3(0, 0, -1.6), "E  게임하기 (₩20 · 물총 에임 연습)")],
		"spots": [], "boss": Vector3.ZERO,
	}
