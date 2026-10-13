extends Node3D
## 자유 순찰. 정해진 업무나 제한 시간 없이 동네를 돌며 마음대로 단속한다.
## 사건은 플레이어 근처에 계속 생기고, 실적이 쌓이면 그 자리에서 승진하며 관할 구역이 넓어진다.

const COMBO_WINDOW := 8.0
const NEAR := 12.0               # 사건이 생기는 거리 (플레이어 기준)
const FAR := 42.0
const STREAK_NAMES := ["", "", "더블!", "트리플!", "물벼락!", "싹쓸이!!", "동네 평화!!!"]
const CHEERS := ["속이 다 시원하네!", "잘한다!", "역시 단속반!", "오오~", "멋져요!", "그렇지!"]
const EVENTS := [
	["group", "흡연 모임 출몰!", "골목에 여럿이 모여 담배를 피워요"],
	["drunk", "음주운전 의심 차량 제보!", "바깥 도로를 비틀비틀 달리는 차를 찍으세요"],
	["shop", "불법업소 기습 개업!", "간판에 물을 뿌려 합선시킨 뒤 E 연타로 뜯어내세요"],
	["bully", "학교폭력 신고 접수!", "현장을 찾아 사진으로 남기세요"],
	["rush", "퇴근길 흡연 러시!", "30초 동안 흡연자가 쏟아져요 (보상 2배)"],
	["thief", "소매치기 주의보!", "도둑 둘이 동네에 숨어들었어요"],
	["parking", "불법주차 신고 폭주!", "횡단보도를 막은 차들을 찍어 견인시키세요"],
	["boss", "골초왕 출현!", "공원 쪽에서 엄청난 연기가..."],
]

@onready var water: WaterSystem = $Water
@onready var npcs: Node3D = $Npcs
@onready var player: Player = $Player
@onready var hud = $HUD
@onready var pause = $Pause
@onready var shop_layer: CanvasLayer = $ShopLayer
@onready var shop = $ShopLayer/Shop

var city := CityBuilder.new()
var cfg := {}
var rank := 0
var vehicle: Vehicle = null      # 지금 타고 있는 차
var last_vehicle: Vehicle = null # 마지막에 탄 차 (내리면 지도와 화면에 "내 차" 표시)
var phone: CanvasLayer           # 물대포폰 (B)
var photos: Array = []           # 사진첩 (찍은 단속 사진)

var playing := false
var complaints := 0
var combo := 1.0
var _combo_t := 0.0
var _streak := 0
var _timers := {}
var _group_seq := 0
var _event_t := 50.0
var _rush_t := 0.0
var _save_t := 20.0
var _city_sound: AudioStreamPlayer
var _capture_grace := 0.0
var day: DayCycle
var shift: Shift
var crime: Crime
var interiors: Interiors
var report: CanvasLayer
var dialogue: CanvasLayer
var ending: CanvasLayer
var inside := ""                 # 지금 들어가 있는 건물 (빈 문자열이면 바깥)
var buddy: Buddy                 # 같이 순찰 도는 신입
var favors := {}                 # 맡은 동네 부탁 role -> {count, giver}
var _return_door := {}
var _hud_t := 0.0


func _ready() -> void:
	get_tree().paused = false
	$Sun.rotation_degrees = Vector3(-50, -35, 0)
	Game.apply_quality(self)
	# 처음 보는 인물이 나올 때 디스크에서 읽느라 끊기지 않게 미리 다 읽어 둔다 (load 는 캐시됨)
	var names := {}
	for pool in Npc.POOLS.values():
		for n in pool:
			names[n] = true
	for n in names:
		load("res://assets/people/%s.glb" % n)
		Human.lib(n)
	rank = Game.rank()
	cfg = Game.patrol_config(rank)
	city.build(self, 4242)
	city.apply_zone(Game.ZONES[cfg.zone].rect)
	interiors = Interiors.new()
	add_child(interiors)
	interiors.build_all()
	day = DayCycle.new()
	add_child(day)
	day.setup(self, city)
	shift = Shift.new()
	add_child(shift)
	shift.start(self, day)
	report = load("res://ui/report.tscn").instantiate()
	add_child(report)
	report.next_day.connect(_next_day)
	dialogue = load("res://ui/dialogue.tscn").instantiate()
	add_child(dialogue)
	dialogue.player = player
	ending = load("res://ui/ending.tscn").instantiate()
	add_child(ending)
	phone = load("res://ui/phone.tscn").instantiate()
	phone.world = self
	add_child(phone)
	phone.closed.connect(_close_phone)
	phone.shop_requested.connect(func():
		phone.visible = false
		_open_shop())

	player.water = water
	player.hydrants = city.hydrants
	player.doors = city.doors
	# 시작 위치: 첫 블록 동쪽 인도, 북쪽을 보고 선다
	player.position = SPAWN
	player.rotation.y = PI
	water.exclude = [player.get_rid()]
	water.npc_hit.connect(_on_water_hit)

	hud.bind(self, player)
	player.ammo_changed.connect(hud.set_ammo)
	player.weapon_changed.connect(hud.set_weapon)
	player.mental_changed.connect(hud.set_mental)
	player.prompt_changed.connect(hud.set_prompt)
	player.camera_mode_changed.connect(hud.set_camera_mode)
	player.photo_taken.connect(_on_photo)
	player.trash_picked.connect(_on_picked)
	player.use_door.connect(_use_door)
	player.hurt.connect(_on_player_hurt)
	player.interact_vehicle.connect(_toggle_vehicle)
	player.tackled.connect(func(n):
		var dir: Vector3 = n.global_position - player.global_position
		dir.y = 0
		n.caught("tackle", dir.normalized()))
	pause.resumed.connect(func():
		player.input_enabled = playing
		_capture_grace = 1.0)
	pause.shop_requested.connect(func():
		pause.visible = false
		_open_shop())
	shop.closed.connect(_close_shop)

	_update_rank_hud()
	hud.set_money(Game.money)
	hud.set_mental(player.mental, Game.max_mental())
	hud.set_complaints(0, 0)
	hud.set_weapon(player.current)
	player.equip(Game.owned[Game.owned.size() - 1] if Game.owned.size() > 0 else "spray")

	for lane in city.ring_lanes:
		for i in 3:
			var car := TrafficCar.new()
			car.setup(lane[0], lane[1], i + randi() % 2, player)
			add_child(car)

	for i in cfg.pedestrians:
		_spawn_pedestrian(true)
	for i in 14:
		_spawn_trash(city.random_sidewalk_point())
	for i in cfg.shops:
		_spawn_shop()
	_spawn_vehicles()
	_spawn_props(22)
	_spawn_coworkers()
	_spawn_townsfolk()
	_spawn_interior_staff()
	crime = Crime.new()
	add_child(crime)
	crime.setup(self)
	refresh_doors()
	_decorate_station()
	hud.radar.range_m = 75.0 if Game.upgrades.cctv > 0 else 45.0
	# 시작하자마자 근처에 흡연자 둘
	for i in 2:
		_spawn_at_spot("normal", 6.0)

	_city_sound = Sfx.loop_player("city", self, -6.0)
	_city_sound.play()
	Sfx.music(true)
	# 출근은 파출소 안에서 (흡연자 둘은 바로 앞 길에 미리 세워 두었다)
	_go_station(interiors.rooms.station.spawn, interiors.rooms.station.yaw)
	player.input_enabled = false
	hud.banner("DAY %d" % Game.day, "클릭해서 출근", 0.0)


func _update_rank_hud() -> void:
	var span: Array = Game.rank_span()
	hud.set_rank(Game.rank_name(), Game.ZONES[cfg.zone].name, Game.xp, span[0], span[1])


func _start() -> void:
	playing = true
	player.input_enabled = true
	player.capture_mouse()
	_capture_grace = 1.0
	if day.raining:
		hud.radio("오늘 비 와요. 길 미끄러우니까 조심하고.")
	shift.begin()
	hud.banner_box.visible = false
	Sfx.play("bong")
	# 아침 조회: 소장님이 오늘의 지시를 내린다. 첫날엔 일도 가르쳐 준다 (튜토리얼 화면 대신 대화로)
	var first := not Game.flag("intro")
	var chief := get_tree().get_nodes_in_group("coworker").filter(func(c): return c.role == "chief")
	if not chief.is_empty():
		await get_tree().create_timer(0.6).timeout
		dialogue.start(Talks.briefing(shift.order, first), chief[0])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not playing:
			_start()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not pause.visible and not shop_layer.visible:
			player.capture_mouse()
	if event is InputEventKey and event.pressed and not event.echo and playing:
		if event.keycode == KEY_ESCAPE and not pause.visible and not shop_layer.visible:
			pause.open()
		elif event.keycode == KEY_B and not pause.visible and not phone.visible:
			if shop_layer.visible:
				_close_shop()
			elif not dialogue.active:
				open_phone()
		elif event.keycode == KEY_F and vehicle and not pause.visible and not shop_layer.visible:
			# 운전 중엔 플레이어 입력이 꺼져 있어서 여기서 내린다
			get_viewport().set_input_as_handled()
			_toggle_vehicle()


