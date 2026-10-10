extends Node3D
## 하루 근무. 동네를 만들고 온갖 사건(흡연, 쓰레기, 무단횡단, 미성년 비행, 음주운전, 불법업소)을 내보내며
## 업무 목록, 시간, 돈, 민원, 멘탈을 관리한다.

const MAX_COMPLAINTS := 5
const COMBO_WINDOW := 8.0
const TRUCK_NEED := 6.0
const HINTS := {
	"smoke": "흡연자(빨강)는 물로! 좌클릭으로 뿌려 담배를 끄세요.",
	"trash": "길에 떨어진 쓰레기는 가까이 가서 E로 주워요.",
	"litter": "걸으면서 쓰레기 버리는 사람(주황)은 물로 혼내주세요.",
	"jaywalk": "무단횡단(노랑)은 우클릭 카메라로! 도로 위에 있을 때 좌클릭으로 찍어 신고.",
	"teen_smoke": "담배 피는 학생(분홍)한테 물은 금지! 우클릭 카메라로 찍어 학교에 신고해요.",
	"teen_drink": "술 마시는 학생 무리(보라)도 사진으로 신고해요.",
	"bully": "학교폭력 현장(진분홍)! 카메라로 찍으면 가해자들이 도망가요.",
	"drunk": "바깥 도로에서 비틀거리는 차(하늘색)를 찍으면 경찰이 출동해요.",
	"shop": "불법업소 네온 간판에 물을 계속 뿌리면 합선돼서 철거돼요!",
}
const GENERAL_HINTS := [
	"행인이나 학생에게 물을 뿌리면 민원! 민원 5건이면 근무 실패.",
	"물이 떨어지면 빨간 소화전 옆에서 E를 꾹 누르세요.",
]

@onready var water: WaterSystem = $Water
@onready var npcs: Node3D = $Npcs
@onready var player: Player = $Player
@onready var hud = $HUD
@onready var pause = $Pause
@onready var result = $Result

var city := CityBuilder.new()
var cfg := {}

var playing := false
var time_left := 0.0
var progress := {}           # 업무 id -> 해결 수
var total_resolved := 0
var earned := 0
var complaints := 0
var combo := 1.0
var best_combo := 1.0
var _combo_t := 0.0
var truck_charge := 0.0
var _timers := {}            # 사건 종류별 다음 등장까지 남은 시간
var _group_seq := 0
var _boss_spawned := false
var _all_done := false
var _hints: Array = []
var _hint_t := 0.0
var _city_sound: AudioStreamPlayer
var _capture_grace := 0.0


func _ready() -> void:
	get_tree().paused = false
	$Sun.rotation_degrees = Vector3(-50, -35, 0)
	cfg = Game.day_config(Game.day)
	city.build(self, 1000 + Game.day)
	city.apply_zone(Game.ZONES[cfg.zone].rect)

	player.water = water
	player.hydrants = city.hydrants
	player.position = Vector3(-7, 0.3, -7)
	player.rotation.y = deg_to_rad(-135)
	water.exclude = [player.get_rid()]
	water.npc_hit.connect(_on_water_hit)

	hud.bind(self, player)
	player.ammo_changed.connect(hud.set_ammo)
	player.weapon_changed.connect(hud.set_weapon)
	player.mental_changed.connect(hud.set_mental)
	player.prompt_changed.connect(hud.set_prompt)
	player.camera_mode_changed.connect(hud.set_camera_mode)
	player.photo_taken.connect(_on_photo)
	player.trash_picked.connect(func(_t): _complete("trash", "쓰레기 줍기"))
	player.hurt.connect(_on_player_hurt)
	player.call_truck.connect(_call_truck)
	pause.resumed.connect(func():
		player.input_enabled = playing
		_capture_grace = 1.0)

	for id in cfg.tasks:
		progress[id] = 0
	hud.setup_tasks(cfg.tasks)
	hud.set_day("%d일차 · %s" % [Game.day, cfg.title])
	hud.set_time(cfg.duration)
	hud.set_quota(0, _tasks_total())
	hud.set_money(Game.money)
	hud.set_mental(player.mental, Game.max_mental())
	hud.set_complaints(0, MAX_COMPLAINTS)
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
	if "smoke" in cfg.spawns:
		for i in 2:
			_spawn_smoker("normal", true)
	if "trash" in cfg.spawns:
		for i in 14:
			_spawn_trash(city.random_sidewalk_point())
	if "shop" in cfg.spawns:
		for i in max(cfg.tasks.get("shop", 0), 1):
			_spawn_shop()
	# 사건별 첫 등장 시간 (시작하자마자 하나씩은 보이도록 짧게)
	for k in ["litter", "jaywalk", "teen_smoke", "teen_drink", "bully", "drunk"]:
		if k in cfg.spawns:
			_timers[k] = randf_range(3.0, 12.0)
	if "drunk" in cfg.spawns:
		_timers["drunk"] = randf_range(15.0, 30.0)

	for id in cfg.tasks:
		if HINTS.has(id):
			_hints.append(HINTS[id])
	_hints.append_array(GENERAL_HINTS)

	_city_sound = Sfx.loop_player("city", self, -6.0)
	_city_sound.play()
	Sfx.music(true)
	_intro()


