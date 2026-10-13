class_name Shift
extends Node
## 하루 근무. 10시 출근 → 새벽 2시 퇴근. 할당량, 오늘 기록, 퇴근 성적표와 동네일보.

const START_HOUR := 10.0
const END_HOUR := 26.0          # 새벽 2시
const GRADE_PAY := {"S": 2.0, "A": 1.5, "B": 1.0, "C": 0.6}
## 아침 조회에서 소장님이 내리는 오늘의 특별 지시.
## 해당 단속은 보상 1.5배에 더 자주 생기고, 목표를 채우면 보너스.
const ORDER_MULT := 1.5
const ORDERS := [
	{"id": "smoke", "title": "흡연 집중 단속", "tasks": ["smoke"], "goal": 6, "boost": ["smoke"], "rank": 0,
		"line": "오늘은 흡연 집중 단속일세. 연기 피우는 사람 보이면 사정 봐주지 말게!"},
	{"id": "street", "title": "거리 질서 확립", "tasks": ["litter", "pee", "graffiti"], "goal": 4, "boost": ["litter", "pee", "graffiti"], "rank": 0,
		"line": "꽁초 투기에 노상방뇨 민원이 구청까지 들어갔네. 거리 질서 좀 잡아 주게."},
	{"id": "thief", "title": "소매치기 소탕", "tasks": ["thief"], "goal": 2, "boost": ["thief"], "rank": 0,
		"line": "소매치기가 기승이야. 가방 들고 뛰는 놈 보이면 달려가서 태클로 잡게!"},
	{"id": "camera", "title": "찰칵 단속의 날", "tasks": ["jaywalk", "parking", "teen_smoke", "teen_drink", "bully", "drunk"], "goal": 4, "boost": ["jaywalk", "parking", "teen_smoke"], "rank": 1,
		"line": "사진 단속 실적이 모자라다는군. 무단횡단, 불법주차, 학생 비행... 찰칵찰칵 찍어 오게."},
	{"id": "night", "title": "밤거리 안전", "tasks": ["fight", "pee", "graffiti", "teen_drink"], "goal": 4, "boost": ["fight", "graffiti"], "rank": 1,
		"line": "밤마다 싸움판이야. 해 지면 열 받은 사람들 물로 단단히 식혀 주게."},
]

var world: Node
var day: DayCycle
var quota := 10
var mission_quota := 2
var caught := 0
var by_task := {}
var missions_ok := 0
var missions_fail := 0
var complaints := 0
var earned := 0
var raid_today := -1            # 오늘 급습한 조직 번호
var clean_start: Array = []
var ended := false
var order := {}                 # 오늘의 지시 (ORDERS 중 하나)
var order_count := 0
var order_cleared := false
var _rain_tomorrow := false


func start(w: Node, d: DayCycle) -> void:
	world = w
	day = d
	var r := Game.rank()
	quota = 8 + r * 3
	mission_quota = 2 if r < 3 else 3
	# 온보딩: 첫날은 가볍게 (출동 없음), 출동은 처음 며칠 하나만
	if not Game.unlocked("missions"):
		quota = 3
		mission_quota = 0
	elif not Game.unlocked("events"):
		quota = 5
		mission_quota = 1
	clean_start = Game.clean.duplicate()
	day.hour = START_HOUR
	# 첫날은 맑게, 그 뒤로는 셋에 하나꼴로 비
	day.raining = Game.unlocked("rain") and Game.day > 1 and randf() < 0.35
	day.rain = 1.0 if day.raining else 0.0
	_rain_tomorrow = randf() < 0.35
	day.hour_passed.connect(_on_hour)
	order = _pick_order(r)


func _pick_order(r: int) -> Dictionary:
	## 특별 지시는 4일차부터 (테스트는 첫날 흡연 단속). 그 뒤로는 계급에 맞는 것 중 어제와 다른 것
	if not Game.unlocked("orders"):
		return {}
	if Game.day <= 1 or Game.day == Game.UNLOCK_DAY.orders:
		return ORDERS[0]
	var last: String = Game.flags.get("last_order", "")
	var ok := ORDERS.filter(func(o): return o.rank <= r and o.id != last)
	var o: Dictionary = ok.pick_random()
	Game.flags["last_order"] = o.id
	return o