func _notification(what: int) -> void:
	# 웹에서 Esc 를 누르면 브라우저가 마우스 잠금을 풀어버린다 -> 일시정지
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and playing and not shop_layer.visible:
		pause.open()
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		Game.save_game()


func _open_shop() -> void:
	player.set_camera_mode(false)
	shop.refresh()
	shop_layer.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("click")


func open_phone() -> void:
	player.set_camera_mode(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	phone.open()


func _close_phone() -> void:
	get_tree().paused = false
	player.capture_mouse()
	_capture_grace = 1.0


func phone_call(who: String) -> Array:
	## 폰으로 전화. [누가, 대답]
	match who:
		"ops":
			if not mission.is_empty():
				return ["상황실 요원", "지금 출동 중이잖아요! 그거부터 끝내요."]
			if inside != "":
				return ["상황실 요원", "밖에 나가면 바로 하나 잡아 드릴게요!"]
			_mission_t = 0.5
			return ["상황실 요원", "마침 신고 하나 들어왔어요! 바로 보낼게요."]
		"mech":
			if Game.money < 50:
				return ["정비 담당", "공짜는 없어 신입~ 50원 들고 와."]
			if inside != "" or vehicle != null:
				return ["정비 담당", "밖에 있을 때 불러."]
			var car: Node3D = hud.indicators.my_car(self)
			if car == null:
				return ["정비 담당", "차가 없는데? 정비고에 말해 봐."]
			Game.money -= 50
			hud.set_money(Game.money)
			hud.money_delta(-50)
			_deliver_car(car)
			return ["정비 담당", "옆 도로에 세워 놨어! 이번엔 긁지 마라잉."]
		"chief":
			var o: Dictionary = shift.order
			return ["소장님", "오늘은 '%s'일세. %s" % [o.title, o.line] if not o.is_empty() else "오늘은 자유롭게 순찰하게."]
		"rookie":
			if buddy.active:
				buddy._go_home()
				return ["신입 순경", "알겠습니다! 파출소에서 기다릴게요."]
			buddy.sent_home = false
			if inside == "" and playing:
				buddy.join()
				return ["신입 순경", "지금 갈게요 선배님!!"]
			return ["신입 순경", "밖에 나가시면 바로 따라갈게요!"]
	return ["", ""]


func _deliver_car(car: Node3D) -> void:
	## 가장 가까운 도로 위, 차선 쪽에 차를 세운다
	var p := player.global_position
	var best_x: float = CityBuilder.ROAD_LINES[0]
	var best_z: float = CityBuilder.ROAD_LINES[0]
	for r in CityBuilder.ROAD_LINES:
		if absf(p.x - r) < absf(p.x - best_x):
			best_x = r
		if absf(p.z - r) < absf(p.z - best_z):
			best_z = r
	var pos: Vector3
	var yaw: float
	if absf(p.x - best_x) < absf(p.z - best_z):
		pos = Vector3(best_x + 2.5, 0.3, p.z)     # 세로 도로 (z 방향으로 달림)
		yaw = PI
	else:
		pos = Vector3(p.x, 0.3, best_z - 2.5)     # 가로 도로
		yaw = -PI / 2
	car.global_position = pos
	car.rotation = Vector3(0, yaw, 0)
	car.set("speed", 0.0)
	car.velocity = Vector3.ZERO


func _close_shop() -> void:
	shop_layer.visible = false
	get_tree().paused = false
	Game.save_game()
	# 새로 산 무기/강화 반영
	for id in Game.WEAPON_ORDER:
		player.ammo[id] = Game.weapon_stat(id, "tank")
	player.mental = Game.max_mental()
	hud.set_mental(player.mental, Game.max_mental())
	hud.set_money(Game.money)
	player.equip(Game.owned[Game.owned.size() - 1])
	if Game.has_truck and get_tree().get_nodes_in_group("vehicle").filter(func(v): return v.kind == "firetruck").is_empty():
		_spawn_vehicles()
	_decorate_station()
	hud.radar.range_m = 75.0 if Game.upgrades.cctv > 0 else 45.0
	player.capture_mouse()
	_capture_grace = 1.0


func _process(delta: float) -> void:
	_capture_grace -= delta
	if playing and _capture_grace <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not pause.visible and not shop_layer.visible and OS.has_feature("web"):
		pause.open()
	if not playing:
		return

	_combo_t -= delta
	if _combo_t <= 0.0 and combo > 1.0:
		combo = 1.0
		_streak = 0
		hud.set_combo(combo)

	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 20.0
		Game.save_game()

	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.25
		_update_day_hud()
	if inside != "":
		_update_mission(delta)
		return
	_update_spawns(delta)
	_update_events(delta)
	_update_boss_smoke()
	_update_mission(delta)


func _update_day_hud() -> void:
	hud.set_clock("DAY %d  %s%s" % [Game.day, day.clock_text(), "  ☂" if day.raining else ""])
	hud.set_quota(shift.quota_text(), shift.quota_done())
	hud.set_order(shift.order_text(), shift.order_cleared)
	if inside != "":
		hud.set_district("")
		return
	var i := Game.district_of(player.global_position)
	var tag := "두목 검거" if Game.raided[i] else "단서 %d/%d" % [Game.clues[i], Game.CLUES_NEEDED]
	hud.set_district("정화도 %d%% · %s %s" % [int(Game.clean[i]), Game.GANGS[i].name, tag])



func _update_boss_smoke() -> void:
	var in_smoke := false
	for n in get_tree().get_nodes_in_group("smoker"):
		if n.kind == "boss" and n.is_smoking() and n.global_position.distance_to(player.global_position) < 7.0:
			in_smoke = true
	player.slowed = in_smoke
	hud.set_smoke(1.0 if in_smoke else 0.0)


# ---------------------------------------------------------------- 사건 채우기

func _update_spawns(delta: float) -> void:
	if npcs_count("ped") < cfg.pedestrians:
		_spawn_pedestrian(false)
	if get_tree().get_nodes_in_group("trash").size() < 12:
		_tick("trash", delta, 3.0, func(): _spawn_trash(_near_sidewalk_point()))
	if _rush_t > 0.0:
		_rush_t -= delta
	# 진행 중인 사건이 목표보다 적으면 근처에 하나씩 만든다
	var clean_mul: float = lerpf(1.25, 0.7, Game.clean[Game.district_of(player.global_position)] / 100.0)
	var target: int = int(cfg.incidents * clean_mul) + (6 if _rush_t > 0.0 else 0)
	_tick("incident", delta, 1.2 if _rush_t > 0.0 else 2.5, func():
		if _active_total() < target:
			_spawn_random_incident())


func _spawn_random_incident() -> void:
	## 열린 사건 종류 중 하나를 고른다 (흡연이 가장 흔하다)
	var pool := []
	for s in cfg.spawns:
		match s:
			"smoke": pool.append_array(["smoke", "smoke"])
			"litter": pool.append_array(["litter", "litter"])
			"jaywalk": pool.append_array(["jaywalk", "jaywalk"])
			"teen_smoke": pool.append_array(["teen_smoke", "teen_smoke"])
			"teen_drink": pool.append("teen_drink")
			"bully": pool.append("bully")
			"thief": pool.append_array(["thief", "thief"])
			"pee": pool.append("pee")
			"fight": pool.append_array(["fight", "fight"])
			"graffiti": pool.append("graffiti")
			"parking": pool.append("parking")
	if shift.is_night():
		for s in ["fight", "pee", "teen_drink", "graffiti"]:
			if s in cfg.spawns:
				pool.append_array([s, s])
	# 오늘의 지시 대상은 더 자주
	for s in shift.order.get("boost", []):
		if s in cfg.spawns:
			pool.append_array([s, s, s])
	if _rush_t > 0.0:
		pool = ["smoke"]
	match pool.pick_random():
		"smoke":
			_spawn_smoker_weighted()
		"litter":
			if _active("litter") < 2:
				_spawn_walker("litter")
		"jaywalk":
			if _count_kind("jaywalker") < 2:
				_spawn_jaywalker()
		"teen_smoke":
			if _active("teen_smoke") < 2:
				_spawn_at_spot("teen_smoker")
		"teen_drink":
			if _active("teen_drink") == 0:
				_spawn_teen_drinkers()
		"bully":
			if _active("bully") == 0:
				_spawn_bullying()
		"thief":
			if _count_kind("thief") < 2:
				_spawn_walker("thief")
		"pee":
			if _active("pee") < 1:
				_spawn_wall_npc("pee")
		"fight":
			if _active("fight") < 2:
				_spawn_fight()
		"graffiti":
			if _active("graffiti") < 1:
				_spawn_wall_npc("tagger")
		"parking":
			if _active("parking") < 2:
				_spawn_parking()


func _update_events(delta: float) -> void:
	## 40~70초마다 돌발 이벤트
	if not cfg.events:
		return
	_event_t -= delta
	if _event_t > 0.0:
		return
	_event_t = randf_range(40.0, 70.0)
	var options := []
	for e in EVENTS:
		match e[0]:
			"group", "rush", "thief":
				options.append(e)
			"parking":
				if "parking" in cfg.spawns:
					options.append(e)
			"drunk", "bully":
				if e[0] in cfg.spawns:
					options.append(e)
			"shop":
				if "shop" in cfg.spawns and _active("shop") < 3:
					options.append(e)
			"boss":
				if cfg.boss and _count_kind("boss") == 0:
					options.append(e)
	if options.is_empty():
		return
	var e: Array = options.pick_random()
	hud.radio(e[1] + " " + e[2])
	Sfx.play("horn", -6.0, 0.8)
	match e[0]:
		"group": _spawn_group()
		"drunk": _spawn_drunk_car()
		"shop": _spawn_shop()
		"bully": _spawn_bullying()
		"rush": _rush_t = 30.0
		"boss": _spawn_boss()
		"thief":
			_spawn_walker("thief")
			_spawn_walker("thief")
		"parking":
			for i in 3:
				_spawn_parking()


func _tick(key: String, delta: float, every: float, action: Callable) -> void:
	_timers[key] = _timers.get(key, every) - delta
	if _timers[key] <= 0.0:
		_timers[key] = every
		action.call()


func _active_total() -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group("incident"):
		if not n.done and not n.task() in ["shop", "drunk", "parking"]:
			c += 1
	return c


func _active(task_id: String) -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group("incident"):
		if n.task() == task_id and not n.done:
			c += 1
	return c


func _count_kind(kind: String) -> int:
	var c := 0
	for n in npcs.get_children():
		if n is Npc and n.kind == kind and not n.done:
			c += 1
	return c


func npcs_count(kind: String) -> int:
	var c := 0
	for n in npcs.get_children():
		if n is Npc and n.kind == kind and n.state != Npc.State.LEAVING:
			c += 1
	return c


func _new_npc(kind: String) -> Npc:
	var n := Npc.new()
	n.setup(kind, city, player)
	n.resolved.connect(_on_npc_resolved)
	n.annoyed.connect(_on_annoyed)
	n.dropped_trash.connect(func(pos): if get_tree().get_nodes_in_group("trash").size() < 25: _spawn_trash(pos))
	n.hurt_player.connect(func(npc, amount): player.take_hit(amount, npc.global_position))
	n.dropped_bag.connect(_spawn_bag)
	n.shout.connect(func(who, text):
		if text == "도둑이야!!" and who.global_position.distance_to(player.global_position) < 45.0:
			hud.radio("소매치기 신고! 가방 든 사람 쫓아가서 부딪혀요." if not Game.flag("talk_thief") else "소매치기 신고!"))
	return n


func _dist_ok(p: Vector3, near := NEAR, far := FAR) -> bool:
	var d := p.distance_to(player.global_position)
	return d >= near and d <= far


func _near_nav() -> int:
	## 플레이어에게서 적당히 떨어진 길 노드 (너무 가깝지도 멀지도 않게)
	var ok: Array = city.allowed_nodes.filter(func(i): return _dist_ok(city.nav_nodes[i]))
	if ok.is_empty():
		ok = city.allowed_nodes.filter(func(i): return city.nav_nodes[i].distance_to(player.global_position) > 8.0)
	return ok.pick_random() if not ok.is_empty() else -1


func _near_sidewalk_point() -> Vector3:
	for tries in 12:
		var p := city.random_sidewalk_point()
		if _dist_ok(p, 6.0, 35.0):
			return p
	return city.random_sidewalk_point()


func _free_spot(kinds := [], near := NEAR) -> Dictionary:
	var all := city.spots.filter(func(s): return not s.busy and (kinds.is_empty() or s.kind in kinds))
	var ok := all.filter(func(s): return _dist_ok(s.pos, near))
	if ok.is_empty():
		ok = all.filter(func(s): return s.pos.distance_to(player.global_position) > 6.0)
	return ok.pick_random() if not ok.is_empty() else {}


func _spawn_pedestrian(anywhere: bool) -> void:
	var idx: int = city.allowed_nodes.pick_random() if anywhere else _near_nav()
	if idx < 0:
		return
	var n := _new_npc("ped")
	n.position = city.nav_nodes[idx] + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	npcs.add_child(n)
	n.start_walking(idx)


func _spawn_walker(kind: String) -> void:
	var idx := _near_nav()
	if idx < 0:
		return
	var n := _new_npc(kind)
	n.position = city.nav_nodes[idx]
	npcs.add_child(n)
	n.start_walking(idx)


func _spawn_trash(pos: Vector3) -> void:
	var t := Trash.new()
	t.position = Vector3(pos.x, 0.06, pos.z)
	add_child(t)


func _spawn_smoker_weighted() -> void:
	var total := 0.0
	for k in cfg.weights:
		total += cfg.weights[k]
	var r := randf() * total
	var kind := "normal"
	for k in cfg.weights:
		r -= cfg.weights[k]
		if r <= 0.0:
			kind = k
			break
	if kind == "group":
		_spawn_group()
	elif randf() < 0.4 and _convert_pedestrian(kind):
		pass
	else:
		_spawn_at_spot(kind)


func _convert_pedestrian(kind: String) -> bool:
	## 걷던 행인이 그 자리에서 담배에 불을 붙인다.
	for n in npcs.get_children():
		if n is Npc and n.kind == "ped" and n.state == Npc.State.WALK and _dist_ok(n.global_position):
			n.light_up(kind)
			return true
	return false


func _spawn_at_spot(kind: String, near := NEAR, kinds := []) -> Npc:
	var spot := _free_spot(kinds, near)
	if spot.is_empty():
		return null
	var n := _new_npc(kind)
	n.position = spot.pos + Vector3(randf_range(-0.3, 0.3), 0.05, randf_range(-0.3, 0.3))
	n.rotation.y = randf() * TAU
	npcs.add_child(n)
	n.occupy(spot)
	return n


func _spawn_group() -> void:
	var spot := _free_spot()
	if spot.is_empty():
		return
	spot.busy = true
	var count := randi_range(3, 4)
	for i in count:
		var kind := "angry" if i == 0 and cfg.weights.has("angry") and randf() < 0.5 else "normal"
		var n := _new_npc(kind)
		var a := TAU * i / count
		n.position = spot.pos + Vector3(cos(a), 0.05, sin(a)) * 1.0
		n.rotation.y = -a - PI / 2
		npcs.add_child(n)
	_later(20.0, func(): spot.busy = false)


func _spawn_circle(kind: String, center: Vector3, count: int, radius: float, group: String) -> Array:
	var list := []
	for i in count:
		var n := _new_npc(kind)
		var a := TAU * i / count + randf_range(-0.2, 0.2)
		n.position = center + Vector3(cos(a), 0.05, sin(a)) * radius
		n.group_id = _group_seq
		n.add_to_group(group)
		npcs.add_child(n)
		var to := center - n.position
		n.rotation.y = atan2(-to.x, -to.z)
		list.append(n)
	return list


func _spawn_teen_drinkers() -> void:
	var spot := _free_spot(["bench", "park", "alley"])
	if spot.is_empty():
		return
	_group_seq += 1
	spot.busy = true
	_spawn_circle("teen_drinker", spot.pos, 3, 0.9, "teen_drink_%d" % _group_seq)
	_later(30.0, func(): spot.busy = false)


func _spawn_bullying() -> void:
	var spot := _free_spot(["alley", "park"])
	if spot.is_empty():
		return
	_group_seq += 1
	spot.busy = true
	var group := "bully_%d" % _group_seq
	var victim := _new_npc("victim")
	victim.position = spot.pos + Vector3(0, 0.05, 0)
	victim.group_id = _group_seq
	victim.add_to_group(group)
	npcs.add_child(victim)
	for b in _spawn_circle("bully", spot.pos, 3, 1.1, group):
		b.victim = victim
	_later(30.0, func(): spot.busy = false)


func _spawn_jaywalker() -> void:
	var space := get_world_3d().direct_space_state
	for tries in 10:
		var path: Array = city.random_crossing()
		var a: Vector3 = path[0]
		var b: Vector3 = path[1]
		if not _dist_ok(a, 10.0, 45.0) or not city.in_zone(a) or not city.in_zone(b):
			continue
		# 주차된 차에 막히지 않는 자리
		var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 0.8, b + Vector3.UP * 0.8, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		var n := _new_npc("jaywalker")
		n.position = a
		npcs.add_child(n)
		n.start_crossing(b)
		return


func _spawn_drunk_car() -> void:
	var lane: Array = city.ring_lanes[randi() % city.ring_lanes.size()]
	var car := TrafficCar.new()
	car.drunk = true
	car.setup(lane[0], lane[1], randi() % 4, player)
	car.resolved.connect(func(c, task): _complete(task, Game.TASKS[task].name, c.global_position))
	add_child(car)


func _spawn_shop() -> void:
	var free := city.shop_slots.filter(func(s): return not s.used)
	if free.is_empty():
		return
	var slot: Dictionary = free.pick_random()
	slot.used = true
	var shop_node := IllegalShop.new()
	shop_node.type = IllegalShop.TYPES.keys().pick_random()
	add_child(shop_node)
	shop_node.global_position = slot.pos + slot.normal * 0.05
	shop_node.look_at(shop_node.global_position - slot.normal, Vector3.UP)
	# 업소 사장이 가게 앞을 지킨다. 철거되면 발을 구르다 사라진다
	var owner_npc := Coworker.new()
	owner_npc.role = "s_shady"
	owner_npc.position = Vector3(1.7, 0.06, 1.3)
	owner_npc.rotation.y = PI
	shop_node.add_child(owner_npc)
	shop_node.shorted.connect(func(_s):
		if is_instance_valid(owner_npc):
			owner_npc.say(["안 돼!! 전기!!", "야 이거 비싼 간판이야!", "손대지 마요!!"].pick_random(), "angry")
		if not Game.flag("talk_rip"):
			hud.radio("전원 나갔어요! 간판 앞에서 E 연타로 뜯어요. 차로 들이받아도 되고요.", "정비 담당")
		refresh_doors())
	shop_node.ripped.connect(func(_s, rammed):
		refresh_doors()
		_slowmo(0.6)
		player.shake(0.9 if rammed else 0.6)
		hud.banner("간판 철거", "", 1.4))
	shop_node.resolved.connect(func(s, task):
		if is_instance_valid(owner_npc):
			owner_npc.say(["내 가게!!", "이게 무슨 짓이에요!", "아이고 망했다..."].pick_random(), "angry")
			_later(4.0, func():
				if is_instance_valid(owner_npc):
					owner_npc.queue_free())
		_complete(task, Game.TASKS[task].name, s.incident_pos()))


func _spawn_boss() -> void:
	var p: Vector3 = Vector3(city.park_center.x, 0.2, city.park_center.y) + Vector3(8, 0, 8)
	if not city.in_zone(p):
		p = city.nav_nodes[_near_nav()]
	var n := _new_npc("boss")
	n.position = p
	npcs.add_child(n)
	n.say(Npc.LINES.boss.pick_random(), Color(1, 0.85, 0.3))


# ---------------------------------------------------------------- 이벤트

func _on_water_hit(target: Node, _amount: float) -> void:
	if target.has_method("wants_water") and target.wants_water():
		hud.hit(false)


func _on_npc_resolved(npc: Npc, task: String) -> void:
	var reward: int = Game.reward_for(npc.kind) if task == "smoke" else Game.TASKS[task].reward
	if _rush_t > 0.0 and task == "smoke":
		reward *= 2
	var name: String = {"runner": "도망자 검거!", "angry": "다혈질 진압!", "boss": "골초왕 퇴치!!", "thief": "소매치기 검거!"}.get(npc.kind, Game.TASKS[task].name)
	_complete(task, name, npc.global_position, reward, npc)
	_cheer(npc.global_position)
	if npc.kind == "boss":
		player.shake(0.6)


func _complete(task: String, label: String, pos := Vector3.ZERO, reward := -1, src: Node = null) -> void:
	if not playing:
		return
	if reward < 0:
		reward = Game.TASKS[task].reward
	if crime:
		crime.on_catch(task, pos if pos != Vector3.ZERO else player.global_position, src)
	var big := task != "trash"
	if big:
		Game.total_caught += 1
		if _combo_t > 0.0:
			combo = min(combo + 0.25, 3.0)
		_combo_t = COMBO_WINDOW
	reward = int(reward * (combo if big else 1.0))
	if shift and shift.is_order_task(task):
		reward = int(reward * Shift.ORDER_MULT)
	Game.money += reward
	hud.set_money(Game.money)
	hud.set_combo(combo)
	hud.hit(true)
	hud.money_delta(reward)
	Sfx.play("coin", -3.0 if big else -6.0, 1.0 + (combo - 1.0) * 0.15)
	if big:
		_streak += 1
		if _streak >= 2:
			Sfx.play("fanfare", -8.0, 1.0 + _streak * 0.08)
		_hitstop(0.07 if _streak < 3 else 0.12)
		player.shake(0.25)
	_add_xp(reward)
	if shift:
		shift.record_catch(task, reward)
	if big and buddy:
		buddy.on_catch(task, pos if pos != Vector3.ZERO else player.global_position)
	_progress_favors(task, pos if pos != Vector3.ZERO else player.global_position)


# ---------------------------------------------------------------- 동네 사람 부탁

func favor_status(role: String) -> String:
	if not Talks.FAVORS.has(role):
		return ""
	if Game.flags.get("favor_%s_%d" % [role, Game.day], false):
		return "done"
	if favors.has(role):
		return "active"
	return "offer" if rank >= Talks.FAVORS[role].rank else ""


func favor_progress(role: String) -> String:
	return "%d/%d" % [favors[role].count, Talks.FAVORS[role].need] if favors.has(role) else ""


func accept_favor(role: String, giver: Node3D) -> void:
	favors[role] = {"count": 0, "giver": giver}
	hud.add_feed("부탁 · %s  0/%d" % [giver.display_name(), Talks.FAVORS[role].need], Color(0.6, 0.9, 1))
	giver._update_marker()


func _favor_center(role: String) -> Vector3:
	var f: Dictionary = Talks.FAVORS[role]
	if f.has("at_door"):
		for d in city.doors:
			if d.role == f.at_door:
				return d.pos
	var g = favors[role].giver
	return g.global_position if is_instance_valid(g) else player.global_position


func _progress_favors(task: String, pos: Vector3) -> void:
	for role in favors.keys():
		var f: Dictionary = Talks.FAVORS[role]
		var c := _favor_center(role)
		if task != f.task or Vector2(pos.x - c.x, pos.z - c.z).length() > f.radius:
			continue
		favors[role].count += 1
		var giver = favors[role].giver
		var name: String = giver.display_name() if is_instance_valid(giver) else "동네 주민"
		if favors[role].count < f.need:
			hud.add_feed("부탁 · %s  %s" % [name, favor_progress(role)], Color(0.6, 0.9, 1))
			continue
		# 부탁 완료: 사례
		favors.erase(role)
		Game.flags["favor_%s_%d" % [role, Game.day]] = true
		Game.money += f.pay
		hud.set_money(Game.money)
		hud.money_delta(f.pay)
		_add_xp(f.pay)
		if f.get("mental", false):
			player.mental = Game.max_mental()
			hud.set_mental(player.mental, Game.max_mental())
		if f.get("refill", false):
			player.refill_all()
		hud.radio(f.thanks, name)
		Sfx.play("fanfare", -4.0, 1.2)
		if is_instance_valid(giver):
			giver._update_marker()


func order_cleared(order: Dictionary) -> void:
	## 소장님 특별 지시 완수: 보너스 + 무전으로 칭찬
	var bonus: int = shift.order_bonus()
	Game.money += bonus
	hud.set_money(Game.money)
	hud.money_delta(bonus)
	_add_xp(bonus)
	hud.banner("지시 완수!", order.title, 2.2)
	hud.radio(["허허, 역시 내 눈이 정확했어! 수고했네.", "벌써 다 했나? 오늘 저녁은 내가 사지!", "구청장님이 직접 전화하셨더군. 잘했네!"].pick_random(), "소장님")
	Sfx.play("fanfare", 0.0)
	player.shake(0.3)


func _add_xp(amount: int) -> void:
	Game.xp += amount
	var new_rank := Game.rank()
	if new_rank > rank:
		_promote(new_rank)
	_update_rank_hud()


func _promote(new_rank: int) -> void:
	## 그 자리에서 승진. 관할 구역이 넓어지면 바리케이드가 걷힌다.
	var old_cfg := cfg
	rank = new_rank
	cfg = Game.patrol_config(rank)
	var lines := []
	if cfg.zone != old_cfg.zone:
		city.apply_zone(Game.ZONES[cfg.zone].rect)
		lines.append("관할 확장: " + Game.ZONES[cfg.zone].name)
	var news := []
	for s in cfg.spawns:
		if not s in old_cfg.spawns:
			news.append(Game.SPAWN_NAMES[s])
	if not news.is_empty():
		lines.append("새로 나타남: " + ", ".join(news))
	for i in cfg.shops - old_cfg.shops:
		_spawn_shop()
	if cfg.zone != old_cfg.zone:
		_spawn_props(10)
	hud.banner("승진 · %s" % Game.rank_name(), " · ".join(lines), 3.0)
	Sfx.play("fanfare", 0.0)
	player.mental = Game.max_mental()
	hud.set_mental(player.mental, Game.max_mental())
	Game.save_game()


func _cheer(pos: Vector3) -> void:
	## 근처 행인들이 박수 치며 좋아한다
	var n := 0
	for p in npcs.get_children():
		if n >= 2:
			break
		if p is Npc and p.kind == "ped" and p.state == Npc.State.WALK and p.global_position.distance_to(pos) < 14.0 and randf() < 0.7:
			n += 1
			var who: Npc = p
			_later(randf_range(0.3, 0.9), func():
				if is_instance_valid(who) and who.state == Npc.State.WALK:
					who.say(CHEERS.pick_random(), Color(0.7, 1, 0.7))
					who._play("emote-yes", 0.1)
					_later(0.9, func():
						if is_instance_valid(who) and who.state == Npc.State.WALK:
							who._play("walk" if who._pause_t <= 0.0 else "idle")))


func _slowmo(real_seconds: float) -> void:
	## 잠깐 느려졌다가 돌아온다 (간판이 떨어지는 순간)
	Engine.time_scale = 0.3
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	if not (hud.wheel.visible):
		Engine.time_scale = 1.0


func _hitstop(duration: float) -> void:
	## 단속 순간 아주 잠깐 멈칫 (타격감)
	Engine.time_scale = 0.08
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


func _on_photo(targets: Array) -> void:
	hud.camera_flash()
	var names := []
	for t in targets:
		if is_instance_valid(t) and t.photo_task() != "":
			var task_id: String = t.photo_task()
			t.on_photographed()
			if not Game.TASKS[task_id].name in names:
				names.append(Game.TASKS[task_id].name)
	# 찍힌 화면을 폴라로이드로 (HUD 없이 거리만)
	var tex: Texture2D = null
	if DisplayServer.get_name() != "headless":
		hud.visible = false
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		hud.visible = true
		if img and not img.is_empty():
			img.resize(int(img.get_width() * 0.3), int(img.get_height() * 0.3), Image.INTERPOLATE_BILINEAR)
			tex = ImageTexture.create_from_image(img)
	if tex:
		photos.append(tex)
		if photos.size() > 12:
			photos.pop_front()
	if names.is_empty():
		hud.show_polaroid(tex, "신고할 만한 게 안 찍혔어요", false)
	else:
		hud.show_polaroid(tex, "신고 접수: " + ", ".join(names), true)


func _on_annoyed(_npc: Npc, minor: bool) -> void:
	if not playing:
		return
	complaints += 1
	shift.complaints += 1
	crime.on_complaint(_npc.global_position)
	Game.money = max(Game.money - 20, 0)
	hud.set_money(Game.money)
	hud.set_complaints(complaints, 0)
	hud.money_delta(-20)
	if minor and not Game.flag("talk_minor_water"):
		hud.radio("학생한테 물 뿌리면 안 돼요! 우클릭으로 사진 찍어서 학교에 넘겨요.", "소장님")
	Sfx.play("error", -4.0)


func _on_player_hurt(amount: int) -> void:
	if amount <= 0:
		return
	hud.damage_flash()
	Sfx.play("thud")
	if player.mental <= 0:
		_faint()


func _faint() -> void:
	## 멘탈이 바닥나면 잠깐 기절했다가 파출소 앞에서 다시 시작 (돈 10% 잃음)
	player.input_enabled = false
	var lost := int(Game.money * 0.1)
	Game.money -= lost
	hud.banner("기절", "", 1.8)
	hud.money_delta(-lost)
	hud.damage_flash(0.8)
	await get_tree().create_timer(2.2).timeout
	# 파출소 소파에서 깨어난다
	_go_station(interiors.rooms.station.sofa, PI / 2)
	hud.flash_fade()
	hud.radio("정신 들어요? 동네 분들이 업어다 줬어요. 좀 쉬었다 나가요.", "상황실 요원")
	player.mental = Game.max_mental()
	hud.set_mental(player.mental, Game.max_mental())
	hud.set_money(Game.money)
	player.input_enabled = true


# ---------------------------------------------------------------- 차

func _spawn_vehicles() -> void:
	## 파출소 앞 길가에 순찰차 (소방차 키가 있으면 소방차도)
	var have := {}
	for v in get_tree().get_nodes_in_group("vehicle"):
		have[v.kind] = true
	if not have.has("police"):
		_add_vehicle("police", Vector3(-13.0, 0.3, -3.6), -PI / 2)
	if Game.has_truck and not have.has("firetruck"):
		_add_vehicle("firetruck", Vector3(-23.0, 0.3, -3.6), -PI / 2)
	if Game.has_excavator and not have.has("excavator"):
		_add_vehicle("excavator", Vector3(-32.0, 0.3, -3.6), -PI / 2)


func _add_vehicle(kind: String, pos: Vector3, yaw: float, model := "") -> Vehicle:
	var v := Vehicle.new()
	v.kind = kind
	v.speed_mult = 1.15 if Game.upgrades.garage > 0 else 1.0
	v.model_name = model
	v.water = water
	v.position = pos
	v.rotation.y = yaw
	add_child(v)
	v.hit_npc.connect(_on_vehicle_hit.bind(v))
	return v


func _toggle_vehicle() -> void:
	if vehicle:
		var out := vehicle.exit()
		player.global_position = out
		player.rotation.y = vehicle.rotation.y
		player.set_driving(false)
		vehicle = null
		hud.set_driving(false)
		player.capture_mouse()
		hud.set_hint("")
		return
	if player.camera_mode or not player.input_enabled:
		return
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.can_enter(player):
			_enter(v)
			return
	# 지나가는 차 뺏기
	for t in get_tree().get_nodes_in_group("traffic"):
		if t.global_position.distance_to(player.global_position) < 3.4:
			_hijack(t)
			return


func _enter(v: Vehicle) -> void:
	vehicle = v
	last_vehicle = v
	player.set_driving(true)
	v.enter(player)
	hud.set_driving(true, v.kind)
	var keys := "W/S 가속·후진 · A/D 조향 · Space 브레이크 · F 내리기"
	match v.kind:
		"police": keys += " · H 사이렌"
		"firetruck": keys += " · 좌클릭 물대포 · H 경적"
		_: keys += " · H 경적"
	hud.set_hint(keys)


func _hijack(t: TrafficCar) -> void:
	## 지나가는 차를 세우고 운전자를 내리게 한다 (민원!)
	var pos := t.global_position + Vector3.UP * 0.3
	var yaw := t.rotation.y
	var model := t.model_name
	t.queue_free()
	var v := _add_vehicle("civilian", pos, yaw, model)
	var d := _new_npc("ped")
	d.position = pos + v.global_basis.x * 2.4
	npcs.add_child(d)
	d.start_walking(city.nearest_nav(d.position))
	d.say(["내 차!!", "도둑이야!!", "경찰 맞아요?!"].pick_random(), Color(1, 0.5, 0.4))
	_on_annoyed(d, false)
	_enter(v)


func _on_vehicle_hit(n: Node, spd: float, v: Vehicle) -> void:
	if not is_instance_valid(n) or n.state == Npc.State.DOWN:
		return
	var dir: Vector3 = n.global_position - v.global_position
	dir.y = 0
	dir = dir.normalized()
	if n.can_be_caught():
		n.caught("car", dir)
	else:
		n.run_over(dir, spd)
		if not n.done:
			_on_annoyed(n, n.is_minor())
	v.speed *= 0.7
	player.shake(0.5)


# ---------------------------------------------------------------- 도둑 가방, 줍기

func _spawn_bag(pos: Vector3, owner_npc: Node) -> void:
	var b := StolenBag.new()
	b.victim = owner_npc
	b.position = Vector3(pos.x, 0.06, pos.z)
	add_child(b)


func _on_picked(t: Node3D) -> void:
	if t is StolenBag:
		_complete("trash", "가방 돌려주기", t.global_position - Vector3.UP * 1.6, 150)
		if is_instance_valid(t.victim) and t.victim is Npc and not t.victim.done:
			t.victim.say(["감사합니다!!", "제 가방이에요!", "역시 경찰관님!"].pick_random(), Color(0.7, 1, 0.7))
			t.victim._play("emote-yes", 0.1)
	else:
		_complete("trash", "쓰레기 줍기", t.global_position - Vector3.UP * 1.6)


# ---------------------------------------------------------------- 싸움, 낙서, 노상방뇨, 불법주차

func _spawn_fight() -> void:
	var spot := _free_spot(["street", "corner", "busstop", "cafe", "park"])
	if spot.is_empty():
		return
	spot.busy = true
	var a := _new_npc("fighter")
	var b := _new_npc("fighter")
	var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 0.7
	a.position = spot.pos + off + Vector3.UP * 0.05
	b.position = spot.pos - off + Vector3.UP * 0.05
	a.partner = b
	b.partner = a
	npcs.add_child(a)
	npcs.add_child(b)
	_later(25.0, func(): spot.busy = false)


func _spawn_wall_npc(kind: String) -> void:
	## 벽 앞에 붙어서는 사람 (낙서범, 노상방뇨)
	var spot := _free_spot(["alley"])
	if spot.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var best: Dictionary = {}
	var bd := INF
	for k in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0)
		var from: Vector3 = spot.pos + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4.0, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and abs(hit.normal.y) < 0.3:
			var d: float = from.distance_to(hit.position)
			if d < bd:
				bd = d
				best = hit
	if best.is_empty():
		return
	var normal: Vector3 = best.normal
	var n := _new_npc(kind)
	n.position = Vector3(best.position.x, spot.pos.y + 0.05, best.position.z) + normal * 0.6
	n.rotation.y = atan2(normal.x, normal.z) + PI
	npcs.add_child(n)
	n.occupy(spot)
	if kind == "tagger":
		var g := Label3D.new()
		g.text = ["YOLO", "낙서왕", "ㅋㅋㅋ", "ART", "왔다감"].pick_random()
		g.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
		g.font_size = 120
		g.pixel_size = 0.008
		g.outline_size = 0
		g.modulate = [Color(1, 0.2, 0.4), Color(0.2, 1, 0.5), Color(0.3, 0.6, 1), Color(1, 0.8, 0.1)].pick_random()
		add_child(g)
		g.global_position = Vector3(best.position.x, 1.7, best.position.z) + normal * 0.03
		g.rotation = Vector3(0, atan2(normal.x, normal.z), deg_to_rad(randf_range(-10, 10)))
		g.scale = Vector3.ONE * 0.2
		n.graffiti = g