func _tasks_total() -> int:
	var n := 0
	for id in cfg.tasks:
		n += cfg.tasks[id]
	return n


func _tasks_done() -> int:
	var n := 0
	for id in cfg.tasks:
		n += min(progress[id], cfg.tasks[id])
	return n


func _intro() -> void:
	player.input_enabled = false
	var lines := []
	for id in cfg.tasks:
		lines.append("%s %d" % [Game.TASKS[id].short, cfg.tasks[id]])
	var extra := ""
	if cfg.boss:
		extra = "\n골초왕 출몰 주의!"
	var zone_line: String = "관할: " + Game.ZONES[cfg.zone].name
	if cfg.zone > Game.zone_index(Game.day - 1) and Game.day > 1:
		zone_line = "관할 구역 확장! " + Game.ZONES[cfg.zone].name
	hud.banner("%d일차  %s" % [Game.day, cfg.title], "%s\n오늘의 업무: %s%s\n클릭해서 시작" % [zone_line, " · ".join(lines), extra], 0.0)
	time_left = cfg.duration


func _start_shift() -> void:
	playing = true
	player.input_enabled = true
	player.capture_mouse()
	_capture_grace = 1.0
	hud.banner("근무 시작!", "", 0.8)
	Sfx.play("bong")
	_hint_t = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not playing and time_left > 0.0 and not result.visible:
			_start_shift()
		elif playing and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not pause.visible:
			player.capture_mouse()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and playing:
		if not pause.visible:
			pause.open()


func _notification(what: int) -> void:
	# 웹에서 Esc 를 누르면 브라우저가 마우스 잠금을 풀어버린다 → 일시정지
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and playing and not result.visible:
		pause.open()


func _process(delta: float) -> void:
	_capture_grace -= delta
	if playing and _capture_grace <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not pause.visible and not result.visible and OS.has_feature("web"):
		pause.open()
	if not playing:
		return

	time_left -= delta
	hud.set_time(time_left)
	if time_left <= 0.0:
		_end_shift(_tasks_done() >= _tasks_total(), "업무를 다 못 끝냈어요...")
		return

	_combo_t -= delta
	if _combo_t <= 0.0 and combo > 1.0:
		combo = 1.0
		hud.set_combo(combo)

	_update_spawns(delta)
	if cfg.boss and not _boss_spawned and time_left < cfg.duration * 0.65:
		_boss_spawned = true
		_spawn_boss()
	_update_boss_smoke()
	_update_hints(delta)


func _update_hints(delta: float) -> void:
	_hint_t -= delta
	if _hint_t > 0.0:
		return
	_hint_t = 8.0
	if _hints.is_empty():
		hud.set_hint("우클릭 카메라 · E 줍기 · 1~5 무기")
		return
	hud.set_hint(_hints.pop_front())


