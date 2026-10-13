class_name TownLife
extends Node
## 동네가 살아 있게: 시간대별 풍경과 이름 있는 단골.
## - 점심엔 카페 앞에 커피 든 사람들, 퇴근길엔 인파, 밤엔 취객. 낮 출근 시간엔 회사원이 바쁘게.
## - 단골은 나를 기억한다 (Game.regulars 친밀도). 친해지면 사건 제보, 더 친해지면 선물.
##   눈앞에서 단속하면 좋아하고, 물을 맞히면 실망한다.

const REGULARS := [
	{"id": "park", "name": "박 할머니", "model": "f_grandma", "spot": "bench",
		"hello": "처음 보는 순경 양반이네? 나 이 동네 산 지 삼십 년이야. 잘 부탁해요.",
		"lines": ["오늘도 고생 많아요~", "요새 공원이 좀 깨끗해졌어.", "밥은 먹고 다녀요?"]},
	{"id": "kim", "name": "김 대리", "model": "m_office", "spot": "busstop",
		"hello": "아 경찰분이시구나. 저 맨날 이 정류장에서 버스 기다려요. 담배 연기 때문에 죽겠어요.",
		"lines": ["오늘도 야근각이에요...", "정류장 앞 흡연자 좀 어떻게 안 될까요?", "수고하십니다!"]},
	{"id": "choi", "name": "최 기사", "model": "m_delivery", "spot": "street",
		"hello": "배달하다 보면 동네 구석구석 다 봐요. 수상한 거 보면 알려 드릴게요!",
		"lines": ["오늘 콜 많네요~", "골목길에 별의별 사람 다 있어요.", "순경님 화이팅!"]},
	{"id": "lee", "name": "이 학생", "model": "m_college", "spot": "cafe",
		"hello": "앗 경찰이다... 아 저 착한 학생이에요! 카페에서 과제하는 중이에요.",
		"lines": ["과제 마감이 내일이라...", "이 카페 아아 맛집이에요.", "저번에 물대포 쏘는 거 봤어요 ㅋㅋ"]},
	{"id": "jung", "name": "정 아주머니", "model": "f_ajumma", "spot": "corner",
		"hello": "어머 새로 온 순경이구나! 이 골목 소문은 다 나한테 들어와~",
		"lines": ["저 집 아들이 글쎄...", "요즘 동네가 좀 살 만해졌어!", "순경 양반 결혼은 했어?"]},
]
const TIP_AT := 25        # 이만큼 친하면 사건 제보
const GIFT_AT := 60       # 이만큼 친하면 하루 한 번 선물

var world: Node
var regulars := {}        # id -> Npc (오늘 나와 있는 단골)
var _t := 0.0
var _greeted := {}        # 오늘 지나가며 인사한 단골


func setup(w: Node) -> void:
	world = w
	for r in REGULARS:
		_spawn_regular(r)


# ---------------------------------------------------------------- 시간대 풍경

func crowd_mult() -> float:
	## 시간대별 행인 수 배율
	var h: float = world.day.hour
	if h >= 12.0 and h < 14.0:
		return 1.4      # 점심
	if h >= 18.0 and h < 20.5:
		return 1.6      # 퇴근길
	if h >= 23.0:
		return 0.55     # 한밤
	if h >= 21.0:
		return 0.85
	return 1.0


func pick_ped_model() -> String:
	## 시간대에 어울리는 행인 (빈 문자열이면 아무나)
	var h: float = world.day.hour
	if h >= 22.0 and randf() < 0.3:
		return "m_drunk"
	if (h < 11.5 or (h >= 18.0 and h < 20.5)) and randf() < 0.5:
		return ["m_office", "f_office"].pick_random()
	return ""


func _process(delta: float) -> void:
	if world == null or not world.playing or world.inside != "":
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var h: float = world.day.hour
	if h >= 12.0 and h < 14.0:
		_lunch()
	_greet_passing()
	_ensure_regulars()


func _ensure_regulars() -> void:
	## 단골은 언제나 동네 어딘가에 (사라졌으면 다시 나온다)
	for r in REGULARS:
		if not is_instance_valid(regulars.get(r.id)):
			_spawn_regular(r)


func _lunch() -> void:
	## 점심시간: 카페 앞에 커피 들고 서 있는 사람들
	var sitting := 0
	for n in world.npcs.get_children():
		if n is Npc and n.get_meta("lunch", false) and not n.done:
			sitting += 1
	if sitting >= 4 or randf() > 0.4:
		return
	var free: Array = world.city.spots.filter(func(s): return s.kind == "cafe" and not s.busy \
			and s.pos.distance_to(world.player.global_position) < 45.0 and s.pos.distance_to(world.player.global_position) > 8.0)
	if free.is_empty():
		return
	var sp: Dictionary = free.pick_random()
	var n: Npc = world._new_npc("ped")
	n.position = sp.pos + Vector3(randf_range(-0.6, 0.6), 0.05, randf_range(-0.6, 0.6))
	n.set_meta("lunch", true)
	world.npcs.add_child(n)
	n.start_walking(world.city.nearest_nav(n.position))
	n.start_pause(randf_range(25.0, 45.0), "drink", null)


# ---------------------------------------------------------------- 단골