func _spawn_parking() -> void:
	var used := []
	for c in get_children():
		if c is IllegalParking:
			used.append(c.global_position)
	var options := city.parking_candidates().filter(func(c):
		for u in used:
			if u.distance_to(c[0]) < 4.0:
				return false
		return c[0].distance_to(player.global_position) > 8.0)
	if options.is_empty():
		return
	var c: Array = options.pick_random()
	var car := IllegalParking.new()
	add_child(car)
	car.global_position = c[0]
	car.rotation_degrees.y = c[1]
	car.resolved.connect(func(p, task): _complete(task, Game.TASKS[task].name, p.global_position))


# ---------------------------------------------------------------- 물리 소품

func _spawn_props(count: int) -> void:
	## 물줄기와 차에 날아가는 라바콘, 쓰레기통, 박스
	for i in count:
		var p := city.random_sidewalk_point()
		if p.distance_to(SPAWN) < 4.0:
			continue
		var body := RigidBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		var shape := CollisionShape3D.new()
		var kind := randi() % 3
		match kind:
			0:
				var m: Node3D = load("res://assets/cars/cone.glb").instantiate()
				m.scale = Vector3.ONE * 1.3
				body.add_child(m)
				var cs := CylinderShape3D.new()
				cs.radius = 0.25
				cs.height = 0.75
				shape.shape = cs
				shape.position.y = 0.38
				body.mass = 2.0
			1:
				var mi := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.3
				cm.bottom_radius = 0.26
				cm.height = 0.85
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.2, 0.5, 0.35)
				cm.material = mat
				mi.mesh = cm
				mi.position.y = 0.43
				body.add_child(mi)
				var cs := CylinderShape3D.new()
				cs.radius = 0.3
				cs.height = 0.85
				shape.shape = cs
				shape.position.y = 0.43
				body.mass = 4.0
			_:
				var m: Node3D = load("res://assets/cars/box.glb").instantiate()
				m.scale = Vector3.ONE * 0.9
				body.add_child(m)
				var bs := BoxShape3D.new()
				bs.size = Vector3.ONE * 0.64
				shape.shape = bs
				shape.position.y = 0.32
				body.mass = 1.5
		body.add_child(shape)
		body.position = p + Vector3.UP * 0.05
		body.rotation.y = randf() * TAU
		body.can_sleep = true
		add_child(body)


