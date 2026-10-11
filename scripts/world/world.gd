extends Node3D
## 자유 순찰. 정해진 업무나 제한 시간 없이 동네를 돌며 마음대로 단속한다.
## 사건은 플레이어 근처에 계속 생기고, 실적이 쌓이면 그 자리에서 승진하며 관할 구역이 넓어진다.

const COMBO_WINDOW := 8.0
const TRUCK_NEED := 6.0
const NEAR := 12.0               # 사건이 생기는 거리 (플레이어 기준)
const FAR := 42.0
const STREAK_NAMES := ["", "", "더블!", "트리플!", "물벼락!", "싹쓸이!!", "동네 평화!!!"]
const CHEERS := ["속이 다 시원하네!", "잘한다!", "역시 단속반!", "오오~", "멋져요!", "그렇지!"]
const HINTS := [
	"연기 나는 사람(흡연자)에게 좌클릭으로 물을 뿌려 담배를 끄세요.",
	"길에 떨어진 쓰레기는 가까이 가서 E로 주워요.",
	"오른쪽 위 레이더의 색 점이 사건이에요. 화면 가장자리 화살표도 따라가 보세요.",
	"행인이나 학생에게 물을 뿌리면 민원(-20원)! 학생 비행은 우클릭 카메라로 찍어 신고해요.",
	"뛰는 사람 앞 바닥에 물을 깔아두면 미끄러져요.",
	"Tab: 장비실 · 물이 떨어지면 빨간 소화전 옆에서 E를 꾹",
]
const EVENTS := [
	["group", "흡연 모임 출몰!", "골목에 여럿이 모여 담배를 피워요"],
	["drunk", "음주운전 의심 차량 제보!", "바깥 도로를 비틀비틀 달리는 차를 찍으세요"],
	["shop", "불법업소 기습 개업!", "네온 간판에 물을 뿌려 합선시키세요"],
	["bully", "학교폭력 신고 접수!", "현장을 찾아 사진으로 남기세요"],
	["rush", "퇴근길 흡연 러시!", "30초 동안 흡연자가 쏟아져요 (보상 2배)"],
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

var playing := false
var complaints := 0
var combo := 1.0
var _combo_t := 0.0
var _streak := 0
var truck_charge := 0.0
var _timers := {}
var _group_seq := 0
var _event_t := 50.0
var _rush_t := 0.0
var _hint_i := 0
var _hint_t := 0.0
var _save_t := 20.0
var _city_sound: AudioStreamPlayer
var _capture_grace := 0.0


func _ready() -> void:
	get_tree().paused = false
	$Sun.rotation_degrees = Vector3(-50, -35, 0)
	rank = Game.rank()
	cfg = Game.patrol_config(rank)
	city.build(self, 4242)
	city.apply_zone(Game.ZONES[cfg.zone].rect)

	player.water = water
	player.hydrants = city.hydrants
	# 시작 위치: 첫 블록 동쪽 인도, 북쪽을 보고 선다
	player.position = Vector3(-8.5, 0.3, -14.0)
	player.rotation.y = deg_to_rad(-20)
	water.exclude = [player.get_rid()]
	water.npc_hit.connect(_on_water_hit)

	hud.bind(self, player)
	player.ammo_changed.connect(hud.set_ammo)
	player.weapon_changed.connect(hud.set_weapon)
	player.mental_changed.connect(hud.set_mental)
	player.prompt_changed.connect(hud.set_prompt)
	player.camera_mode_changed.connect(hud.set_camera_mode)
	player.photo_taken.connect(_on_photo)
	player.trash_picked.connect(func(t): _complete("trash", "쓰레기 줍기", t.global_position - Vector3.UP * 1.6))
	player.hurt.connect(_on_player_hurt)
	player.call_truck.connect(_call_truck)
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
	hud.set_truck(0.0)
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
	# 시작하자마자 근처에 흡연자 둘
	for i in 2:
		_spawn_at_spot("normal", 6.0)

	_city_sound = Sfx.loop_player("city", self, -6.0)
	_city_sound.play()
	Sfx.music(true)
	player.input_enabled = false
	hud.banner("%s · 자유 순찰" % Game.rank_name(), "%s\n클릭해서 시작" % Game.ZONES[cfg.zone].name, 0.0)


func _update_rank_hud() -> void:
	var span: Array = Game.rank_span()
	hud.set_rank(Game.rank_name(), Game.ZONES[cfg.zone].name, Game.xp, span[0], span[1])


func _start() -> void:
	playing = true
	player.input_enabled = true
	player.capture_mouse()
	_capture_grace = 1.0
	hud.banner("순찰 시작!", "", 0.8)
	Sfx.play("bong")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not playing:
			_start()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not pause.visible and not shop_layer.visible:
			player.capture_mouse()
	if event is InputEventKey and event.pressed and not event.echo and playing:
		if event.keycode == KEY_ESCAPE and not pause.visible and not shop_layer.visible:
			pause.open()
		elif event.keycode == KEY_TAB and not pause.visible:
			if shop_layer.visible:
				_close_shop()
			else:
				_open_shop()


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
	hud.set_truck(truck_charge)
	player.equip(Game.owned[Game.owned.size() - 1])
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

	_update_spawns(delta)
	_update_events(delta)
	_update_boss_smoke()
	_update_hints(delta)


func _update_hints(delta: float) -> void:
	_hint_t -= delta
	if _hint_t > 0.0:
		return
	_hint_t = 9.0
	if _hint_i < HINTS.size():
		hud.set_hint(HINTS[_hint_i])
		_hint_i += 1
	else:
		hud.set_hint("")


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
	var target: int = cfg.incidents + (6 if _rush_t > 0.0 else 0)
	_tick("incident", delta, 1.2 if _rush_t > 0.0 else 2.5, func():
		if _active_total() < target:
			_spawn_random_incident())


func _spawn_random_incident() -> void:
	## 열린 사건 종류 중 하나를 고른다 (흡연이 가장 흔하다)
	var pool := []
	for s in cfg.spawns:
		match s:
			"smoke": pool.append_array(["smoke", "smoke", "smoke", "smoke"])
			"litter": pool.append_array(["litter", "litter"])
			"jaywalk": pool.append_array(["jaywalk", "jaywalk"])
			"teen_smoke": pool.append_array(["teen_smoke", "teen_smoke"])
			"teen_drink": pool.append("teen_drink")
			"bully": pool.append("bully")
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
			"group", "rush":
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
	hud.banner(e[1], e[2], 2.5)
	Sfx.play("horn", -6.0, 0.8)
	match e[0]:
		"group": _spawn_group()
		"drunk": _spawn_drunk_car()
		"shop": _spawn_shop()
		"bully": _spawn_bullying()
		"rush": _rush_t = 30.0
		"boss": _spawn_boss()


func _tick(key: String, delta: float, every: float, action: Callable) -> void:
	_timers[key] = _timers.get(key, every) - delta
	if _timers[key] <= 0.0:
		_timers[key] = every
		action.call()


func _active_total() -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group("incident"):
		if not n.done and n.task() != "shop" and n.task() != "drunk":
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
	get_tree().create_timer(20.0).timeout.connect(func(): spot.busy = false)


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
	get_tree().create_timer(30.0).timeout.connect(func(): spot.busy = false)


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
	get_tree().create_timer(30.0).timeout.connect(func(): spot.busy = false)


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
	shop_node.resolved.connect(func(s, task):
		_complete(task, Game.TASKS[task].name, s.incident_pos())
		hud.banner("불법업소 철거!", "", 1.6)
		player.shake(0.4))


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
	var name: String = {"runner": "도망자 검거!", "angry": "다혈질 진압!", "boss": "골초왕 퇴치!!"}.get(npc.kind, Game.TASKS[task].name)
	_complete(task, name, npc.global_position, reward)
	_cheer(npc.global_position)
	if npc.kind == "boss":
		hud.banner("골초왕 퇴치!", "", 2.0)
		player.shake(0.6)


func _complete(task: String, label: String, pos := Vector3.ZERO, reward := -1) -> void:
	if not playing:
		return
	if reward < 0:
		reward = Game.TASKS[task].reward
	var big := task != "trash"
	if big:
		Game.total_caught += 1
		if _combo_t > 0.0:
			combo = min(combo + 0.25, 3.0)
		_combo_t = COMBO_WINDOW
	reward = int(reward * (combo if big else 1.0))
	Game.money += reward
	hud.set_money(Game.money)
	hud.set_combo(combo)
	hud.hit(true)
	hud.add_feed("+%d원  %s" % [reward, label], Game.TASKS[task].color.lightened(0.3))
	Sfx.play("coin", -3.0 if big else -6.0, 1.0 + (combo - 1.0) * 0.15)
	if pos != Vector3.ZERO:
		Popups.text(self, pos + Vector3.UP * 2.4, "+%d원" % reward, Color(1, 0.88, 0.3), 80 if big else 54, 1.6, 1.1)
	if big:
		_streak += 1
		if _streak >= 2:
			hud.announce(STREAK_NAMES[min(_streak, STREAK_NAMES.size() - 1)])
			Sfx.play("fanfare", -8.0, 1.0 + _streak * 0.08)
		_hitstop(0.07 if _streak < 3 else 0.12)
		player.shake(0.25)
	_add_xp(reward)

	if Game.has_truck and task == "smoke":
		truck_charge = min(truck_charge + 1.0 / TRUCK_NEED, 1.0)
		hud.set_truck(truck_charge)
		if truck_charge >= 1.0:
			hud.add_feed("소방차 준비 완료! F", Color(1, 0.4, 0.3))


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
	hud.banner("승진! %s" % Game.rank_name(), "\n".join(lines), 3.0)
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
			get_tree().create_timer(randf_range(0.3, 0.9)).timeout.connect(func():
				if is_instance_valid(who) and who.state == Npc.State.WALK:
					who.say(CHEERS.pick_random(), Color(0.7, 1, 0.7))
					who._play("emote-yes", 0.1)
					get_tree().create_timer(0.9).timeout.connect(func():
						if is_instance_valid(who) and who.state == Npc.State.WALK:
							who._play("walk")))


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
	if names.is_empty():
		hud.show_polaroid(tex, "신고할 만한 게 안 찍혔어요", false)
	else:
		hud.show_polaroid(tex, "신고 접수: " + ", ".join(names), true)


func _on_annoyed(_npc: Npc, minor: bool) -> void:
	if not playing:
		return
	complaints += 1
	Game.money = max(Game.money - 20, 0)
	hud.set_money(Game.money)
	hud.set_complaints(complaints, 0)
	hud.add_feed("민원 접수 -20원" + ("  (미성년자에게 물!)" if minor else ""), Color(1, 0.5, 0.4))
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
	hud.banner("멘탈 붕괴...", "파출소에서 정신 차리는 중 (-%d원)" % lost, 2.0)
	hud.damage_flash(0.8)
	await get_tree().create_timer(2.2).timeout
	player.global_position = Vector3(-8.5, 0.3, -14.0)
	player.mental = Game.max_mental()
	hud.set_mental(player.mental, Game.max_mental())
	hud.set_money(Game.money)
	player.input_enabled = true


func _call_truck() -> void:
	if truck_charge < 1.0 or not playing:
		return
	truck_charge = 0.0
	hud.set_truck(0.0)
	var p := player.global_position
	var best_d := INF
	var along_x := false
	var line := 0.0
	for c in [-CityBuilder.PITCH, 0.0, CityBuilder.PITCH]:
		if abs(p.x - c) < best_d:
			best_d = abs(p.x - c)
			along_x = false
			line = c
		if abs(p.z - c) < best_d:
			best_d = abs(p.z - c)
			along_x = true
			line = c
	var lane: float = 2.5 * (sign((p.z if along_x else p.x) - line) if best_d > 0.5 else 1.0)
	var truck := FireTruck.new()
	truck.water = water
	truck.player = player
	add_child(truck)
	truck.launch(along_x, line, lane)
	hud.banner("소방차 출동!", "", 1.5)
