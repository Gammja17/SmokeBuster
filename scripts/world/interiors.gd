class_name Interiors
extends Node3D
## 건물 안. 땅 밑 멀리(y = -100)에 방을 만들어 두고, 문으로 들어가면 순간이동한다.
## 각 방은 {spawn, yaw, points(상호작용 자리), spots(사람 세울 자리), boss}.

const BASE := Vector3(0, -100, 0)
const H := 3.4      # 천장 높이

var rooms := {}     # key -> Dictionary


func build_all() -> void:
	var keys := ["station", "store", "hospital", "smoke_den", "karaoke", "casino"]
	for i in keys.size():
		var origin := BASE + Vector3(i * 60.0, 0, 0)
		var root := Node3D.new()
		root.name = keys[i]
		root.position = origin
		add_child(root)
		rooms[keys[i]] = call("_build_" + keys[i], root)
		rooms[keys[i]].root = root


# ---------------------------------------------------------------- 공통

func _box(root: Node3D, size: Vector3, pos: Vector3, mat: Material, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		root.add_child(body)
	return mi


func _room(root: Node3D, w: float, d: float, floor_mat: Material, wall_mat: Material, ambient: Color) -> void:
	## 바닥, 천장, 네 벽. 앞(+z) 벽 가운데가 출입문.
	_box(root, Vector3(w, 0.2, d), Vector3(0, -0.1, 0), floor_mat)
	_box(root, Vector3(w, 0.2, d), Vector3(0, H + 0.1, 0), Mats.flat(Color(0.85, 0.85, 0.83), 0.9))
	_box(root, Vector3(w, H, 0.3), Vector3(0, H / 2, -d / 2), wall_mat)
	_box(root, Vector3(0.3, H, d), Vector3(-w / 2, H / 2, 0), wall_mat)
	_box(root, Vector3(0.3, H, d), Vector3(w / 2, H / 2, 0), wall_mat)
	_box(root, Vector3((w - 2.0) / 2, H, 0.3), Vector3(-(w + 2.0) / 4, H / 2, d / 2), wall_mat)
	_box(root, Vector3((w - 2.0) / 2, H, 0.3), Vector3((w + 2.0) / 4, H / 2, d / 2), wall_mat)
	_box(root, Vector3(2.0, 1.0, 0.3), Vector3(0, H - 0.5, d / 2), wall_mat)
	# 문 (닫힌 문짝이 보이게, 지나가지는 않는다)
	_box(root, Vector3(1.9, H - 1.0, 0.1), Vector3(0, (H - 1.0) / 2, d / 2 + 0.1), Mats.flat(Color(0.25, 0.2, 0.16), 0.6))
	# 하늘빛이 새지 않게 방 안 주변광을 따로 준다
	var probe := ReflectionProbe.new()
	probe.size = Vector3(w + 1, H + 1, d + 1)
	probe.position = Vector3(0, H / 2, 0)
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = ambient
	probe.ambient_color_energy = 1.0
	root.add_child(probe)


func _light(root: Node3D, pos: Vector3, color: Color, energy := 1.6, rng := 7.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	root.add_child(l)
	return l


func _label(root: Node3D, text: String, pos: Vector3, size := 64, color := Color.WHITE, rot := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 8
	l.position = pos
	l.rotation_degrees.y = rot
	root.add_child(l)
	return l


func _exit_point(root: Node3D, d: float) -> Dictionary:
	return {"role": "exit", "pos": root.position + Vector3(0, 0, d / 2 - 0.8), "normal": Vector3.BACK, "label": "E  밖으로 나가기"}


func _point(root: Node3D, role: String, local: Vector3, label: String) -> Dictionary:
	return {"role": role, "pos": root.position + local, "normal": Vector3.BACK, "label": label}


# ---------------------------------------------------------------- 방들

func _build_station(r: Node3D) -> Dictionary:
	var w := 16.0
	var d := 11.0
	_room(r, w, d, Mats.pbr("tiles", 1.2, Color(0.9, 0.92, 0.95)), Mats.pbr("plaster", 3.0, Color(0.85, 0.9, 1.0)), Color(0.55, 0.6, 0.7))
	var navy := Mats.flat(Color(0.12, 0.2, 0.42), 0.5)
	var metal := Mats.flat(Color(0.55, 0.6, 0.66), 0.35, 0.6)
	var wood := Mats.flat(Color(0.42, 0.3, 0.2), 0.7)
	# 민원 창구
	_box(r, Vector3(5.0, 1.1, 0.8), Vector3(-2.5, 0.55, 1.5), wood)
	_box(r, Vector3(5.2, 0.08, 1.0), Vector3(-2.5, 1.14, 1.5), Mats.flat(Color(0.85, 0.85, 0.82), 0.4))
	_label(r, "민원 접수", Vector3(-2.5, 0.75, 1.92), 44, Color(0.95, 0.95, 0.9))
	# 창구 위 모니터 두 대
	var screen := Mats.flat(Color(0.3, 0.55, 0.9), 0.2)
	screen.emission_enabled = true
	screen.emission = Color(0.35, 0.6, 1.0)
	screen.emission_energy_multiplier = 1.2
	for x in [-3.6, -1.4]:
		_box(r, Vector3(0.9, 0.55, 0.05), Vector3(x, 1.55, 1.3), screen, false)
		_box(r, Vector3(0.1, 0.3, 0.1), Vector3(x, 1.25, 1.3), Mats.flat(Color(0.1, 0.1, 0.1), 0.5), false)
	# 수배 전단: 조직 두목들
	for i in Game.GANGS.size():
		var gx := -1.4 + i * 1.4
		_box(r, Vector3(1.0, 1.3, 0.04), Vector3(gx, 1.7, -5.33), Mats.flat(Color(0.95, 0.92, 0.82), 0.9), false)
		var wl := _label(r, "수배\n%s\n%s" % [Game.GANGS[i].boss, "검거" if Game.raided[i] else "?"], Vector3(gx, 1.75, -5.28), 30, Color(0.6, 0.1, 0.1) if not Game.raided[i] else Color(0.2, 0.5, 0.2))
		wl.outline_size = 0
	# 화분, 정수기, 태극기 대신 파출소 깃발
	for pos in [Vector3(-7.4, 0, -4.8), Vector3(7.4, 0, 4.6)]:
		_box(r, Vector3(0.5, 0.5, 0.5), pos + Vector3(0, 0.25, 0), Mats.flat(Color(0.55, 0.35, 0.25), 0.8))
		_box(r, Vector3(0.8, 1.0, 0.8), pos + Vector3(0, 1.0, 0), Mats.flat(Color(0.2, 0.5, 0.25), 0.9), false)
	_box(r, Vector3(0.4, 1.3, 0.4), Vector3(7.4, 0.65, -2.5), Mats.flat(Color(0.9, 0.92, 0.95), 0.4))
	_box(r, Vector3(0.3, 0.45, 0.3), Vector3(7.4, 1.5, -2.5), Mats.flat(Color(0.5, 0.7, 1.0, 0.7), 0.1))
	# 업무 일지 (근무 상황판)
	_box(r, Vector3(3.2, 1.8, 0.08), Vector3(-5.5, 1.8, -5.3), Mats.flat(Color(0.95, 0.95, 0.92), 0.8), false)
	_label(r, "오늘의 근무", Vector3(-5.5, 2.45, -5.2), 40, Color(0.15, 0.2, 0.35))
	# 사물함 (장비실)
	for i in 6:
		_box(r, Vector3(0.62, 2.1, 0.55), Vector3(4.0 + i * 0.66, 1.05, -5.1), navy)
	_label(r, "장비실", Vector3(5.6, 2.6, -4.7), 64, Color(1, 0.9, 0.5))
	# 소파 (휴식)
	_box(r, Vector3(3.0, 0.45, 0.9), Vector3(5.5, 0.23, 2.5), Mats.flat(Color(0.3, 0.32, 0.36), 0.8))
	_box(r, Vector3(3.0, 0.7, 0.25), Vector3(5.5, 0.6, 2.95), Mats.flat(Color(0.3, 0.32, 0.36), 0.8))
	_box(r, Vector3(1.2, 0.45, 0.7), Vector3(5.5, 0.23, 1.2), wood)
	# 유치장
	_box(r, Vector3(3.6, 0.1, 3.0), Vector3(-6.0, 0.05, 3.2), Mats.flat(Color(0.5, 0.5, 0.5), 0.8), false)
	for i in 8:
		_box(r, Vector3(0.06, H, 0.06), Vector3(-7.7 + i * 0.48, H / 2, 1.7), metal)
	_label(r, "유치장", Vector3(-6.0, 2.9, 1.65), 48, Color(1, 0.6, 0.5))
	_label(r, "물대포 파출소", Vector3(0, 2.95, -5.3), 80, Color(1, 1, 1))
	for x in [-5.0, 0.0, 5.0]:
		_light(r, Vector3(x, H - 0.3, 0), Color(0.95, 0.97, 1.0), 1.8, 9.0)
	return {
		"name": "파출소 안", "spawn": r.position + Vector3(0, 0.2, d / 2 - 1.8), "yaw": 0.0,
		"points": [_exit_point(r, d),
			_point(r, "locker", Vector3(5.6, 0, -4.2), "E  사물함 (장비실)"),
			_point(r, "rest", Vector3(5.5, 0, 1.6), "E  소파에서 쉬기 (멘탈, 물 회복)"),
			_point(r, "desk", Vector3(-5.5, 0, -4.4), "E  근무 일지 (퇴근 보고)")],
		"spots": [], "boss": Vector3.ZERO,
	}


func _build_store(r: Node3D) -> Dictionary:
	var w := 12.0
	var d := 10.0
	_room(r, w, d, Mats.pbr("tiles", 0.8, Color(0.96, 0.96, 0.96)), Mats.flat(Color(0.94, 0.95, 0.93), 0.8), Color(0.65, 0.68, 0.7))
	var shelf := Mats.flat(Color(0.85, 0.86, 0.88), 0.5, 0.3)
	var colors := [Color(0.9, 0.3, 0.25), Color(0.25, 0.55, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.4), Color(0.95, 0.55, 0.2)]
	for row in 3:
		var x := -3.5 + row * 2.6
		_box(r, Vector3(0.9, 1.6, 5.0), Vector3(x, 0.8, -1.0), shelf)
		for k in 10:
			_box(r, Vector3(0.95, 0.22, 0.4), Vector3(x, 0.45 + (k % 3) * 0.5, -3.2 + (k / 3) * 1.4), Mats.flat(colors[(k + row) % colors.size()], 0.6), false)
	# 음료 냉장고 (빛나는 문)
	var fridge := Mats.flat(Color(0.75, 0.88, 1.0), 0.1, 0.3)
	fridge.emission_enabled = true
	fridge.emission = Color(0.8, 0.92, 1.0)
	fridge.emission_energy_multiplier = 0.8
	_box(r, Vector3(5.0, 2.2, 0.6), Vector3(1.5, 1.1, -4.6), fridge)
	# 계산대
	_box(r, Vector3(2.8, 1.0, 0.8), Vector3(4.3, 0.5, 2.6), Mats.flat(Color(0.2, 0.55, 0.35), 0.5))
	_label(r, "24시 편의점", Vector3(0, 2.9, -4.25), 80, Color(0.4, 0.9, 0.5))
	for x in [-3.0, 3.0]:
		_light(r, Vector3(x, H - 0.3, 0), Color(1, 1, 1), 1.9, 8.0)
	return {
		"name": "편의점 안", "spawn": r.position + Vector3(0, 0.2, d / 2 - 1.8), "yaw": 0.0,
		"points": [_exit_point(r, d), _point(r, "counter", Vector3(4.3, 0, 1.7), "E  계산대 (물 + 멘탈1, 30원)")],
		"spots": [], "boss": Vector3.ZERO, "clerk": r.position + Vector3(4.3, 0.06, 3.4),
	}


func _build_hospital(r: Node3D) -> Dictionary:
	var w := 14.0
	var d := 10.0
	_room(r, w, d, Mats.pbr("tiles", 1.0, Color(0.9, 0.97, 0.95)), Mats.flat(Color(0.95, 0.97, 0.97), 0.85), Color(0.65, 0.7, 0.72))
	_box(r, Vector3(4.0, 1.1, 0.8), Vector3(0, 0.55, -2.5), Mats.flat(Color(0.85, 0.9, 0.92), 0.4))
	for row in 2:
		for k in 5:
			_box(r, Vector3(0.6, 0.45, 0.6), Vector3(-4.0 + k * 0.7, 0.23, 1.0 + row * 1.6), Mats.flat(Color(0.3, 0.6, 0.75), 0.6))
	_label(r, "+", Vector3(0, 2.6, -4.7), 220, Color(1, 0.25, 0.25))
	_label(r, "접수", Vector3(0, 1.6, -2.05), 56, Color(0.2, 0.3, 0.4))
	for x in [-4.0, 0.0, 4.0]:
		_light(r, Vector3(x, H - 0.3, 0), Color(0.95, 1, 1), 1.7, 8.0)
	return {
		"name": "병원 안", "spawn": r.position + Vector3(0, 0.2, d / 2 - 1.8), "yaw": 0.0,
		"points": [_exit_point(r, d), _point(r, "reception", Vector3(0, 0, -1.6), "E  접수 (멘탈 완전 회복, 100원)")],
		"spots": [], "boss": Vector3.ZERO, "doctor": r.position + Vector3(0.8, 0.06, -3.4),
	}


func _build_smoke_den(r: Node3D) -> Dictionary:
	## 지하 흡연카페: 어둡고 연기 자욱, 붉은 조명
	var w := 18.0
	var d := 13.0
	_room(r, w, d, Mats.flat(Color(0.25, 0.17, 0.12), 0.8), Mats.pbr("brick", 3.0, Color(0.5, 0.4, 0.38)), Color(0.18, 0.1, 0.1))
	var sofa := Mats.flat(Color(0.45, 0.1, 0.12), 0.7)
	var table := Mats.flat(Color(0.15, 0.1, 0.08), 0.5)
	var spots: Array = []
	for i in 4:
		var c := Vector3(-6.0 + (i % 2) * 12.0, 0, -3.5 + (i / 2) * 5.0)
		_box(r, Vector3(2.6, 0.45, 0.8), c + Vector3(0, 0.23, -1.0), sofa)
		_box(r, Vector3(1.4, 0.55, 0.8), c + Vector3(0, 0.28, 0.2), table, false)
		spots.append(r.position + c + Vector3(-0.8, 0.1, -0.5))
		spots.append(r.position + c + Vector3(0.8, 0.1, 0.9))
	var fog := FogVolume.new()
	fog.size = Vector3(w, H, d)
	fog.position = Vector3(0, H / 2, 0)
	var fm := FogMaterial.new()
	fm.density = 0.07
	fm.albedo = Color(0.6, 0.55, 0.5)
	fog.material = fm
	r.add_child(fog)
	_label(r, "SMOKE LOUNGE", Vector3(0, 2.7, -6.3), 96, Color(1, 0.3, 0.25))
	for x in [-6.0, 0.0, 6.0]:
		_light(r, Vector3(x, H - 0.4, 0), Color(1, 0.55, 0.4), 2.4, 9.0)
	return {"name": "지하 흡연카페", "spawn": r.position + Vector3(0, 0.2, d / 2 - 1.8), "yaw": 0.0,
		"points": [_exit_point(r, d)], "spots": spots, "boss": r.position + Vector3(0, 0.1, -4.8)}


func _build_karaoke(r: Node3D) -> Dictionary:
	## 불법 노래방: 보라 네온 복도와 방들
	var w := 20.0
	var d := 14.0
	_room(r, w, d, Mats.flat(Color(0.12, 0.08, 0.16), 0.3, 0.2), Mats.flat(Color(0.2, 0.12, 0.3), 0.6), Color(0.15, 0.08, 0.2))
	var neon := Mats.flat(Color(1, 0.3, 0.9), 0.3)
	neon.emission_enabled = true
	neon.emission = Color(1, 0.3, 0.9)
	neon.emission_energy_multiplier = 3.0
	var cyan := neon.duplicate() as StandardMaterial3D
	cyan.albedo_color = Color(0.3, 0.9, 1)
	cyan.emission = Color(0.3, 0.9, 1)
	_box(r, Vector3(w - 0.6, 0.06, 0.06), Vector3(0, H - 0.2, -d / 2 + 0.2), neon, false)
	_box(r, Vector3(w - 0.6, 0.06, 0.06), Vector3(0, 0.15, -d / 2 + 0.2), cyan, false)
	# 방 칸막이 셋 (방마다 소파, 화면)
	var spots: Array = []
	for i in 3:
		var x := -6.5 + i * 6.5
		_box(r, Vector3(0.2, H, 5.0), Vector3(x - 3.1, H / 2, -4.0), Mats.flat(Color(0.25, 0.15, 0.35), 0.6))
		_box(r, Vector3(3.0, 0.45, 0.8), Vector3(x, 0.23, -5.8), Mats.flat(Color(0.35, 0.1, 0.4), 0.7))
		var screen := Mats.flat(Color(0.2, 0.5, 1), 0.2)
		screen.emission_enabled = true
		screen.emission = Color(0.3, 0.6, 1)
		screen.emission_energy_multiplier = 1.5
		_box(r, Vector3(2.0, 1.1, 0.06), Vector3(x, 1.8, -6.75), screen, false)
		_light(r, Vector3(x, H - 0.4, -4.0), [Color(1, 0.3, 0.9), Color(0.3, 0.9, 1), Color(1, 0.8, 0.3)][i], 2.5, 7.0)
		spots.append(Vector3(x - 0.8, 0.1, -4.6))
		spots.append(Vector3(x + 0.8, 0.1, -3.4))
	_label(r, "♪ 24시 노래방 ♪", Vector3(0, 2.8, 2.0), 96, Color(1, 0.4, 0.95))
	_light(r, Vector3(0, H - 0.4, 3.0), Color(0.8, 0.4, 1), 1.5, 9.0)
	var music := Sfx.loop_player_3d("karaoke", r, -4.0)
	music.position = Vector3(0, 1.5, -4)
	music.max_distance = 30.0
	music.play()
	for i in spots.size():
		spots[i] = r.position + spots[i]
	return {"name": "불법 노래방", "spawn": r.position + Vector3(0, 0.2, d / 2 - 1.8), "yaw": 0.0,
		"points": [_exit_point(r, d)], "spots": spots, "boss": r.position + Vector3(0, 0.1, 0.0)}


func _build_casino(r: Node3D) -> Dictionary:
	## 지하 도박장: 초록 테이블 위에 낮게 매단 등
	var w := 20.0
	var d := 14.0
	_room(r, w, d, Mats.flat(Color(0.35, 0.08, 0.08), 0.9), Mats.pbr("concrete", 4.0, Color(0.4, 0.4, 0.42)), Color(0.12, 0.12, 0.1))
	var felt := Mats.flat(Color(0.1, 0.45, 0.2), 0.9)
	var rim := Mats.flat(Color(0.3, 0.18, 0.1), 0.5)
	var spots: Array = []
	for i in 4:
		var c := Vector3(-5.5 + (i % 2) * 11.0, 0, -3.5 + (i / 2) * 5.5)
		_box(r, Vector3(3.2, 0.85, 1.8), c + Vector3(0, 0.42, 0), rim)
		_box(r, Vector3(3.0, 0.04, 1.6), c + Vector3(0, 0.87, 0), felt, false)
		for k in 4:
			_box(r, Vector3(0.12, 0.08, 0.12), c + Vector3(-1.0 + k * 0.6, 0.93, 0.2 * (k % 2)), Mats.flat([Color(1, 0.2, 0.2), Color(0.2, 0.4, 1), Color(1, 1, 1)][k % 3], 0.4), false)
		var lamp := _light(r, c + Vector3(0, 2.3, 0), Color(1, 0.85, 0.55), 2.4, 5.5)
		lamp.shadow_enabled = false
		_box(r, Vector3(1.2, 0.25, 0.6), c + Vector3(0, 2.5, 0), Mats.flat(Color(0.1, 0.25, 0.12), 0.5), false)
		spots.append(c + Vector3(-1.2, 0.1, 1.4))
		spots.append(c + Vector3(1.2, 0.1, -1.4))
	_label(r, "출입금지", Vector3(0, 2.7, -6.8), 96, Color(1, 0.85, 0.3))
	for i in spots.size():
		spots[i] = r.position + spots[i]
	return {"name": "지하 도박장", "spawn": r.position + Vector3(0, 0.2, d / 2 - 1.8), "yaw": 0.0,
		"points": [_exit_point(r, d)], "spots": spots, "boss": r.position + Vector3(0, 0.1, -5.6)}