## t초 뒤에 fn 실행. 이 노드가 사라지면 같이 취소된다.
func _later(t: float, fn: Callable) -> void:
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_callback(fn)


# ---------------------------------------------------------------- 거점, 건물 이용

const SPAWN := Vector3(-17.0, 0.3, -7.2)     # 파출소 정문 앞
var _deco: Array[Node] = []


func _use_door(door: Dictionary) -> void:
	match door.role:
		"station", "store", "hospital":
			enter_interior(door.role, door)
		"exit":
			exit_interior()
		"hideout":
			crime.start_raid(door.gang)
		"rip":
			if is_instance_valid(door.shop):
				door.shop.tug(player.global_position)
				player.shake(0.25)
				hud.hit(false)
		"locker":
			_open_shop()
		"rest":
			player.mental = Game.max_mental()
			hud.set_mental(player.mental, Game.max_mental())
			player.refill_all()
			hud.add_feed("휴식 · 멘탈, 물 회복", Color(0.6, 0.9, 1))
			Sfx.play("refill", -4.0)
		"desk":
			if shift.can_clock_out():
				exit_interior()
				shift.end_shift()
			else:
				hud.add_feed("퇴근 불가 · 할당량 또는 22시 이후", Color(1, 0.8, 0.5))
				Sfx.play("error", -6.0)
		"counter":
			if Game.money < 30:
				hud.add_feed("돈 부족", Color(1, 0.5, 0.4))
				Sfx.play("error", -4.0)
				return
			Game.money -= 30
			player.refill_all()
			player.mental = min(player.mental + 1, Game.max_mental())
			hud.set_mental(player.mental, Game.max_mental())
			hud.set_money(Game.money)
			hud.money_delta(-30)
			Sfx.play("buy")
		"reception":
			if player.mental >= Game.max_mental():
				hud.add_feed("멘탈 정상", Color(0.8, 0.8, 0.8))
				return
			if Game.money < 100:
				hud.add_feed("돈 부족", Color(1, 0.5, 0.4))
				Sfx.play("error", -4.0)
				return
			Game.money -= 100
			player.mental = Game.max_mental()
			hud.set_mental(player.mental, Game.max_mental())
			hud.set_money(Game.money)
			hud.money_delta(-100)
			Sfx.play("buy")
		"school":
			pass