func _update_boss_smoke() -> void:
	var in_smoke := false
	for n in get_tree().get_nodes_in_group("smoker"):
		if n.kind == "boss" and n.is_smoking() and n.global_position.distance_to(player.global_position) < 7.0:
			in_smoke = true
	player.slowed = in_smoke
	hud.set_smoke(1.0 if in_smoke else 0.0)


# ---------------------------------------------------------------- 스폰

func _update_spawns(delta: float) -> void:
	if npcs_count("ped") < cfg.pedestrians:
		_spawn_pedestrian(false)

	if "smoke" in cfg.spawns:
		_tick("smoke", delta, cfg.spawn_every, func():
			if _active("smoke") < cfg.max_smokers:
				_spawn_by_weight())
	if "trash" in cfg.spawns and get_tree().get_nodes_in_group("trash").size() < 10:
		_tick("trash", delta, 4.0, func(): _spawn_trash(_far_sidewalk_point()))
	if "litter" in cfg.spawns:
		_tick("litter", delta, 20.0, func():
			if _active("litter") < 2:
				_spawn_walker("litter"))
	if "jaywalk" in cfg.spawns:
		_tick("jaywalk", delta, randf_range(14.0, 22.0), func():
			if _count_kind("jaywalker") < 2:
				_spawn_jaywalker())
	if "teen_smoke" in cfg.spawns:
		_tick("teen_smoke", delta, 24.0, func():
			if _active("teen_smoke") < 2:
				_spawn_at_spot("teen_smoker"))
	if "teen_drink" in cfg.spawns:
		_tick("teen_drink", delta, 40.0, func():
			if _active("teen_drink") == 0:
				_spawn_teen_drinkers())
	if "bully" in cfg.spawns:
		_tick("bully", delta, 45.0, func():
			if _active("bully") == 0:
				_spawn_bullying())
	if "drunk" in cfg.spawns:
		_tick("drunk", delta, randf_range(40.0, 65.0), func():
			if _active("drunk") == 0:
				_spawn_drunk_car())


func _tick(key: String, delta: float, every: float, action: Callable) -> void:
	_timers[key] = _timers.get(key, every) - delta
	if _timers[key] <= 0.0:
		_timers[key] = every
		action.call()


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


func _far_nav(min_dist := 20.0) -> int:
	for tries in 20:
		var i: int = city.allowed_nodes.pick_random()
		if city.nav_nodes[i].distance_to(player.global_position) > min_dist:
			return i
	return -1


func _far_sidewalk_point() -> Vector3:
	for tries in 10:
		var p := city.random_sidewalk_point()
		if p.distance_to(player.global_position) > 15.0:
			return p
	return city.random_sidewalk_point()


func _spawn_pedestrian(anywhere: bool) -> void:
	var idx: int = city.allowed_nodes.pick_random() if anywhere else _far_nav(14.0)
	if idx < 0:
		return
	var n := _new_npc("ped")
	n.position = city.nav_nodes[idx] + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	npcs.add_child(n)
	n.start_walking(idx)


func _spawn_walker(kind: String) -> void:
	var idx := _far_nav()
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


func _spawn_by_weight() -> void:
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
		_spawn_smoker(kind, false)


func _convert_pedestrian(kind: String) -> bool:
	## 걷던 행인이 그 자리에서 담배에 불을 붙인다.
	for n in npcs.get_children():
		if n is Npc and n.kind == "ped" and n.state == Npc.State.WALK:
			var d: float = n.global_position.distance_to(player.global_position)
			if d > 15.0 and d < 45.0:
				n.light_up(kind)
				return true
	return false


func _free_spot(min_dist: float, kinds := []) -> Dictionary:
	var options := []
	for s in city.spots:
		if not s.busy and s.pos.distance_to(player.global_position) > min_dist and (kinds.is_empty() or s.kind in kinds):
			options.append(s)
	return options.pick_random() if options.size() > 0 else {}


