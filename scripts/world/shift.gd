class_name Shift
extends Node
## 하루 근무. 10시 출근 → 새벽 2시 퇴근. 할당량, 오늘 기록, 퇴근 성적표와 동네일보.

const START_HOUR := 10.0
const END_HOUR := 26.0          # 새벽 2시
const GRADE_PAY := {"S": 2.0, "A": 1.5, "B": 1.0, "C": 0.6}

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
var _rain_tomorrow := false


func start(w: Node, d: DayCycle) -> void:
	world = w
	day = d
	var r := Game.rank()
	quota = 8 + r * 3
	mission_quota = 2 if r < 3 else 3
	clean_start = Game.clean.duplicate()
	day.hour = START_HOUR
	# 첫날은 맑게, 그 뒤로는 셋에 하나꼴로 비
	day.raining = Game.day > 1 and randf() < 0.35
	day.rain = 1.0 if day.raining else 0.0
	_rain_tomorrow = randf() < 0.35
	day.hour_passed.connect(_on_hour)


func begin() -> void:
	day.running = true


func is_night() -> bool:
	return day.daylight() < 0.3


func record_catch(task: String, reward: int) -> void:
	if task != "trash":
		caught += 1
		by_task[task] = by_task.get(task, 0) + 1
	earned += reward


func quota_text() -> String:
	return "오늘 할당  단속 %d/%d · 출동 %d/%d" % [caught, quota, missions_ok, mission_quota]


func quota_done() -> bool:
	return caught >= quota and missions_ok >= mission_quota


func _on_hour(h: int) -> void:
	match h:
		18:
			world.hud.banner("해가 집니다", "밤에는 술집, 싸움, 노상방뇨가 늘어나요", 2.5)
		22:
			world.hud.add_feed("심야 근무 시작. 유흥가를 살펴보세요", Color(0.75, 0.6, 1))
		25:
			world.hud.banner("퇴근 1시간 전!", "할당량: " + quota_text().trim_prefix("오늘 할당  "), 2.5)
		26:
			end_shift()


func can_clock_out() -> bool:
	return quota_done() or day.hour >= 22.0


func grade() -> String:
	var score: float = minf(float(caught) / quota, 1.3) * 60.0 + missions_ok * 12.0 - missions_fail * 6.0 - complaints * 4.0
	if raid_today >= 0:
		score += 30.0
	if score >= 95.0:
		return "S"
	if score >= 75.0:
		return "A"
	if score >= 50.0:
		return "B"
	return "C"


func end_shift() -> void:
	if ended:
		return
	ended = true
	day.running = false
	var g := grade()
	var pay := int((200 + Game.rank() * 150) * GRADE_PAY[g])
	Game.money += pay
	if Game.best_grade == "" or "SABC".find(g) < "SABC".find(Game.best_grade):
		Game.best_grade = g
	var r := {
		"day": Game.day, "grade": g, "pay": pay,
		"stats": "단속 %d / %d\n출동 성공 %d · 실패 %d\n민원 %d건\n오늘 번 돈 ₩%d" % [caught, quota, missions_ok, missions_fail, complaints, earned],
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