func refresh_doors() -> void:
	## 플레이어가 E 로 쓸 수 있는 자리: 바깥 건물 문 + 아지트 문 + 건물 안 상호작용 자리
	var all: Array = city.doors.duplicate()
	if crime:
		all.append_array(crime.hideouts.values())
	for key in interiors.rooms:
		all.append_array(interiors.rooms[key].points)
	for shop_node in get_tree().get_nodes_in_group("illegal_shop"):
		if shop_node.can_rip():
			all.append({"role": "rip", "shop": shop_node, "pos": shop_node.rip_point(), "normal": shop_node.global_basis.z, "label": "E 연타  간판 뜯기!"})
	player.doors = all


func enter_interior(key: String, door: Dictionary) -> void:
	if vehicle:
		_toggle_vehicle()
	var room: Dictionary = interiors.rooms[key]
	inside = key
	_return_door = door
	player.set_camera_mode(false)
	player.global_position = room.spawn
	player.rotation.y = room.yaw
	player.velocity = Vector3.ZERO
	day.indoor = true
	_city_sound.volume_db = -20.0
	hud.flash_fade()
	Sfx.play("click", -4.0, 0.7)


func exit_interior() -> void:
	if inside == "":
		return
	var was := inside
	inside = ""
	day.indoor = false
	var n: Vector3 = _return_door.get("normal", Vector3.BACK)
	player.global_position = _return_door.pos + n * 1.4 + Vector3.UP * 0.3
	player.rotation.y = atan2(-n.x, -n.z)
	player.velocity = Vector3.ZERO
	_city_sound.volume_db = -6.0
	hud.flash_fade()
	Sfx.play("click", -4.0, 0.7)
	if was == "station" and buddy and playing:
		buddy.join()


