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


func _use_point(role: String) -> void:
	## 지금 건물 안의 그 자리로 가서 E
	var world = current_scene
	for p in world.player.doors:
		if p.role == role and p.pos.y < -50.0 and (world.inside == "" or p.pos.distance_to(world.interiors.rooms[world.inside].spawn) < 30.0):
			world.player.global_position = p.pos + Vector3(0, 0.3, 0)
			break
	await frames(3)
	world.player._try_pickup()
	await frames(3)


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


func _skip_dialogue() -> void:
	## 대화창을 끝까지 넘긴다 (선택지는 첫 번째)
	var w = current_scene
	for k in 40:
		if not w.dialogue.active:
			break
		if w.dialogue._choosing:
			w.dialogue._pick(["", []])
		else:
			w.dialogue._line.visible_ratio = 1.0
			w.dialogue._next()
		await frames(2)
	await create_timer(0.5).timeout


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
	game.flags["intro"] = true   # 첫날 소장님 대화는 건너뛴다
	game.flags["onboard_skip"] = true   # 온보딩 없이 처음부터 다 연다 (온보딩은 맨 끝에서 따로)
	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	game.has_truck = true

	# ---- 처음 시작: 순경, 1구역
	change_scene_to_file("res://scenes/world.tscn")
	await frames(8)
	world = current_scene
	check(world != null and world.name == "World", "월드 씬 로드")
	check(game.rank() == 0 and world.city.zone.size.x < 100, "순경은 1구역만")
	check(world.npcs.get_child_count() >= 8, "행인과 흡연자 등장 (%d명)" % world.npcs.get_child_count())
	check(world.inside == "station" and world.player.global_position.y < -50.0, "출근은 파출소 안에서")
	var staff_in: Array = world.get_tree().get_nodes_in_group("coworker").filter(func(c): return c.role in ["chief", "ops", "rookie"] and c.global_position.y < -50.0)
	check(staff_in.size() == 3, "소장님/상황실/신입은 파출소 안 (%d명)" % staff_in.size())
	var dup: Array = world.get_tree().get_nodes_in_group("coworker").filter(func(c): return c.role in ["s_clerk", "s_doctor"] and c.global_position.y > -50.0)
	check(dup.is_empty(), "편의점 알바/병원 원장님은 밖에 안 서 있다")
	world._start()
	await create_timer(0.9).timeout
	check(world.dialogue.active and world.shift.order.get("id") == "smoke", "아침 조회: 소장님이 오늘의 지시 (첫날은 흡연 단속)")
	await _skip_dialogue()
	check(world.playing and world.player.input_enabled, "조회 끝나면 바로 순찰 시작")
	world.exit_interior()
	await frames(3)
	check(world.inside == "" and world.player.global_position.y > -10.0, "파출소 문으로 나가면 바깥")
	# 신입 순경이 따라나온다
	var bud = world.buddy
	await frames(5)
	check(bud.active and bud.visible and bud.global_position.distance_to(world.player.global_position) < 6.0, "신입 순경 동행 순찰 시작")
	var station_rookie: Array = world.get_tree().get_nodes_in_group("coworker_rookie")
	check(not station_rookie.is_empty() and not station_rookie[0].visible, "따라나오면 파출소 안 신입 자리는 빈다")
	var bp0: Vector3 = world.player.global_position
	world.player.global_position = bp0 + Vector3(0, 0, -12)
	for i in 240:
		await physics_frame
	check(bud.global_position.distance_to(world.player.global_position) < 7.0, "신입이 선배를 따라온다 (%.1fm)" % bud.global_position.distance_to(world.player.global_position))
	world.player.global_position = bp0
	await frames(10)

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

	# ---- 흡연자: 물 → 돈, 실적 (오늘의 지시: 흡연 단속 진행)
	var money0: int = game.money
	var xp0: int = game.xp
	var order0: int = world.shift.order_count
	var s = world._new_npc("normal")
	_place_front(player, s, 3.0)
	world.npcs.add_child(s)
	await frames(5)
	player.equip("spray")
	_face(player, s.global_position + Vector3.UP * 1.3)
	var m_seen: int = game.money
	await frames(25)
	check(s.has_meta("seen") and game.money == m_seen + world.DISCOVER_PAY, "눈앞 사건 직접 발견 (+%d)" % (game.money - m_seen))
	money0 = game.money
	xp0 = game.xp
	for i in 14:
		player._fire_cd = 0
		player._try_single_fire()
		await frames(10)
		if s.done:
			break
	check(s.done and game.money > money0 and game.xp > xp0, "흡연자 단속 → 돈 %d, 실적 %d" % [game.money - money0, game.xp - xp0])
	check(world.shift.order_count == order0 + 1 and game.money - money0 >= 75, "지시 대상 단속: 진행 +1, 수당 1.5배 (%d원)" % (game.money - money0))
	# 신입: 근처 사건을 무전으로 알려 준다 / 물 맞으면 비명 (민원은 아님)
	var bud2 = world.buddy
	bud2._teleport_behind()
	var far_s = world._new_npc("normal")
	far_s.position = player.global_position + Vector3(14, 0.05, 0)
	world.npcs.add_child(far_s)
	await frames(30)
	world.hud._radio_queue.clear()
	world.hud.radio_box.visible = false
	bud2._spot()
	check(world.hud.radio_who.text.contains("신입") and world.hud.radio_line.text.contains("m)"), "신입이 사건 위치를 알려 줌 (%s)" % world.hud.radio_line.text)
	far_s.queue_free()
	var comp0: int = world.complaints
	bud2._wet_cd = 0.0
	bud2.soak(0.5, Vector3.FORWARD, 1.0)
	check(bud2.soaked_today == 1 and world.complaints == comp0, "신입한테 물: 비명만, 민원 없음")
	# 물대포폰: 정비 담당이 차를 가져다준다
	world.open_phone()
	await frames(3)
	check(world.phone.visible and world.get_tree().paused, "B: 폰 꺼내기 (일시정지)")
	var car_far: Node3D = world.hud.indicators.my_car(world)
	game.money += 100
	var reply: Array = world.phone_call("mech")
	check(car_far != null and car_far.global_position.distance_to(player.global_position) < 15.0, "폰: 정비 담당이 차를 근처 도로에 (%s)" % reply[1])
	world.phone.close()
	await frames(3)
	check(not world.phone.visible and not world.get_tree().paused, "폰 넣기")
	# 동네 사람 부탁: 분식집 사장님 쓰레기 다섯 개
	var vendors: Array = world.get_tree().get_nodes_in_group("coworker").filter(func(c): return c.role == "s_vendor")
	check(not vendors.is_empty() and world.favor_status("s_vendor") == "offer" and vendors[0]._marker.visible, "분식집 사장님 부탁 있음 (노란 표시)")
	if not vendors.is_empty():
		world.accept_favor("s_vendor", vendors[0])
		player.mental = 1
		for k in 5:
			world._complete("trash", "쓰레기 줍기", vendors[0].global_position + Vector3(2, 0, 0))
		check(world.favor_status("s_vendor") == "done" and player.mental == game.max_mental() and not vendors[0]._marker.visible, "부탁 완료 → 떡볶이 (멘탈 회복)")
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
	# 지시 완수 보너스
	world.shift.order_count = world.shift.order.goal - 1
	var mb: int = game.money
	var bonus: int = world.shift.order_bonus()
	world._complete("smoke", "흡연자 단속", player.global_position, 50)
	check(world.shift.order_cleared and game.money - mb >= 50 + bonus, "지시 완수 → 보너스 (%d원)" % (game.money - mb))
	check("jaywalk" in world.cfg.spawns and "shop" in world.cfg.spawns, "새 사건 종류가 열린다")
	var shops := 0
	for c in world.get_children():
		if c.has_method("_short_out"):
			shops += 1
	check(shops >= 1, "승진하면 불법업소가 생긴다 (%d곳)" % shops)

	# ---- 불법업소: 물로 합선 → E 연타로 간판 뜯기 / 차로 들이받기
	var shop_list: Array = world.get_tree().get_nodes_in_group("illegal_shop")
	if shop_list.size() > 0:
		var sh = shop_list[0]
		sh.soak(999.0, Vector3.FORWARD, 0.0)
		await frames(2)
		check(sh.is_shorted and not sh.done, "물로 합선 → 전원 차단 (아직 철거 전)")
		var rip_doors: Array = player.doors.filter(func(d): return d.role == "rip")
		check(rip_doors.size() == 1, "간판 앞에 'E 연타' 자리가 생긴다")
		var money_before: int = game.money
		for k in 3:
			world._use_door(rip_doors[0])
			await frames(2)
		await create_timer(1.0, true, false, true).timeout
		check(sh.done and game.money > money_before, "E 세 번에 간판이 뜯겨 떨어진다 (+%d원)" % (game.money - money_before))
		check(player.doors.filter(func(d): return d.role == "rip").is_empty(), "뜯고 나면 E 자리가 사라진다")
		world._spawn_shop()
		await frames(2)
		var fresh: Array = world.get_tree().get_nodes_in_group("illegal_shop").filter(func(x): return not x.done)
		if fresh.size() > 0:
			fresh[0].on_rammed()
			await frames(2)
			check(fresh[0].done, "순찰차로 들이받으면 간판이 바로 떨어진다")
		# 포크레인: 팔로 내려찍어 간판 뜯기
		game.has_excavator = true
		world._spawn_vehicles()
		var exc: Array = world.get_tree().get_nodes_in_group("vehicle").filter(func(v): return v.kind == "excavator")
		check(exc.size() == 1, "포크레인이 파출소 옆에 생긴다")
		world._spawn_shop()
		await frames(2)
		var target_shop: Array = world.get_tree().get_nodes_in_group("illegal_shop").filter(func(x): return not x.done)
		if exc.size() == 1 and target_shop.size() > 0:
			var ts = target_shop[0]
			var n: Vector3 = ts.global_basis.z
			# 팔 끝이 간판에 닿는 자리에 세우고 바로 찍는다 (골목이 좁아도 되게)
			exc[0].rotation.y = atan2(n.x, n.z)
			exc[0].global_position = ts.incident_pos() + n * 5.5 - Vector3.UP * 2.5
			exc[0]._arm_hit()
			await frames(2)
			check(ts.done, "포크레인 팔로 간판을 찍어 떨어뜨린다")

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
	check(world.inside == "station" and player.global_position.distance_to(world.interiors.rooms.station.sofa) < 1.5, "기절하면 파출소 소파에서 깨어남")
	world.exit_interior()
	await frames(3)

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
	check(looks.size() >= 3, "행인 생김새가 다양함 (%d종)" % looks.size())
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
	check(world.dialogue.active, "E 로 동료와 대화 (대화창)")
	for k in 12:
		if not world.dialogue.active:
			break
		if world.dialogue._choosing:
			world.dialogue._pick(["", []])
		else:
			world.dialogue._line.visible_ratio = 1.0
			world.dialogue._next()
		await frames(2)
	await create_timer(0.5).timeout
	check(not world.dialogue.active and player.input_enabled, "대화 끝나면 다시 움직임")
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
	check(world.inside == "store" and player.global_position.y < -50.0, "편의점 문 → 가게 안으로")
	await _use_point("counter")
	check(game.money == 470 and player.mental == 2, "편의점 계산대: 30원, 멘탈 +1")
	await _use_point("exit")
	check(world.inside == "" and player.global_position.distance_to(store.pos) < 4.0, "밖으로 나오면 가게 문 앞")
	var station: Dictionary = world.city.doors.filter(func(d): return d.role == "station")[0]
	player.global_position = station.pos + Vector3(0, 0.3, 0)
	await frames(3)
	player._try_pickup()
	await frames(2)
	check(world.inside == "station", "파출소 안으로")
	await _use_point("rest")
	check(player.mental == game.max_mental(), "파출소 소파: 멘탈 회복")
	await _use_point("locker")
	check(world.shop_layer.visible, "파출소 사물함: 장비실 열림")
	world._close_shop()
	await frames(2)
	await _use_point("desk")
	check(not world.report.visible, "할당량 전엔 퇴근 못 함")
	await _use_point("exit")

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

	# ---- 밤: 해가 지면 가로등이 켜지고 간판이 밝아진다
	world.day.hour = 22.0
	world.day.apply()
	check(world.city.lamp_lights.size() > 0 and world.city.lamp_lights[0].light_energy > 1.0 and world.get_node("Sun").light_energy < 0.5, "밤 22시: 가로등 켜짐, 해 짐")
	world.day.hour = 13.0
	world.day.apply()
	check(world.city.lamp_lights[0].light_energy < 0.1, "낮 13시: 가로등 꺼짐")

	# ---- 조직: 단서가 다 모이면 아지트가 드러나고, 급습해서 두목까지 잡으면 구역 정화
	game.clues[0] = game.CLUES_NEEDED - 1
	game.raided[0] = false
	var clean0: float = game.clean[0]
	world.crime.on_catch("thief", world.SPAWN)
	check(game.clues[0] == game.CLUES_NEEDED and world.crime.hideouts.has(0), "단서 %d개 → 아지트 발견" % game.CLUES_NEEDED)
	var hide: Dictionary = world.crime.hideouts.get(0, {})
	if not hide.is_empty():
		player.global_position = hide.pos + Vector3(0, 0.3, 0)
		await frames(3)
		player._try_pickup()
		await frames(5)
		check(world.inside == "smoke_den" and world.crime.raid.targets.size() >= 4, "아지트 안으로 급습 (일당 %d)" % world.crime.raid.get("targets", []).size())
		var boss_ok: bool = world.crime.raid.targets.any(func(n): return n.kind == "boss" and n.model_name == "m_boss")
		check(boss_ok, "두목은 골초왕 모델")
		for n in world.crime.raid.targets:
			n.caught("tackle", Vector3.FORWARD)
		for k in 60:
			if world.crime.raid.is_empty():
				break
			await frames(1)
		check(game.raided[0] and game.clean[0] >= minf(clean0 + 25.0, 100.0) and world.crime.raid.is_empty(), "급습 성공: 두목 검거, 정화도 +30")
		await _use_point("exit")

	# ---- 엔딩: 다섯 조직을 다 잡으면 동료 대화 → 호외 → 크레딧
	for gi in game.GANGS.size():
		game.raided[gi] = gi != 4
	game.ending_seen = false
	game.clues[4] = game.CLUES_NEEDED
	world.crime._reveal(4, false)
	if world.crime.hideouts.has(4):
		world.crime.start_raid(4)
		await frames(3)
		for n in world.crime.raid.targets:
			n.caught("tackle", Vector3.FORWARD)
		await frames(5)
		await create_timer(4.2).timeout
		check(world.dialogue.active and game.ending_seen, "마지막 두목 검거 → 엔딩 대화")
		for k in 20:
			if not world.dialogue.active:
				break
			if world.dialogue._choosing:
				world.dialogue._pick(["", []])
			else:
				world.dialogue._line.visible_ratio = 1.0
				world.dialogue._next()
			await frames(2)
		await create_timer(0.6).timeout
		check(world.ending.visible, "호외와 크레딧")
		world.ending.visible = false
		world.get_tree().paused = false
	else:
		check(false, "5구역 아지트 자리 없음")

	# ---- 퇴근: 성적표와 신문, 다음 날
	var day0: int = game.day
	world.shift.end_shift()
	await frames(5)
	check(world.report.visible and game.day == day0 + 1, "퇴근 성적표 (DAY %d)" % day0)
	check(world.report.get_node("Row/Paper/V/Headline").text.contains("검거"), "신문 1면: 두목 검거 (%s)" % world.report.get_node("Row/Paper/V/Headline").text)
	world.report.visible = false
	world.get_tree().paused = false

	# ---- 진행 저장 → 다시 열면 계급 유지
	game.save_game()
	var xp_saved: int = game.xp
	game.xp = 0
	game.load_game()
	check(game.xp == xp_saved, "실적 저장/불러오기")

	change_scene_to_file("res://scenes/title.tscn")
	await frames(30)
	check(current_scene.name == "Title", "타이틀 씬")

	# ---- 온보딩: 1일차는 담배만 걸어서, 2일차 출동·순찰차 키
	game.new_game()
	game.flags["intro"] = true
	change_scene_to_file("res://scenes/world.tscn")
	await frames(10)
	var w1 = current_scene
	check(w1.cfg.spawns == ["smoke", "trash"] and w1.shift.mission_quota == 0 and w1.shift.order.is_empty() and not w1.day.raining, "1일차: 담배·쓰레기만, 출동·지시·비 없음 (%s)" % str(w1.cfg.spawns))
	check(not w1.car_ok() and w1.favor_status("s_vendor") == "", "1일차: 순찰차·부탁 없음")
	w1._start()
	await create_timer(0.9).timeout
	await _skip_dialogue()
	w1.exit_interior()
	w1._mission_t = 0.0
	await frames(10)
	check(w1.mission.is_empty() and w1.buddy.active, "1일차: 출동 무전 없이 신입이랑 걸어서 순찰")
	game.day = 2
	change_scene_to_file("res://scenes/world.tscn")
	await frames(10)
	var w2 = current_scene
	var mech: Array = w2.get_tree().get_nodes_in_group("coworker").filter(func(c): return c.role == "mechanic")
	check(not w2.car_ok() and w2.shift.mission_quota == 1 and "litter" in w2.cfg.spawns, "2일차: 출동·무단투기 시작, 키는 아직")
	check(not mech.is_empty() and mech[0].has_topic(), "2일차: 정비 담당 노란 표시 (키 주려고)")
	game.flags["talk_mechanic"] = true
	check(w2.car_ok(), "정비 담당한테 키 받으면 순찰차")
	game.day = 4
	check(game.unlocked("orders") and game.unlocked("thief"), "4일차: 지시·소매치기까지 다 열림")

	game.new_game()
	game.flags["intro"] = true   # 첫날 소장님 대화는 건너뛴다
	game.flags["onboard_skip"] = true   # 온보딩 없이 처음부터 다 연다 (온보딩은 맨 끝에서 따로)
	print("RESULT fails=%d" % fails)
	quit(fails)
