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


func settle() -> void:
	## 흘려보낸 입력은 다음 물리 틱에 처리되므로 물리 프레임도 기다린다 (한 화면 프레임에 몰릴 수 있어 화면 프레임도)
	await frames(3)
	for i in 3:
		await physics_frame
	await frames(2)


func key_event(key: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = down
	Input.parse_input_event(e)


func press(key: Key) -> void:
	## 진짜 키 입력처럼 이벤트를 흘려보낸다
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = true
	Input.parse_input_event(e)
	var r := InputEventKey.new()
	r.keycode = key
	r.physical_keycode = key
	r.pressed = false
	Input.parse_input_event(r)


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

	# ---- 장비실 (B)
	world._open_shop()
	await process_frame
	check(world.shop_layer.visible and paused, "B 로 장비실 열면 게임 멈춤")
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

	_clear(world)
	await frames(5)
	player.global_position = Vector3(-8.5, 0.2, -14)
	player.rotation.y = 0
	player.camera.rotation = Vector3.ZERO
	await frames(3)

	# ---- 도둑: 행인 가방을 낚아채고 도망 → 태클 → 가방 돌려주기
	var victim = world._new_npc("ped")
	victim.position = player.global_position + Vector3(0, 0, -8)
	world.npcs.add_child(victim)
	victim.start_walking(world.city.nearest_nav(victim.position))
	var thief = world._new_npc("thief")
	thief.position = victim.position + Vector3(1.0, 0, 0)
	world.npcs.add_child(thief)
	thief.start_walking(world.city.nearest_nav(thief.position))
	thief._snatch_t = 0.0
	await frames(10)
	check(thief._stolen and thief.is_active_incident(), "도둑이 가방을 낚아챔")
	check(thief.state == 2, "도둑이 달아남")
	await frames(30)
	var xp_b: int = game.xp
	player.global_position = thief.global_position + Vector3(0, 0.2, 1.0)
	player.velocity = Vector3(0, 0, -8)
	player._tackle_cd = 0
	player._check_tackle(0.016, 8.0)
	await frames(5)
	check(thief.done, "달리다 부딪혀 태클로 검거")
	await frames(10)
	var bags: Array = world.get_tree().get_nodes_in_group("bag")
	check(bags.size() == 1, "도둑이 가방을 떨어뜨림")
	if bags.size() == 1:
		player.global_position = bags[0].global_position + Vector3(0.5, 0.2, 0)
		await frames(3)
		player._try_pickup()
		await frames(3)
	check(game.xp > xp_b + 300, "가방 돌려주기 보상 (+%d)" % (game.xp - xp_b))

	# ---- 싸움, 낙서, 노상방뇨, 불법주차
	world._spawn_fight()
	world._spawn_wall_npc("tagger")
	world._spawn_wall_npc("pee")
	world._spawn_parking()
	await frames(10)
	check(world._active("fight") == 2, "길거리 싸움 2명")
	check(world._active("graffiti") == 1 and world._active("pee") == 1, "낙서범, 노상방뇨 등장")
	check(world._active("parking") >= 1, "불법주차 차량 등장")
	for c in world.get_children():
		if c.has_method("task") and c.task() == "parking" and not c.done:
			c.on_photographed()
	await frames(3)
	check(world._active("parking") == 0, "불법주차 촬영 → 견인")

	# ---- 운전: 순찰차 타고 달려서 문제아를 들이받기
	var cars: Array = world.get_tree().get_nodes_in_group("vehicle")
	check(cars.size() >= 1, "순찰차가 길가에 있음")
	var car = cars[0]
	player.global_position = car.global_position + Vector3(2.0, 0, 0)
	await frames(3)
	press(KEY_F)
	await settle()
	check(world.vehicle == car and not player.visible, "F 키로 순찰차 탑승")
	var target = world._new_npc("normal")
	target.position = car.global_position - car.global_basis.z * 9.0
	target.position.y = 0.1
	world.npcs.add_child(target)
	await frames(5)
	car.speed = 12.0
	for i in 120:
		await physics_frame
		car.speed = 12.0
		if target.done:
			break
	check(target.done, "차로 들이받아 검거")
	press(KEY_F)
	await settle()
	check(world.vehicle == null and player.visible and player.input_enabled, "F 키로 하차")
	press(KEY_F)
	await settle()
	check(world.vehicle == car, "다시 F 키로 탑승")
	press(KEY_F)
	await settle()
	check(world.vehicle == null, "다시 F 키로 하차")

	# ---- 물리 소품이 물에 밀린다
	var prop: RigidBody3D = null
	for c in world.get_children():
		if c is RigidBody3D:
			prop = c
			break
	check(prop != null, "물리 소품 배치")
	if prop:
		var p0: Vector3 = prop.global_position
		player.global_position = p0 + Vector3(0, 0.2, 4)
		await frames(3)
		_face(player, p0 + Vector3.UP * 0.4)
		player.equip("hose")
		for i in 60:
			player._fire_drops(game.WEAPONS.hose, 2)
			await physics_frame
		check(prop.global_position.distance_to(p0) > 0.5, "소방호스에 소품이 날아감 (%.1fm)" % prop.global_position.distance_to(p0))

	# ---- 3인칭
	player.set_third_person(true)
	await frames(20)
	check(player._body.visible and player.camera.position.distance_to(Vector3(0, 1.62, 0)) > 0.4, "V로 3인칭 전환")
	player.set_third_person(false)

	# ---- 거점과 건물 문
	check(world.city.station_node != null, "파출소 건물")
	for p in world.get_tree().get_nodes_in_group("pickup"):
		p.queue_free()
	var all_cw: Array = world.get_tree().get_nodes_in_group("coworker")
	var cws: Array = all_cw.filter(func(c): return c.role in ["chief", "ops", "mechanic", "rookie"])
	check(cws.size() == 4, "파출소 동료 4명")
	check(all_cw.size() >= 7, "가게 앞 동네 사람들 (%d명)" % (all_cw.size() - 4))
	var looks := {}
	for n in world.get_tree().get_nodes_in_group("npc"):
		looks[n.model_name] = true
	check(looks.size() >= 5, "행인 생김새가 다양함 (%d종)" % looks.size())
	# Tab 무기 휠: 누르면 열리고 시간이 느려지고, 마우스를 민 쪽 무기로 바뀐다
	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	player.equip("spray")
	key_event(KEY_TAB, true)
	await frames(2)
	var wheel = world.hud.wheel
	check(wheel.visible and Engine.time_scale < 1.0, "Tab 꾹: 무기 휠 열림 + 슬로모션")
	wheel.feed(Vector2(0, 300))
	key_event(KEY_TAB, false)
	await frames(12)
	check(not wheel.visible and Engine.time_scale == 1.0 and player.current != "spray", "휠에서 고른 무기로 교체 (%s, vis=%s, ts=%.2f, in=%s)" % [player.current, wheel.visible, Engine.time_scale, player.input_enabled])
	player.global_position = cws[0].global_position + Vector3(0, 0.3, 1.5)
	await frames(3)
	player._try_pickup()
	await frames(2)
	check(cws[0]._label.text != cws[0].display_name(), "E 로 동료와 대화")
	var roles: Array = world.city.doors.map(func(d): return d.role)
	check("station" in roles and "store" in roles and "hospital" in roles, "파출소/편의점/병원 문 (%s)" % str(roles))
	var store: Dictionary = world.city.doors.filter(func(d): return d.role == "store")[0]
	game.money = 500
	player.mental = 1
	player.global_position = store.pos + Vector3(0, 0.3, 0)
	await frames(3)
	check(not player._nearest_door().is_empty(), "편의점 문 앞에서 E 안내")
	player._try_pickup()
	await frames(2)
	check(game.money == 470 and player.mental == 2, "편의점: 30원, 멘탈 +1")
	var station: Dictionary = world.city.doors.filter(func(d): return d.role == "station")[0]
	player.global_position = station.pos + Vector3(0, 0.3, 0)
	await frames(3)
	player._try_pickup()
	await frames(2)
	check(player.mental == game.max_mental() and world.shop_layer.visible, "파출소: 회복하고 장비실 열림")
	world._close_shop()
	await frames(2)

	# ---- 무전 출동: 종류마다 현장이 생기는지
	world.rank = 3
	for k in world.MISSIONS:
		if world.mission.size() > 0:
			world._finish_mission(false, 0)
		world.force_mission_type = k
		for tries in 5:
			if world.mission.is_empty():
				world._start_mission()
		check(world.mission.size() > 0 and world.mission.type == k and world.mission.targets.size() > 0, "출동 '%s' 현장 생성 (대상 %d)" % [k, world.mission.targets.size() if world.mission.size() > 0 else 0])
	# 마지막 출동(학교)을 사진으로 해결
	if world.mission.size() > 0:
		var xpm: int = game.xp
		for t in world.mission.targets:
			if t.has_method("on_photographed"):
				t.on_photographed()
		await frames(70)
		check(world.mission.is_empty() and game.xp > xpm, "출동 완료 보상 (+%d)" % (game.xp - xpm))

	# 음주운전 출동: 순찰차로 들이받기
	world.force_mission_type = "drunk"
	world._start_mission()
	var dcar = world.mission.targets[0] if world.mission.size() > 0 else null
	check(dcar != null, "음주운전 추격 출동")
	if dcar:
		dcar.on_rammed()
		await frames(70)
		check(dcar.done and world.mission.is_empty(), "순찰차로 들이받아 음주운전 검거")

	# 시간 초과
	world.force_mission_type = "smoke"
	world._start_mission()
	if world.mission.size() > 0:
		world.mission.deadline = 0.0
		await frames(5)
		check(world.mission.is_empty(), "제한 시간 지나면 출동 실패")
	world.force_mission_type = ""

	# ---- 파출소 업그레이드
	game.upgrades.cctv = 1
	game.upgrades.garage = 1
	world._close_shop()
	await frames(3)
	check(world.hud.radar.range_m > 60.0, "CCTV: 레이더 범위 증가")
	check(world._deco.size() >= 2, "업그레이드가 파출소에 보인다")
	game.upgrades.cctv = 0
	game.upgrades.garage = 0

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