func _spawn_interior_staff() -> void:
	for pair in [["s_clerk", interiors.rooms.store.clerk], ["s_doctor", interiors.rooms.hospital.doctor]]:
		var t := Coworker.new()
		t.role = pair[0]
		t.position = pair[1]
		t.rotation.y = 0.0
		add_child(t)


func start_ending() -> void:
	## 다섯 조직을 다 잡으면: 파출소 안에 동료들이 모여 한마디씩 → 호외 → 크레딧
	if Game.ending_seen:
		return
	Game.ending_seen = true
	Game.save_game()
	await get_tree().create_timer(3.0).timeout
	hud.flash_fade()
	var room: Dictionary = interiors.rooms.station
	_go_station(room.spawn + Vector3(0, 0, -1.5), 0.0)
	if buddy:
		buddy.dismiss()
	var cw := {}
	for c in get_tree().get_nodes_in_group("coworker"):
		cw[c.role] = c
	for r in ["chief", "ops", "rookie", "mechanic"]:
		if cw.has(r):
			cw[r].global_position = room.staff[r][0]
	await get_tree().create_timer(0.5).timeout
	var convo := [
		{"who": "소장님", "at": cw.get("chief"), "text": "해냈군... 다섯 조직 전부. 처음 왔을 땐 분무기 하나 들고 쭈뼛거리더니.", "anim": "cross_arms"},
		{"who": "상황실 요원", "at": cw.get("ops"), "text": "요즘 들어오는 신고가 다 감사 전화예요. 저 이런 거 처음 받아 봐요.", "anim": "talk"},
		{"who": "신입 순경", "at": cw.get("rookie"), "text": "선배님 최고예요! 저도 꼭 선배님처럼 될게요!", "anim": "cheer"},
		{"who": "정비 담당", "at": cw.get("mechanic"), "text": "차는 좀 덜 부숴 줬으면 했지만... 뭐, 잘했어.", "anim": "laugh"},
		{"who": "소장님", "at": cw.get("chief"), "text": "구청에서 연락이 왔네. 자네를 우리 서장으로 올리고 싶다는군.", "anim": "explain"},
		{"choices": [
			["감사합니다. 열심히 하겠습니다!", [{"who": "소장님", "at": cw.get("chief"), "text": "허허, 서장님. 그래도 순찰은 계속 나가야 하네!", "anim": "salute"}]],
			["저는 아직 순찰이 좋습니다.", [{"who": "소장님", "at": cw.get("chief"), "text": "그럴 줄 알았네. 그럼 우리 동네, 앞으로도 잘 부탁하네.", "anim": "salute"}]],
		]},
	]
	convo = convo.filter(func(it): return not it.has("at") or it.at != null)
	dialogue.start(convo, cw.get("chief"))
	await dialogue.finished
	var avg := 0.0
	for c in Game.clean:
		avg += c
	ending.play({"rank": Game.rank_name(), "days": Game.day, "caught": Game.total_caught,
		"best": Game.best_grade if Game.best_grade != "" else "-", "clean": int(avg / Game.clean.size()), "money": Game.money})


