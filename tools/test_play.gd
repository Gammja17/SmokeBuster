extends SceneTree
## 헤드리스 플레이 테스트 (자유 순찰). godot --headless --path . -s tools/test_play.gd

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
	var flat := Vector3(target.x, player.global_position.y, target.z)
	player.look_at(flat, Vector3.UP)
	player.camera.look_at(target, Vector3.UP)


func _place_front(player, n, dist: float) -> void:
	var fwd: Vector3 = -player.global_basis.z
	fwd.y = 0
	n.position = player.global_position + fwd.normalized() * dist


func _clear(w) -> void:
	w.cfg.incidents = 0
	w.cfg.pedestrians = 0
	w.cfg.events = false
	for n in w.npcs.get_children():
		n.queue_free()


func _run() -> void:
	var game = root.get_node("Game")
	game.new_game()
	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	game.has_truck = true

	# ---- 처음 시작: 순경, 1구역
	change_scene_to_file("res://scenes/world.tscn")
	await frames(8)
	world = current_scene
	check(world != null and world.name == "World", "월드 씬 로드")
	check(game.rank() == 0 and world.city.zone.size.x < 100, "순경은 1구역만")
	check(world.npcs.get_child_count() >= 8, "행인과 흡연자 등장 (%d명)" % world.npcs.get_child_count())
	world._start()
	await frames(5)
	check(world.playing and world.player.input_enabled, "클릭하면 바로 순찰 시작")

	# 사건이 플레이어 근처에 계속 채워지는지
	world.cfg.incidents = 6
	for i in 60 * 20:
		await physics_frame
		if world._active_total() >= 5:
			break
	check(world._active_total() >= 5, "근처에 사건이 계속 생긴다 (%d건)" % world._active_total())
	var near := 0
	for n in world.get_tree().get_nodes_in_group("incident"):
		if n.global_position.distance_to(world.player.global_position) < 50.0:
			near += 1
	check(near >= 3, "사건이 가까이 있다 (%d건이 50m 안)" % near)

	_clear(world)
	await frames(5)
	var player = world.player
	player.global_position = Vector3(-8.5, 0.2, -14)
	player.rotation.y = 0
	await frames(3)

	# ---- 흡연자: 물 → 돈, 실적
	var money0: int = game.money
	var xp0: int = game.xp
	var s = world._new_npc("normal")
	_place_front(player, s, 3.0)
	world.npcs.add_child(s)
	await frames(5)
	player.equip("spray")
	_face(player, s.global_position + Vector3.UP * 1.3)
	for i in 14:
		player._fire_cd = 0
		player._try_single_fire()
		await frames(10)
		if s.done:
			break
	check(s.done and game.money > money0 and game.xp > xp0, "흡연자 단속 → 돈 %d, 실적 %d" % [game.money - money0, game.xp - xp0])
	await frames(200)
	check(not is_instance_valid(s) or s.state == 4, "넘어졌다가 일어나 떠난다")

	# ---- 미성년자에게 물 = 민원, 사진 = 신고
	var teen = world._new_npc("teen_smoker")
	_place_front(player, teen, 4.0)
	world.npcs.add_child(teen)
	await frames(5)
	_face(player, teen.incident_pos())
	for i in 3:
		player._fire_cd = 0
		player._try_single_fire()
		await frames(12)
	check(world.complaints >= 1, "미성년자에게 물 → 민원")
	player.set_camera_mode(true)
	await frames(30)
	_face(player, teen.incident_pos())
	await frames(2)
	player._photo_cd = 0
	player.snap_photo()
	await frames(10)
	check(teen.done, "사진으로 학교 신고")
	player.set_camera_mode(false)

	# ---- 승진하면 그 자리에서 구역이 넓어진다
	var zone_before: Rect2 = world.city.zone
	world._add_xp(game.RANK_XP[1] - game.xp + 1)
	await frames(5)
	check(game.rank() == 1 and world.rank == 1, "실적이 차면 승진 (%s)" % game.rank_name())
	check(world.city.zone.size.x > zone_before.size.x, "승진하면 관할 구역 확장")
	check("jaywalk" in world.cfg.spawns and "shop" in world.cfg.spawns, "새 사건 종류가 열린다")
	var shops := 0
	for c in world.get_children():
		if c.has_method("_short_out"):
			shops += 1
	check(shops >= 1, "승진하면 불법업소가 생긴다 (%d곳)" % shops)

	# ---- 장비실 (Tab)
	world._open_shop()
	await process_frame
	check(world.shop_layer.visible and paused, "Tab 으로 장비실 열면 게임 멈춤")
	world._close_shop()
	await process_frame
	check(not world.shop_layer.visible and not paused, "닫으면 순찰 계속")

	# ---- 돌발 이벤트
	world.cfg.events = true
	world._event_t = 0.0
	await frames(3)
	check(world._event_t > 30.0, "돌발 이벤트 발생")

	# ---- 멘탈 0 → 기절 후 복귀 (게임 오버 없음)
	player.mental = 1
	player._invuln = 0
	player.take_hit(1, player.global_position + Vector3.FORWARD)
	await create_timer(2.6).timeout
	check(player.mental == game.max_mental() and player.input_enabled, "기절해도 파출소에서 다시 시작")

	# ---- 쓰레기
	var x1: int = game.xp
	world._spawn_trash(player.global_position + Vector3(1.0, 0, 0))
	await frames(3)
	player._try_pickup()
	await frames(3)
	check(game.xp > x1, "E로 쓰레기 줍기")

	# ---- 진행 저장 → 다시 열면 계급 유지
	game.save_game()
	var xp_saved: int = game.xp
	game.xp = 0
	game.load_game()
	check(game.xp == xp_saved, "실적 저장/불러오기")

	change_scene_to_file("res://scenes/title.tscn")
	await frames(30)
	check(current_scene.name == "Title", "타이틀 씬")

	game.new_game()
	print("RESULT fails=%d" % fails)
	quit(fails)