func _spawn_smoker(kind: String, anywhere: bool) -> Npc:
	return _spawn_at_spot(kind, 0.0 if anywhere else 18.0)


func _spawn_at_spot(kind: String, min_dist := 18.0, kinds := []) -> Npc:
	var spot := _free_spot(min_dist, kinds)
	if spot.is_empty():
		return null
	var n := _new_npc(kind)
	n.position = spot.pos + Vector3(randf_range(-0.3, 0.3), 0.05, randf_range(-0.3, 0.3))
	n.rotation.y = randf() * TAU
	npcs.add_child(n)
	n.occupy(spot)
	return n


func _spawn_group() -> void:
	var spot := _free_spot(18.0)
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
		# 가운데를 바라본다
		var to := center - n.position
		n.rotation.y = atan2(-to.x, -to.z)
		list.append(n)
	return list


func _spawn_teen_drinkers() -> void:
	var spot := _free_spot(20.0, ["bench", "park", "alley"])
	if spot.is_empty():
		return
	_group_seq += 1
	spot.busy = true
	_spawn_circle("teen_drinker", spot.pos, 3, 0.9, "teen_drink_%d" % _group_seq)
	get_tree().create_timer(30.0).timeout.connect(func(): spot.busy = false)


func _spawn_bullying() -> void:
	var spot := _free_spot(20.0, ["alley", "park"])
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
	for tries in 8:
		var path: Array = city.random_crossing()
		var a: Vector3 = path[0]
		var b: Vector3 = path[1]
		if a.distance_to(player.global_position) < 10.0 or not city.in_zone(a) or not city.in_zone(b):
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
	hud.banner("음주운전 의심 차량 제보!", "바깥 도로를 비틀비틀 달리는 차를 찾아 찍으세요", 2.5)
	Sfx.play("horn", -4.0, 0.8)


func _spawn_shop() -> void:
	var free := city.shop_slots.filter(func(s): return not s.used)
	if free.is_empty():
		return
	var slot: Dictionary = free.pick_random()
	slot.used = true
	var shop := IllegalShop.new()
	shop.type = IllegalShop.TYPES.keys().pick_random()
	add_child(shop)
	shop.global_position = slot.pos + slot.normal * 0.05
	shop.look_at(shop.global_position - slot.normal, Vector3.UP)
	shop.resolved.connect(func(s, task):
		_complete(task, Game.TASKS[task].name, s.incident_pos())
		hud.banner("불법업소 철거!", "+%d원" % Game.TASKS.shop.reward, 1.6)
		player.shake(0.4))


func _spawn_boss() -> void:
	var p: Vector3 = Vector3(city.park_center.x, 0.2, city.park_center.y) + Vector3(8, 0, 8)
	var n := _new_npc("boss")
	n.position = p
	npcs.add_child(n)
	n.say(Npc.LINES.boss.pick_random(), Color(1, 0.85, 0.3))
	hud.banner("골초왕 등장!", "공원에서 엄청난 연기가... 연기 속에선 느려져요", 2.5)
	Sfx.play("horn", -4.0, 0.7)


# ---------------------------------------------------------------- 이벤트

func _on_water_hit(target: Node, _amount: float) -> void:
	if target.has_method("wants_water") and target.wants_water():
		hud.hit(false)


func _on_npc_resolved(npc: Npc, task: String) -> void:
	var reward: int = Game.reward_for(npc.kind) if task == "smoke" else Game.TASKS[task].reward
	var name: String = {"runner": "도망자 검거!", "angry": "다혈질 진압!", "boss": "골초왕 퇴치!!"}.get(npc.kind, Game.TASKS[task].name)
	_complete(task, name, npc.global_position, reward)
	if npc.kind == "boss":
		hud.banner("골초왕 퇴치!", "", 2.0)
		player.shake(0.6)