func _next_day() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _spawn_coworkers() -> void:
	## 경찰은 파출소 안 자기 자리 (소장님 책상, 상황실 요원 민원 창구, 신입은 장비실 옆).
	## 정비 담당만 밖 차고에서 순찰차를 돌본다.
	var staff: Dictionary = interiors.rooms.station.staff
	for role in ["chief", "ops", "rookie"]:
		var cw := Coworker.new()
		cw.role = role
		cw.position = staff[role][0]
		cw.rotation.y = staff[role][1]
		add_child(cw)
	for c in get_children():
		if c is Coworker and c.role == "rookie":
			c.add_to_group("coworker_rookie")
	buddy = Buddy.new()
	buddy.world = self
	buddy.player = player
	add_child(buddy)
	var mech := Coworker.new()
	mech.role = "mechanic"
	mech.position = Vector3(-11.0, 0.06, -7.7)
	mech.rotation.y = PI - 0.4
	add_child(mech)


func _go_station(pos: Vector3, yaw: float) -> void:
	## 파출소 안으로 바로 옮긴다 (출근, 기절, 엔딩). 문으로 나가면 파출소 정문 앞.
	if vehicle:
		_toggle_vehicle()
	inside = "station"
	_return_door = city.doors.filter(func(d): return d.role == "station")[0]
	day.indoor = true
	if _city_sound:
		_city_sound.volume_db = -20.0
	player.global_position = pos
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO


func _spawn_townsfolk() -> void:
	## 학교 정문 앞 선생님, 가게 앞 분식집 사장님 둘 (편의점 알바와 병원 원장님은 건물 안에 있다)
	var who := {"school": "s_teacher"}
	for d in city.doors:
		if d.role in who:
			_place_town(who[d.role], d.pos + d.normal * 1.3, d.normal, 2.2)
	var fronts := city.shop_slots.filter(func(sl): return not sl.used and city.in_zone(sl.pos))
	fronts.shuffle()
	for sl in fronts.slice(0, 2):
		# 업소 자리는 비워 두고 옆으로 비켜 선다 (불법업소가 생겨도 겹치지 않게)
		_place_town("s_vendor", sl.pos + sl.normal * 1.4, sl.normal, -3.5)


func _place_town(role: String, pos: Vector3, normal: Vector3, side: float) -> void:
	var t := Coworker.new()
	t.role = role
	t.position = pos + normal.cross(Vector3.UP).normalized() * side
	t.position.y = 0.06
	t.rotation.y = atan2(-normal.x, -normal.z)
	add_child(t)


func _decorate_station() -> void:
	## 파출소 업그레이드가 눈에 보이게 (CCTV, 안테나, 정비고 간판)
	for n in _deco:
		if is_instance_valid(n):
			n.queue_free()
	_deco.clear()
	var st: Node3D = city.station_node
	if st == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.86, 0.88)
	mat.metallic = 0.4
	if Game.upgrades.cctv > 0:
		for x in [-6.5, 6.5]:
			var cam := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.25, 0.25, 0.6)
			bm.material = mat
			cam.mesh = bm
			cam.position = Vector3(x, 4.0, 7.6)
			cam.rotation_degrees.x = -25
			st.add_child(cam)
			_deco.append(cam)
	if Game.upgrades.ops > 0:
		var dish := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.2
		cm.bottom_radius = 0.2
		cm.height = 0.5
		cm.material = mat
		dish.mesh = cm
		dish.position = Vector3(-4, 11.6, -3)
		dish.rotation_degrees = Vector3(-35, 30, 0)
		st.add_child(dish)
		_deco.append(dish)
	if Game.upgrades.garage > 0:
		var l := Label3D.new()
		l.text = "정비고"
		l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
		l.font_size = 90
		l.pixel_size = 0.006
		l.modulate = Color(1, 0.85, 0.2)
		l.position = Vector3(3.2, 3.15, 7.75)
		st.add_child(l)
		_deco.append(l)


# ---------------------------------------------------------------- 무전 출동

