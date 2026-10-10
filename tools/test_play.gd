extends SceneTree
## 헤드리스 플레이 테스트. godot --headless --path . -s tools/test_play.gd

var world
var fails := 0


func check(cond: bool, msg: String) -> void:
	print(("PASS " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	_run.call_deferred()


func _face(player, target: Vector3) -> void:
	# 몸은 수평으로, 카메라는 위아래로 대상을 본다
	var flat := Vector3(target.x, player.global_position.y, target.z)
	player.look_at(flat, Vector3.UP)
	player.camera.look_at(target, Vector3.UP)


func _place_front(player, n, dist: float) -> void:
	var fwd: Vector3 = -player.global_basis.z
	fwd.y = 0
	n.position = player.global_position + fwd.normalized() * dist


func _run() -> void:
	var game = root.get_node("Game")
	game.new_game()
	game.day = 4
	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	game.has_truck = true
	change_scene_to_file("res://scenes/world.tscn")
	await frames(5)
	world = current_scene
	check(world != null and world.name == "World", "월드 씬 로드 (4일차)")
	check(world.city.nav_nodes.size() == 3 * 8 + 4, "길 노드: 건물 블록 8개씩 + 공원 4개 (%d)" % world.city.nav_nodes.size())
	check(world.city.spots.size() > 20, "흡연 장소 %d곳" % world.city.spots.size())
	check(world.city.shop_slots.size() >= 6, "불법업소 자리 %d곳" % world.city.shop_slots.size())
	check(world.progress.size() == world.cfg.tasks.size(), "업무 목록 %d종" % world.progress.size())

	world._start_shift()
	world.cfg.pedestrians = 0
	world.cfg.max_smokers = 0
	world.cfg.spawns = []
	for n in world.npcs.get_children():
		n.queue_free()
	await frames(10)
	check(world.playing, "근무 시작")
	var player = world.player
	player.global_position = Vector3(-7, 0.2, -7)
	player.rotation.y = deg_to_rad(-135)
	await frames(3)

	# ---- 성인 흡연자: 물
	var s = world._new_npc("normal")
	_place_front(player, s, 3.0)
	world.npcs.add_child(s)
	await frames(5)
	check(s.is_smoking() and s._label == null, "흡연자는 글씨 없이 연기만")
	player.equip("spray")
	_face(player, s.global_position + Vector3.UP * 1.3)
	for i in 14:
		player._fire_cd = 0
		player._try_single_fire()
		await frames(10)
		if s.done:
			break
	check(world.progress.get("smoke", 0) == 1, "분무기로 흡연자 단속")

	# ---- 미성년 흡연자: 물 뿌리면 민원, 사진은 신고
	var teen = world._new_npc("teen_smoker")
	_place_front(player, teen, 4.0)
	world.npcs.add_child(teen)
	await frames(5)
	_face(player, teen.incident_pos())
	for i in 3:
		player._fire_cd = 0
		player._try_single_fire()
		await frames(12)
	check(world.complaints >= 1, "미성년자에게 물 뿌리면 민원 (%d)" % world.complaints)
	player.set_camera_mode(true)
	await frames(30)
	_face(player, teen.incident_pos())
	await frames(2)
	var targets: Array = player.photo_targets()
	check(teen in targets, "카메라 프레임 안에 미성년 흡연자 포착 (%d)" % targets.size())
	player._photo_cd = 0
	player.snap_photo()
	await frames(10)
	check(teen.done, "사진 찍으면 학교 신고 처리")
	player.set_camera_mode(false)

	# ---- 학폭: 사진 한 장으로 한 건
	world._group_seq += 1
	var center: Vector3 = player.global_position - player.global_basis.z * 7.0
	center.y = 0.1
	var victim = world._new_npc("victim")
	victim.position = center
	victim.group_id = world._group_seq
	victim.add_to_group("bully_%d" % world._group_seq)
	world.npcs.add_child(victim)
	for b in world._spawn_circle("bully", center, 3, 1.1, "bully_%d" % world._group_seq):
		b.victim = victim
	await frames(10)
	player.set_camera_mode(true)
	_face(player, center + Vector3.UP * 0.8)
	await frames(2)
	player._photo_cd = 0
	player.snap_photo()
	await frames(10)
	check(world.progress.get("bully", 0) == 1, "학폭 현장 촬영 = 1건 (%d)" % world.progress.get("bully", 0))
	player.set_camera_mode(false)

	# ---- 쓰레기 줍기
	var before_trash: int = world.total_resolved
	world._spawn_trash(player.global_position + Vector3(1.0, 0, 0))
	await frames(3)
	player._try_pickup()
	await frames(3)
	check(world.total_resolved == before_trash + 1, "E로 쓰레기 줍기")

	# ---- 불법업소: 물로 합선
	var shop = null
	for c in world.get_children():
		if c.has_method("_short_out"):
			shop = c
	check(shop != null, "불법업소 배치")
	if shop:
		var spos: Vector3 = shop.incident_pos()
		player.global_position = Vector3(spos.x, 0.2, spos.z) + shop.global_basis.z * 3.5
		await frames(3)
		player.equip("hose")
		_face(player, spos)
		for i in 300:
			player._fire_drops(game.WEAPONS.hose, 2)
			await physics_frame
			if shop.done:
				break
		check(shop.done, "간판에 물 뿌려 철거 (남은 전력 %.1f)" % shop.power)

	# ---- 음주운전: 찍으면 경찰 출동
	world._spawn_drunk_car()
	await frames(5)
	var drunk = null
	for c in world.get_children():
		if c.has_method("_chase") and c.drunk:
			drunk = c
	check(drunk != null and drunk.is_active_incident(), "음주운전 차량 등장")
	if drunk:
		drunk.on_photographed()
		await frames(5)
	var cops := 0
	for c in world.get_children():
		if c.has_method("_chase") and c.police:
			cops += 1
	check(cops == 1 and world.progress.get("drunk", 0) == 1, "음주운전 신고 + 경찰차 출동")

	# ---- 무단횡단
	world._spawn_jaywalker()
	await frames(5)
	var jw = null
	for n in world.npcs.get_children():
		if n.has_method("light_up") and n.kind == "jaywalker":
			jw = n
	check(jw != null, "무단횡단자 등장")
	if jw:
		for i in 600:
			await physics_frame
			if jw.photo_task() != "":
				break
		check(jw.photo_task() == "jaywalk", "도로 위에 있을 때만 신고 가능")
		var before: int = world.total_resolved
		jw.on_photographed()
		await frames(3)
		check(world.total_resolved == before + 1, "무단횡단 신고")

	world.time_left = 0.01
	await frames(120)
	check(not world.playing and world.result.visible, "퇴근 → 결과 화면")
	paused = false

	# ---- 1일차는 좁은 구역
	game.day = 1
	change_scene_to_file("res://scenes/world.tscn")
	await frames(8)
	world = current_scene
	var z: Rect2 = world.city.zone
	check(z.size.x < 100, "1일차 관할 구역은 좁다 (%s)" % str(z))
	var outside := 0
	for n in world.npcs.get_children():
		if n.has_method("light_up") and not z.grow(2).has_point(Vector2(n.position.x, n.position.z)):
			outside += 1
	check(outside == 0, "사람은 구역 안에만 생긴다 (밖 %d명)" % outside)

	change_scene_to_file("res://scenes/shop.tscn")
	await frames(5)
	check(current_scene.name == "Shop", "상점 씬")
	change_scene_to_file("res://scenes/title.tscn")
	await frames(30)
	check(current_scene.name == "Title", "타이틀 씬")

	game.new_game()
	print("RESULT fails=%d" % fails)
	quit(fails)