func _spawn_regular(r: Dictionary) -> void:
	# 눈앞에서 뿅 나타나지 않게 멀리 있는 자리부터
	var pp: Vector3 = world.player.global_position
	var options: Array = world.city.spots.filter(func(s): return s.kind == r.spot and not s.busy and s.pos.distance_to(pp) > 25.0)
	if options.is_empty():
		options = world.city.spots.filter(func(s): return s.kind == r.spot and not s.busy)
	if options.is_empty():
		options = world.city.spots.filter(func(s): return not s.busy)
	if options.is_empty():
		return
	var sp: Dictionary = options.pick_random()
	var n: Npc = world._new_npc("ped")
	n.force_model = r.model
	n.regular = r.id
	n.position = sp.pos + Vector3(0, 0.05, 0)
	world.npcs.add_child(n)
	n.start_walking(world.city.nearest_nav(n.position))
	n.start_pause(randf_range(20.0, 60.0), "idle", null)
	regulars[r.id] = n


static func info(id: String) -> Dictionary:
	for r in REGULARS:
		if r.id == id:
			return r
	return {}


func affinity(id: String) -> int:
	return int(Game.regulars.get(id, 0))


func add_affinity(id: String, amount: int, why := "") -> void:
	var before := affinity(id)
	Game.regulars[id] = clampi(before + amount, 0, 100)
	if why != "":
		world.hud.add_feed("%s %s" % [info(id).name, why], Color(1, 0.75, 0.8) if amount > 0 else Color(0.7, 0.7, 0.75))
	if before < TIP_AT and affinity(id) >= TIP_AT:
		world.hud.add_feed("%s 와(과) 친해졌다! 이제 동네 소식을 알려 준다" % info(id).name, Color(1, 0.75, 0.8))


func hearts(id: String) -> String:
	var a := affinity(id)
	return "♥".repeat(int(a / 20.0)) + "♡".repeat(5 - int(a / 20.0))


func _greet_passing() -> void:
	## 지나가면 먼저 아는 척 (친한 단골만, 하루 한 번)
	for id in regulars:
		var n = regulars[id]
		if not is_instance_valid(n) or _greeted.has(id) or affinity(id) < 10:
			continue
		if n.global_position.distance_to(world.player.global_position) < 5.0:
			_greeted[id] = true
			world.hud.add_feed("%s: %s" % [info(id).name, info(id).lines.pick_random()], Color(1, 0.85, 0.9))
			n._play("emote-yes", 0.2)


func on_catch(pos: Vector3) -> void:
	## 단골 눈앞에서 단속하면 좋아한다
	for id in regulars:
		var n = regulars[id]
		if is_instance_valid(n) and n.global_position.distance_to(pos) < 18.0 and n.state == Npc.State.WALK:
			add_affinity(id, 3, "\"잘한다~\" ♥")
			n._play("emote-yes", 0.2)


func on_soaked(n: Npc) -> void:
	## 단골한테 물을 맞히면 실망
	if n.regular != "":
		add_affinity(n.regular, -8, "실망... ♡")


func talk(n: Npc) -> void:
	## E 로 단골과 이야기: 처음엔 인사, 친해지면 제보, 더 친해지면 선물
	var r := info(n.regular)
	var who: String = r.name
	var convo: Array = []
	var key := "regular_%s_%d" % [n.regular, Game.day]
	if not Game.flags.get("met_" + n.regular, false):
		Game.flags["met_" + n.regular] = true
		convo.append({"who": who, "text": r.hello})
		add_affinity(n.regular, 8)
	else:
		convo.append({"who": who, "text": r.lines.pick_random()})
		if not Game.flags.get(key, false):
			add_affinity(n.regular, 3)
	var a := affinity(n.regular)
	if a >= TIP_AT and not Game.flags.get(key, false):
		var tip := _tip(n.global_position)
		if tip:
			var label: String = Game.TASKS[tip.task()].short if tip.has_method("task") and Game.TASKS.has(tip.task()) else "수상한 일"
			convo.append({"who": who, "text": "아 참, 저기 %s 쪽에서 %s 봤어요. 가 봐요!" % [world._place_name(tip.global_position), label], "anim": "explain"})
			world.mark_seen(tip, false)
	if a >= GIFT_AT and not Game.flags.get(key + "_gift", false):
		Game.flags[key + "_gift"] = true
		convo.append({"who": who, "text": "이거 받아요. 고생하는데 뭐라도 먹어야지! (멘탈 회복, ₩50)", "anim": "laugh"})
		convo.append({"do": func():
			Game.money += 50
			world.hud.set_money(Game.money)
			world.player.mental = Game.max_mental()
			world.hud.set_mental(world.player.mental, Game.max_mental())})
	Game.flags[key] = true
	convo.append({"who": who, "text": "(친밀도 %s)" % hearts(n.regular)})
	world.dialogue.start(convo, n)


func _tip(from: Vector3) -> Node3D:
	## 아직 모르는 근처 사건 하나
	var best: Node3D = null
	var bd := 70.0
	for t in get_tree().get_nodes_in_group("incident"):
		if t.has_meta("seen") or not t.has_method("is_active_incident") or not t.is_active_incident():
			continue
		var d: float = t.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = t
	return best
