extends Node3D
## 하루 근무. 동네를 만들고 행인/흡연자를 내보내며 시간, 목표, 돈, 민원, 멘탈을 관리한다.

const MAX_COMPLAINTS := 5
const COMBO_WINDOW := 8.0
const TRUCK_NEED := 6.0
const TUTORIAL := [
	"빨간 표시와 연기가 나는 사람이 흡연자! 다가가서 좌클릭으로 물을 뿌려 담배를 끄세요.",
	"오른쪽 위 레이더의 빨간 점이 흡연자예요. 화면 가장자리 화살표도 따라가 보세요.",
	"담배 안 피우는 행인에게 뿌리면 민원이 쌓여요. 민원 5건이면 그날 근무 실패!",
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
var caught := 0
var earned := 0
var complaints := 0
var combo := 1.0
var best_combo := 1.0
var _combo_t := 0.0
var truck_charge := 0.0
var _spawn_t := 0.0
var _boss_spawned := false
var _quota_announced := false
var _tutorial_i := 0
var _tutorial_t := 0.0
var _city_sound: AudioStreamPlayer
var _capture_grace := 0.0


func _ready() -> void:
	get_tree().paused = false
	$Sun.rotation_degrees = Vector3(-50, -35, 0)
	cfg = Game.day_config(Game.day)
	city.build(self, 1000 + Game.day)

	player.water = water
	player.hydrants = city.hydrants
	player.position = Vector3(-7, 0.3, -7)
	player.rotation.y = deg_to_rad(-135)
	water.exclude = [player.get_rid()]
	water.npc_hit.connect(_on_npc_hit)

	hud.bind(self, player)
	player.ammo_changed.connect(hud.set_ammo)
	player.weapon_changed.connect(hud.set_weapon)
	player.mental_changed.connect(hud.set_mental)
	player.hydrant_nearby.connect(func(near): hud.set_prompt("E 꾹 눌러 물 채우기" if near else ""))
	player.hurt.connect(_on_player_hurt)
	player.call_truck.connect(_call_truck)
	pause.resumed.connect(func():
		player.input_enabled = playing
		_capture_grace = 1.0)

	hud.set_day("%d일차 · %s" % [Game.day, cfg.title])
	hud.set_time(cfg.duration)
	hud.set_quota(0, cfg.quota)
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
	for i in 2:
		_spawn_smoker("normal", true)

	_city_sound = Sfx.loop_player("city", self, -6.0)
	_city_sound.play()
	Sfx.music(true)
	_intro()


func _intro() -> void:
	player.input_enabled = false
	var enemies := ""
	if cfg.weights.has("runner"):
		enemies += " · 도망자 주의"
	if cfg.weights.has("angry"):
		enemies += " · 다혈질 주의"
	if cfg.boss:
		enemies += " · 골초왕 출몰"
	hud.banner("%d일차  %s" % [Game.day, cfg.title], "목표: 흡연자 %d명 단속%s\n클릭해서 시작" % [cfg.quota, enemies], 0.0)
	time_left = cfg.duration


func _start_shift() -> void:
	playing = true
	player.input_enabled = true
	player.capture_mouse()
	_capture_grace = 1.0
	hud.banner("단속 시작!", "", 0.8)
	Sfx.play("bong")
	_tutorial_t = 0.0


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
		_end_shift(caught >= cfg.quota, "시간 초과...")
		return

	_combo_t -= delta
	if _combo_t <= 0.0 and combo > 1.0:
		combo = 1.0
		hud.set_combo(combo)

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = cfg.spawn_every * randf_range(0.7, 1.2)
		if _active_smokers() < cfg.max_smokers:
			_spawn_by_weight()
	if npcs_count("ped") < cfg.pedestrians:
		_spawn_pedestrian(false)

	if cfg.boss and not _boss_spawned and time_left < cfg.duration * 0.65:
		_boss_spawned = true
		_spawn_boss()

	_update_boss_smoke()
	_update_tutorial(delta)


func _update_tutorial(delta: float) -> void:
	if Game.day != 1 or _tutorial_i >= TUTORIAL.size():
		hud.set_hint("")
		return
	_tutorial_t -= delta
	if _tutorial_t <= 0.0:
		hud.set_hint(TUTORIAL[_tutorial_i])
		_tutorial_i += 1
		_tutorial_t = 9.0


func _update_boss_smoke() -> void:
	var in_smoke := false
	for n in get_tree().get_nodes_in_group("smoker"):
		if n.kind == "boss" and n.is_smoking() and n.global_position.distance_to(player.global_position) < 7.0:
			in_smoke = true
	player.slowed = in_smoke
	hud.set_smoke(1.0 if in_smoke else 0.0)


# ---------------------------------------------------------------- 스폰

func npcs_count(kind: String) -> int:
	var c := 0
	for n in npcs.get_children():
		if n is Npc and n.kind == kind and n.state != Npc.State.LEAVING:
			c += 1
	return c


func _active_smokers() -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group("smoker"):
		if n.is_smoking():
			c += 1
	return c


func _new_npc(kind: String) -> Npc:
	var n := Npc.new()
	n.setup(kind, city, player)
	n.extinguished.connect(_on_extinguished)
	n.annoyed.connect(_on_annoyed)
	n.hurt_player.connect(func(npc, amount): player.take_hit(amount, npc.global_position))
	return n


func _spawn_pedestrian(anywhere: bool) -> void:
	var idx := -1
	for tries in 20:
		var i := randi() % city.nav_nodes.size()
		if anywhere or city.nav_nodes[i].distance_to(player.global_position) > 20.0:
			idx = i
			break
	if idx < 0:
		return
	var n := _new_npc("ped")
	n.position = city.nav_nodes[idx] + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	npcs.add_child(n)
	n.start_walking(idx)


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


func _free_spot(min_dist: float) -> Dictionary:
	var options := []
	for s in city.spots:
		if not s.busy and s.pos.distance_to(player.global_position) > min_dist:
			options.append(s)
	return options.pick_random() if options.size() > 0 else {}


func _spawn_smoker(kind: String, anywhere: bool) -> Npc:
	var spot := _free_spot(0.0 if anywhere else 18.0)
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


func _spawn_boss() -> void:
	var p: Vector3 = Vector3(city.park_center.x, 0.2, city.park_center.y) + Vector3(8, 0, 8)
	var n := _new_npc("boss")
	n.position = p
	npcs.add_child(n)
	n.say(Npc.LINES.boss.pick_random(), Color(1, 0.85, 0.3))
	hud.banner("골초왕 등장!", "공원에서 엄청난 연기가... 연기 속에선 느려져요", 2.5)
	Sfx.play("horn", -4.0, 0.7)


# ---------------------------------------------------------------- 이벤트

func _on_npc_hit(npc: Node, _amount: float) -> void:
	if npc.is_smoker_kind():
		hud.hit(false)


func _on_extinguished(npc: Npc) -> void:
	caught += 1
	Game.total_caught += 1
	if _combo_t > 0.0:
		combo = min(combo + 0.25, 3.0)
	_combo_t = COMBO_WINDOW
	best_combo = max(best_combo, combo)
	var reward := int(Game.reward_for(npc.kind) * combo)
	earned += reward
	hud.set_money(Game.money + earned)
	hud.set_combo(combo)
	hud.set_quota(caught, cfg.quota)
	hud.hit(true)
	hud.add_feed("+%d원  %s" % [reward, {"normal": "흡연자 단속", "runner": "도망자 검거!", "angry": "다혈질 진압!", "boss": "골초왕 퇴치!!"}[npc.kind]], Color(1, 0.9, 0.4))
	Sfx.play("coin", -3.0, 1.0 + (combo - 1.0) * 0.15)
	if Game.has_truck:
		truck_charge = min(truck_charge + 1.0 / TRUCK_NEED, 1.0)
		hud.set_truck(truck_charge)
		if truck_charge >= 1.0:
			hud.add_feed("소방차 준비 완료! F", Color(1, 0.4, 0.3))
	if npc.kind == "boss":
		hud.banner("골초왕 퇴치!", "+%d원" % reward, 2.0)
		player.shake(0.6)
	if caught >= cfg.quota and not _quota_announced:
		_quota_announced = true
		hud.banner("목표 달성!", "남은 시간 동안 더 잡으면 보너스", 2.0)
		Sfx.play("fanfare")


func _on_annoyed(npc: Npc) -> void:
	if not playing:
		return
	complaints += 1
	earned -= 20
	hud.set_money(Game.money + earned)
	hud.set_complaints(complaints, MAX_COMPLAINTS)
	hud.add_feed("민원 접수 -20원", Color(1, 0.5, 0.4))
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
	var final_earned: int = earned if success else max(earned / 2, 0)
	Game.money = max(Game.money + final_earned, 0)
	var day_text := "%d일차 · %s" % [Game.day, cfg.title]
	if success:
		Game.day += 1
	Game.save_game()
	Game.last_result = {
		"success": success, "fail_reason": fail_reason, "day_text": day_text,
		"caught": caught, "quota": cfg.quota, "complaints": complaints,
		"best_combo": best_combo, "earned": final_earned,
	}
	hud.banner("근무 끝!" if success else fail_reason, "", 1.2)
	await get_tree().create_timer(1.4).timeout
	result.show_result()