const MISSIONS := {
	"smoke": {"title": "흡연 민원 다수", "time": 90.0, "reward": 300, "rank": 0},
	"trash": {"title": "쓰레기 무단투기 대청소", "time": 90.0, "reward": 250, "rank": 0},
	"thief": {"title": "소매치기 신고", "time": 70.0, "reward": 450, "rank": 0},
	"fight": {"title": "길거리 싸움 신고", "time": 75.0, "reward": 350, "rank": 1},
	"shop": {"title": "불법업소 영업 신고", "time": 120.0, "reward": 500, "rank": 1},
	"drunk": {"title": "음주운전 차량 추격", "time": 90.0, "reward": 700, "rank": 2},
	"school": {"title": "학교 앞 학생 비행", "time": 90.0, "reward": 450, "rank": 2},
}

var mission := {}               # 진행 중인 출동 {type, title, place, deadline, targets, reward, beacon}
var force_mission_type := ""    # 테스트용: 다음 출동 종류 고정
var _mission_t := 20.0


func _update_mission(delta: float) -> void:
	if mission.is_empty() and inside != "":
		return
	if mission.is_empty():
		_mission_t -= delta
		if _mission_t <= 0.0:
			_mission_t = randf_range(25.0, 45.0)
			_start_mission()
		return
	var left: float = mission.deadline - Time.get_ticks_msec() / 1000.0
	var alive := []
	for t in mission.targets:
		if is_instance_valid(t) and not (t.get("done") == true) and not (t.has_method("pick") and t.get("_picked") == true):
			alive.append(t)
	var pos: Vector3 = mission.pos
	if not alive.is_empty():
		pos = alive[0].global_position
	if is_instance_valid(mission.beacon):
		mission.beacon.global_position = Vector3(pos.x, 0, pos.z)
	mission.pos = pos
	var dist := player.global_position.distance_to(pos)
	hud.set_mission(mission.title, mission.place, left, dist, mission.targets.size() - alive.size(), mission.targets.size())
	if alive.is_empty():
		_finish_mission(true, left)
	elif left <= 0.0:
		_finish_mission(false, 0.0)


func _start_mission() -> void:
	var options := []
	for k in MISSIONS:
		if rank >= MISSIONS[k].rank and (k != "school" or city.in_zone(_school_pos())):
			options.append(k)
	var type: String = force_mission_type if force_mission_type != "" else options.pick_random()
	var info: Dictionary = MISSIONS[type]
	var targets: Array = []
	var pos := Vector3.ZERO
	match type:
		"smoke":
			var spot := _far_spot([])
			if spot.is_empty():
				return
			pos = spot.pos
			for i in 3:
				var n := _new_npc("normal" if i > 0 or not cfg.weights.has("runner") else "runner")
				var a := TAU * i / 3.0
				n.position = pos + Vector3(cos(a), 0.05, sin(a)) * 1.2
				n.rotation.y = randf() * TAU
				npcs.add_child(n)
				targets.append(n)
		"trash":
			pos = _far_point()
			for i in 8:
				var t := Trash.new()
				t.position = pos + Vector3(randf_range(-3, 3), 0.06, randf_range(-3, 3))
				add_child(t)
				targets.append(t)
		"thief":
			var idx := _far_nav(45.0)
			if idx < 0:
				return
			pos = city.nav_nodes[idx]
			var victim := _new_npc("ped")
			victim.position = pos
			npcs.add_child(victim)
			victim.start_walking(idx)
			var th := _new_npc("thief")
			th.position = pos + Vector3(1, 0, 0)
			th.run_speed = 6.6
			npcs.add_child(th)
			th.start_walking(idx)
			th._snatch_t = 0.0
			targets.append(th)
		"fight":
			var spot := _far_spot(["street", "corner", "busstop", "cafe", "park"])
			if spot.is_empty():
				return
			pos = spot.pos
			for i in 2:
				var f := _new_npc("fighter")
				f.position = pos + Vector3(-0.7 + i * 1.4, 0.05, 0)
				npcs.add_child(f)
				targets.append(f)
			targets[0].partner = targets[1]
			targets[1].partner = targets[0]
		"shop":
			var before := get_children().filter(func(c): return c is IllegalShop).size()
			_spawn_shop()
			var shops := get_children().filter(func(c): return c is IllegalShop)
			if shops.size() <= before or shops[-1].done:
				return
			targets.append(shops[-1])
			pos = shops[-1].global_position
		"drunk":
			_spawn_drunk_car()
			for c in get_children():
				if c is TrafficCar and c.drunk and not c.done:
					c.speed = 15.0
					targets.append(c)
					pos = c.global_position
					break
			if targets.is_empty():
				return
		"school":
			pos = _school_pos()
			for i in 2:
				var n := _spawn_at_spot("teen_smoker", 0.0, ["school"])
				if n:
					targets.append(n)
			if targets.is_empty():
				return
	var reward := int(info.reward * (1.3 if Game.upgrades.ops > 0 else 1.0))
	mission = {
		"type": type, "title": info.title, "place": _place_name(pos), "pos": pos,
		"deadline": Time.get_ticks_msec() / 1000.0 + info.time, "targets": targets,
		"reward": reward, "beacon": _make_beacon(pos),
	}
	Sfx.play("radio", 2.0)
	hud.radio("%s · %s" % [info.title, mission.place] if Game.flag("talk_mission") else "%s · %s. 파란 빛기둥 보이죠? 거기로 가요." % [info.title, mission.place])


func _finish_mission(success: bool, left: float) -> void:
	if is_instance_valid(mission.beacon):
		mission.beacon.queue_free()
	hud.set_mission("", "", 0, 0, 0, 0)
	if success:
		shift.missions_ok += 1
	else:
		shift.missions_fail += 1
	crime.on_mission(mission.pos, success)
	if success:
		var bonus := int(left * 3.0)
		var total: int = mission.reward + bonus
		Game.money += total
		hud.set_money(Game.money)
		_add_xp(total)
		hud.banner("출동 완료", "", 1.6)
		hud.money_delta(total)
		Sfx.play("fanfare", 0.0)
		player.shake(0.3)
	else:
		hud.banner("출동 실패", "", 1.4)
		Sfx.play("error", -2.0)
	mission = {}
	_mission_t = randf_range(20.0, 35.0)


func _make_beacon(pos: Vector3) -> Node3D:
	## 멀리서도 보이는 현장 표시 빛기둥
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.8
	cm.bottom_radius = 1.6
	cm.height = 60.0
	cm.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cm.material = mat
	b.mesh = cm
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
	b.global_position = Vector3(pos.x, 30.0, pos.z)
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = Vector3(pos.x, 0, pos.z)
	b.reparent(holder)
	var tw := b.create_tween().set_loops()
	tw.tween_property(mat, "albedo_color:a", 0.32, 0.6)
	tw.tween_property(mat, "albedo_color:a", 0.14, 0.6)
	return holder


func _far_nav(min_dist: float) -> int:
	var ok: Array = city.allowed_nodes.filter(func(i): return city.nav_nodes[i].distance_to(player.global_position) > min_dist)
	if ok.is_empty():
		ok = city.allowed_nodes.filter(func(i): return city.nav_nodes[i].distance_to(player.global_position) > 15.0)
	return ok.pick_random() if not ok.is_empty() else -1


func _far_spot(kinds: Array) -> Dictionary:
	var ok := city.spots.filter(func(s): return not s.busy and (kinds.is_empty() or s.kind in kinds) and s.pos.distance_to(player.global_position) > 40.0)
	if ok.is_empty():
		ok = city.spots.filter(func(s): return not s.busy and (kinds.is_empty() or s.kind in kinds) and s.pos.distance_to(player.global_position) > 15.0)
	return ok.pick_random() if not ok.is_empty() else {}


func _far_point() -> Vector3:
	for tries in 20:
		var p := city.random_sidewalk_point()
		if p.distance_to(player.global_position) > 40.0:
			return p
	return city.random_sidewalk_point()


func _school_pos() -> Vector3:
	for d in city.doors:
		if d.role == "school":
			return d.pos
	return Vector3(9999, 0, 9999)


func _place_name(pos: Vector3) -> String:
	if inside != "":
		return interiors.rooms[inside].name
	## 현장 근처 가게 이름으로 위치를 부른다 ("편의점 앞")
	var best := ""
	var bd := INF
	for b in city.buildings:
		if not is_instance_valid(b.node):
			continue
		var d: float = b.node.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = b.name
	return (best + " 근처") if best != "" else "관할 구역 안"