func _complete(task: String, label: String, _pos := Vector3.ZERO, reward := -1) -> void:
	if not playing:
		return
	if reward < 0:
		reward = Game.TASKS[task].reward
	total_resolved += 1
	if task != "trash":
		Game.total_caught += 1
	if _combo_t > 0.0 and task != "trash":
		combo = min(combo + 0.25, 3.0)
	if task != "trash":
		_combo_t = COMBO_WINDOW
	best_combo = max(best_combo, combo)
	reward = int(reward * (combo if task != "trash" else 1.0))
	earned += reward
	hud.set_money(Game.money + earned)
	hud.set_combo(combo)
	hud.hit(true)
	hud.add_feed("+%d원  %s" % [reward, label], Game.TASKS[task].color.lightened(0.3))
	Sfx.play("coin", -6.0 if task == "trash" else -3.0, 1.0 + (combo - 1.0) * 0.15)

	if progress.has(task):
		progress[task] += 1
		hud.set_task(task, progress[task], cfg.tasks[task])
	hud.set_quota(_tasks_done(), _tasks_total())

	if Game.has_truck and task == "smoke":
		truck_charge = min(truck_charge + 1.0 / TRUCK_NEED, 1.0)
		hud.set_truck(truck_charge)
		if truck_charge >= 1.0:
			hud.add_feed("소방차 준비 완료! F", Color(1, 0.4, 0.3))

	if not _all_done and _tasks_done() >= _tasks_total():
		_all_done = true
		time_left = min(time_left, 30.0)
		hud.banner("오늘 업무 완료!", "30초 뒤 퇴근 · 남은 시간은 보너스", 2.2)
		Sfx.play("fanfare")


func _on_photo(targets: Array) -> void:
	hud.camera_flash()
	var names := []
	for t in targets:
		if is_instance_valid(t) and t.photo_task() != "":
			var task_id: String = t.photo_task()
			t.on_photographed()
			if not Game.TASKS[task_id].name in names:
				names.append(Game.TASKS[task_id].name)
	# 찍힌 화면을 폴라로이드로 (그려진 다음 프레임에서 캡처)
	var tex: Texture2D = null
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
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
	earned -= 20
	hud.set_money(Game.money + earned)
	hud.set_complaints(complaints, MAX_COMPLAINTS)
	hud.add_feed("민원 접수 -20원" + ("  (미성년자에게 물!)" if minor else ""), Color(1, 0.5, 0.4))
	Sfx.play("error", -4.0)
	if complaints >= MAX_COMPLAINTS:
		_end_shift(false, "민원 폭주로 퇴근...")


func _on_player_hurt(amount: int) -> void:
	if amount <= 0:
		return
	hud.damage_flash()
	Sfx.play("thud")
	if player.mental <= 0:
		_end_shift(false, "멘탈 붕괴...")


func _call_truck() -> void:
	if truck_charge < 1.0 or not playing:
		return
	truck_charge = 0.0
	hud.set_truck(0.0)
	var p := player.global_position
	# 플레이어와 가장 가까운 도로를 고른다
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


func _end_shift(success: bool, fail_reason: String) -> void:
	if not playing:
		return
	playing = false
	player.input_enabled = false
	player.set_camera_mode(false)
	var final_earned: int = earned if success else max(earned / 2, 0)
	Game.money = max(Game.money + final_earned, 0)
	var day_text := "%d일차 · %s" % [Game.day, cfg.title]
	if success:
		Game.day += 1
	Game.save_game()
	var task_lines := []
	for id in cfg.tasks:
		task_lines.append("%s %d/%d" % [Game.TASKS[id].short, progress[id], cfg.tasks[id]])
	Game.last_result = {
		"success": success, "fail_reason": fail_reason, "day_text": day_text,
		"tasks_text": " · ".join(task_lines), "resolved": total_resolved, "complaints": complaints,
		"best_combo": best_combo, "earned": final_earned,
	}
	hud.banner("퇴근!" if success else fail_reason, "", 1.2)
	await get_tree().create_timer(1.4).timeout
	result.show_result()