func begin() -> void:
	day.running = true


func is_night() -> bool:
	return day.daylight() < 0.3


func is_order_task(task: String) -> bool:
	return not order.is_empty() and task in order.tasks


func record_catch(task: String, reward: int) -> void:
	if task != "trash":
		caught += 1
		by_task[task] = by_task.get(task, 0) + 1
	earned += reward
	if is_order_task(task) and not order_cleared:
		order_count += 1
		if order_count < order.goal:
			world.hud.add_feed(order_text(), Color(1, 0.831, 0))
		if order_count >= order.goal:
			order_cleared = true
			world.order_cleared(order)


func order_bonus() -> int:
	return 300 + Game.rank() * 150


func quota_text() -> String:
	if mission_quota == 0:
		return "단속 %d/%d" % [caught, quota]
	return "단속 %d/%d   출동 %d/%d" % [caught, quota, missions_ok, mission_quota]


func order_text() -> String:
	if order.is_empty():
		return ""
	return "지시 · %s  %s" % [order.title, "완료!" if order_cleared else "%d/%d" % [order_count, order.goal]]


func quota_done() -> bool:
	return caught >= quota and missions_ok >= mission_quota


func _on_hour(h: int) -> void:
	match h:
		18:
			world.hud.radio("해 졌어요. 밤엔 술집, 싸움, 노상방뇨 신고가 늘어요.")
		22:
			world.hud.radio("22시 넘었어요. 할당 못 채웠어도 파출소 들어와서 퇴근해도 돼요.")
		25:
			world.hud.radio("퇴근 한 시간 전이에요.")
		26:
			if ended:
				show_report()        # 비번으로 놀다가 새벽 2시 → 집으로
			else:
				end_shift()


func can_clock_out() -> bool:
	return quota_done() or day.hour >= 22.0


func grade() -> String:
	var score: float = minf(float(caught) / quota, 1.3) * 60.0 + missions_ok * 12.0 - missions_fail * 6.0 - complaints * 4.0
	if raid_today >= 0:
		score += 30.0
	if order_cleared:
		score += 10.0
	if score >= 95.0:
		return "S"
	if score >= 75.0:
		return "A"
	if score >= 50.0:
		return "B"
	return "C"


var report_data := {}


func show_report() -> void:
	## 비번 끝 (파출소 소파에서 하루 마치기, 또는 새벽 2시)
	day.running = false
	world.report.show_report(report_data)


func end_shift(show := true) -> void:
	## 근무 끝: 성적 매기고 저장. show=false 면 퇴근 후 비번으로 동네에서 놀다가 나중에 성적표
	if ended:
		return
	ended = true
	if show:
		day.running = false
	var g := grade()
	var pay := int((200 + Game.rank() * 150) * GRADE_PAY[g])
	Game.money += pay
	if Game.best_grade == "" or "SABC".find(g) < "SABC".find(Game.best_grade):
		Game.best_grade = g
	var r := {
		"day": Game.day, "grade": g, "pay": pay,
		"stats": "단속 %d / %d\n출동 성공 %d · 실패 %d\n%s\n민원 %d건 · 주민 평판 %d\n오늘 번 돈 ₩%d" % [caught, quota, missions_ok, missions_fail, order_text(), complaints, int(Game.reputation), earned],
		"districts": _district_text(),
		"weather": "비" if _rain_tomorrow else "맑음",
	}
	r.merge(_newspaper(g))
	# 퇴근 직전 화면을 신문 사진으로 (흑백 느낌으로 살짝 바래게)
	var img: Image = null
	if DisplayServer.get_name() != "headless":
		world.hud.visible = false
		await RenderingServer.frame_post_draw
		img = world.get_viewport().get_texture().get_image()
		world.hud.visible = true
	if img and not img.is_empty():
		img.resize(img.get_width() / 3, img.get_height() / 3)
		img.adjust_bcs(1.0, 1.1, 0.2)
		r.photo = ImageTexture.create_from_image(img)
	# 밤사이: 두목이 남은 구역은 조금 다시 더러워진다
	for i in Game.clean.size():
		if not Game.raided[i]:
			Game.add_clean(i, -4.0)
	Game.day += 1
	Game.save_game()
	report_data = r
	if show:
		world.report.show_report(r)


