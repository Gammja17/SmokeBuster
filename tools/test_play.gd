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


func _run() -> void:
	var game = root.get_node("Game")
	game.new_game()
	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	game.has_truck = true
	change_scene_to_file("res://scenes/world.tscn")
	await frames(5)
	world = current_scene
	check(world != null and world.name == "World", "월드 씬 로드")
	check(world.city.nav_nodes.size() == 16, "보행자 길 노드 16개 (%d)" % world.city.nav_nodes.size())
	check(world.city.spots.size() > 20, "흡연 장소 %d곳" % world.city.spots.size())
	check(world.city.hydrants.size() >= 8, "소화전 %d개" % world.city.hydrants.size())
	check(world.npcs.get_child_count() >= 12, "NPC 스폰 %d명" % world.npcs.get_child_count())

	world._start_shift()
	world.cfg.pedestrians = 0
	world.cfg.max_smokers = 0
	for n in world.npcs.get_children():
		n.queue_free()
	await frames(10)
	check(world.playing, "근무 시작")

	var player = world.player
	# 플레이어 앞 3m에 흡연자를 세운다
	var fwd: Vector3 = -player.camera.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var s = world._new_npc("normal")
	s.position = player.global_position + fwd * 3.0
	world.npcs.add_child(s)
	await frames(5)
	check(s.is_smoking(), "흡연자 흡연 상태")

	# 분무기 조준해서 펌프
	player.equip("spray")
	player.camera.look_at(s.global_position + Vector3.UP * 1.3)
	var money_before: int = world.earned
	for i in 12:
		player._fire_cd = 0
		player._try_single_fire()
		await frames(10)
		if not is_instance_valid(s) or s.state == 4:
			break
	check(world.caught == 1, "분무기로 흡연자 단속 (caught=%d, wet=%.2f)" % [world.caught, s.wet if is_instance_valid(s) else -1.0])
	check(world.earned > money_before, "보상 지급 %d원" % world.earned)

	# 행인에게 뿌리면 민원
	var ped = world._new_npc("ped")
	ped.position = player.global_position + fwd * 3.0
	world.npcs.add_child(ped)
	ped.start_walking(world.city.nearest_nav(ped.position))
	ped.set_physics_process(false)
	await frames(3)
	player.camera.look_at(ped.global_position + Vector3.UP * 1.3)
	for i in 3:
		player._fire_cd = 0
		player._try_single_fire()
		await frames(12)
	check(world.complaints >= 1, "행인 맞추면 민원 (%d)" % world.complaints)
	ped.queue_free()

	# 양동이로 3명 무리 한 번에
	player.equip("bucket")
	var group := []
	for i in 3:
		var g = world._new_npc("normal")
		g.position = player.global_position + fwd * 6.0 + fwd.cross(Vector3.UP) * (i - 1) * 0.8
		world.npcs.add_child(g)
		group.append(g)
	await frames(3)
	var caught_before: int = world.caught
	player.camera.look_at(group[1].global_position + Vector3.UP * 0.3)
	player._fire_cd = 0
	player._try_single_fire()
	await frames(90)
	check(world.caught - caught_before >= 2, "양동이로 무리 단속 (+%d) wet=%s" % [world.caught - caught_before, str(group.map(func(g): return g.wet if is_instance_valid(g) else -1.0))])

	# 물총 스트림: 다혈질은 달려와서 발차기
	player.equip("pistol")
	var angry = world._new_npc("angry")
	angry.position = player.global_position + fwd * 8.0
	world.npcs.add_child(angry)
	await frames(3)
	angry.soak(0.1, -fwd, 0.0)
	check(angry.state == 3, "다혈질이 맞으면 돌진 상태")
	var mental_before: int = player.mental
	for i in 15:
		await frames(10)
		if i % 5 == 0:
			print("  angry dist=%.1f state=%d wall=%s" % [angry.global_position.distance_to(player.global_position), angry.state, angry.is_on_wall()])
	check(player.mental < mental_before, "다혈질 발차기로 멘탈 감소 (%d -> %d)" % [mental_before, player.mental])

	# 도망자: 가까이 가면 도망
	var runner = world._new_npc("runner")
	runner.position = player.global_position + fwd * 5.0
	world.npcs.add_child(runner)
	await frames(10)
	check(runner.state == 2, "도망자가 도망침")

	# 소방차
	world.truck_charge = 1.0
	world._call_truck()
	await frames(5)
	var trucks := 0
	for c in world.get_children():
		if c.has_method("launch"):
			trucks += 1
	check(trucks == 1, "소방차 출동")

	# 소화전 리필
	player.ammo["hose"] = 0.0
	player.global_position = world.city.hydrants[0] + Vector3(1.2, 0.3, 0)
	await frames(5)
	check(player._near_hydrant, "소화전 근처 감지")

	# 보스
	world._spawn_boss()
	await frames(5)
	var boss = null
	for n in world.npcs.get_children():
		if n.kind == "boss":
			boss = n
	check(boss != null and boss.need >= 10.0, "골초왕 스폰")

	# 근무 종료 → 결과 화면
	world.caught = world.cfg.quota
	world.time_left = 0.01
	await frames(120)
	check(not world.playing, "시간 끝나면 근무 종료")
	check(world.result.visible, "결과 화면 표시")
	check(game.day == 2, "성공하면 다음 날 (day=%d)" % game.day)
	paused = false

	# 상점
	change_scene_to_file("res://scenes/shop.tscn")
	await frames(5)
	check(current_scene.name == "Shop", "상점 씬")
	var money0: int = game.money
	game.money = 5000
	game.upgrades.tank = 0
	current_scene._buy_upgrade("tank")
	check(game.upgrades.tank == 1 and game.money == 4800, "강화 구매")

	change_scene_to_file("res://scenes/title.tscn")
	await frames(30)
	check(current_scene.name == "Title", "타이틀 씬")

	game.new_game()
	print("RESULT fails=%d" % fails)
	quit(fails)