func _district_text() -> String:
	var lines: Array = []
	var zone: int = world.cfg.zone
	for i in zone + 1:
		var tag := " (두목 검거)" if Game.raided[i] else " · 단서 %d/%d" % [Game.clues[i], Game.CLUES_NEEDED]
		lines.append("%s 정화도 %d%% → %d%%%s" % [Game.ZONES[i].name.get_slice(" ", 0), int(clean_start[i]), int(Game.clean[i]), tag])
	return "\n".join(lines)


func _newspaper(g: String) -> Dictionary:
	var rank_name := Game.rank_name()
	var top := ""
	var top_n := 0
	for t in by_task:
		if by_task[t] > top_n:
			top = t
			top_n = by_task[t]
	var head := "조용한 하루... 물대포 파출소 \"이상 무\""
	var sub := "%s 한 명이 동네를 돌며 %d건을 단속했다." % [rank_name, caught]
	if raid_today >= 0:
		var gang: Dictionary = Game.GANGS[raid_today]
		head = "%s 두목 '%s' 전격 검거!" % [gang.name, gang.boss]
		sub = "물대포 파출소 %s, %s 급습해 일당을 일망타진. 주민들 \"이제 살 것 같다\"" % [rank_name, gang.place]
	elif g == "S":
		head = "'물벼락 순경' 하루 %d건 단속… 동네가 달라졌다" % caught
		sub = "주민들 사이에서 \"골목에 담배 연기가 사라졌다\"는 말이 나온다."
	elif complaints >= 3:
		head = "과잉 단속 논란… 하루 민원 %d건" % complaints
		sub = "\"애들한테까지 물을 뿌렸다\"는 목격담. 파출소는 \"재발 방지\" 약속."
	elif top != "":
		head = "%s %d건 적발… 단속 고삐 죈다" % [Game.TASKS[top].short, top_n]
		sub = "물대포 파출소 %s의 집중 단속에 상인들 반응은 엇갈렸다." % rank_name
	var briefs: Array = []
	if order_cleared:
		briefs.append("[파출소] 소장 특별 지시 '%s' 완수… 소장 \"역시 내가 사람 볼 줄 알지\"" % order.title)
	for i in mini(world.cfg.zone + 1, Game.GANGS.size()):
		if Game.raided[i]:
			continue
		var c: int = Game.clues[i]
		if c >= Game.CLUES_NEEDED:
			briefs.append("[제보] %s 아지트 위치 드러나… \"%s\" 앞 수상한 출입" % [Game.GANGS[i].name, Game.GANGS[i].place])
		elif c > 0:
			briefs.append("[사건] %s 꼬리 잡히나… 단서 %d개 확보" % [Game.GANGS[i].name, c])
	var d0: int = Game.district_of(world.player.global_position)
	if Game.clean[d0] >= 60:
		briefs.append("[동네] 문 닫았던 가게들 다시 문 열어… \"손님이 돌아왔다\"")
	elif Game.clean[d0] < 25:
		briefs.append("[동네] 골목마다 꽁초와 낙서… 주민들 \"밤에 다니기 무섭다\"")
	if _rain_tomorrow:
		briefs.append("[날씨] 내일 하루 종일 비. 젖은 길에 네온이 비친다")
	return {"headline": head, "sub": sub, "briefs": "\n".join(briefs) if not briefs.is_empty() else "[동네] 특별한 소식 없음"}
