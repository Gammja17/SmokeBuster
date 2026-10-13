class_name Buddy
extends CharacterBody3D
## 같이 순찰 도는 신입 순경. 선배(플레이어) 뒤를 따라다니며 근처 사건을 무전으로 알려 주고,
## 단속하면 좋아하고, 잘못 쏘면 비명을 지른다. 차를 타거나 건물에 들어가면 잠깐 안 보인다.
## 대화([E])로 같이 다닐지 먼저 들어가 있을지 고를 수 있다.

const FOLLOW := 3.2          # 이만큼 뒤에 선다 (말 걸기 거리 2.4 보다 멀리: 문/소화전 안내를 가리지 않게)
const WALK := 2.0
const RUN := 7.6
const SPOT_RANGE := 32.0
const SPOT := {
	"smoke": ["선배님! 담배 냄새 나요!", "킁킁... 저쪽에서 연기 냄새요!", "또 피워요, 또!"],
	"litter": ["방금 꽁초 버렸어요!", "쓰레기 막 버려요!"],
	"jaywalk": ["무단횡단이에요! 사진이요, 사진!", "저 할머니 또 무단횡단..."],
	"teen_smoke": ["학생이 담배를... 물 말고 사진이요!", "교복 입고 담배 펴요!"],
	"teen_drink": ["학생들이 술 마셔요! 사진 찍어야 돼요!"],
	"bully": ["학교폭력이에요! 빨리요!", "애 하나를 둘러쌌어요!"],
	"thief": ["도, 도둑이에요!! 가방 들고 뛰어요!", "소매치기! 태클이요 태클!"],
	"fight": ["싸움 났어요! 물로 식혀 주세요!", "저 사람들 주먹 오가요!"],
	"graffiti": ["벽에 낙서해요!", "스프레이 든 사람이요!"],
	"pee": ["으... 저 아저씨 벽에다...", "노상방뇨예요! 으웩!"],
	"parking": ["횡단보도에 차 세웠어요!", "불법주차요! 찰칵!"],
	"shop": ["불법업소 간판이에요! 물로 합선시켜요!"],
	"drunk": ["저 차 비틀거려요! 음주운전 같아요!"],
}
const CHEER := ["역시 선배님!", "와... 저도 저렇게 할래요!", "깔끔합니다!", "실적 하나 추가요!", "선배님 멋져요!"]
const WET := ["으악! 선배님 저예요 저!!", "차, 차가워요!!", "제복 다 젖었어요...", "저 단속 대상 아니에요!!"]
const CHAT := ["선배님, 저 오늘 소장님한테 칭찬받았어요!", "순찰차 운전 저도 해 보고 싶어요...", "어제 꿈에 골초왕 나왔어요. 무서웠어요.",
	"분식집 떡볶이 진짜 맛있대요. 이따 가요!", "물대포 파출소 들어오길 진짜 잘한 것 같아요!"]

var world: Node
var player: Node3D
var human: Human
var role := "rookie"         # 동료 목록에서 신입으로 친다
var active := false
var sent_home := false       # 오늘은 먼저 들어가라고 했음
var soaked_today := 0

var _spot_t := 8.0
var _cheer_cd := 0.0
var _wet_cd := 0.0
var _gesture_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _hidden := false
var _pointed := {}           # 이미 알려 준 사건 (같은 걸 또 말하지 않게)


func _ready() -> void:
	add_to_group("soakable")
	# 레이어 8: 물줄기는 맞지만 플레이어(1|2)와는 부딪히지 않는다
	collision_layer = 8
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.62
	shape.shape = cap
	shape.position.y = 0.81
	add_child(shape)
	human = Human.make("rookie", 1.62)
	add_child(human)
	_act("idle", 0.0)
	_set_hidden(true)


func join() -> void:
	## 파출소 문을 나서면 따라나온다
	if active or sent_home:
		return
	active = true
	add_to_group("coworker")
	_teleport_behind()
	_set_hidden(false)
	_act("salute", 0.2)
	_gesture_t = 1.6
	world.hud.radio(["선배님! 오늘도 따라다니면서 배우겠습니다!", "저도 같이 가요! 사건 보이면 바로 말씀드릴게요!"].pick_random(), "신입 순경", true)
	_set_station_rookie(false)


func dismiss() -> void:
	## 먼저 파출소로 들어간다 (파출소 안 원래 자리에 다시 선다)
	active = false
	remove_from_group("coworker")
	_set_hidden(true)
	_set_station_rookie(true)


func _go_home() -> void:
	sent_home = true
	dismiss()


func _set_station_rookie(on: bool) -> void:
	## 따라다니는 동안 파출소 안 신입 자리는 비운다
	for c in get_tree().get_nodes_in_group("coworker_rookie"):
		c.visible = on
		if on:
			c.add_to_group("coworker")
		else:
			c.remove_from_group("coworker")


func _set_hidden(h: bool) -> void:
	_hidden = h
	visible = not h
	collision_layer = 0 if h else 8


func _teleport_behind() -> void:
	var back: Vector3 = player.global_basis.z
	back.y = 0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	global_position = player.global_position + back * FOLLOW + player.global_basis.x * 0.8
	global_position.y = maxf(player.global_position.y - 0.2, 0.05)
	velocity = Vector3.ZERO
	_last_pos = global_position
	_stuck_t = 0.0


# ---------------------------------------------------------------- 말 걸기 (동료와 같은 방식)

func display_name() -> String:
	return "신입 순경"


func gesture(anim: String) -> void:
	_act(anim, 0.2)
	_gesture_t = 2.4


func talk() -> void:
	var convo: Array
	if Talks.TOPICS.has("rookie") and not Game.flags.get("talk_rookie", false):
		Game.flags["talk_rookie"] = true
		convo = Talks.TOPICS.rookie.duplicate()
	else:
		convo = [{"who": "신입 순경", "text": CHAT.pick_random()}]
	convo.append({"choices": [
		["계속 같이 가자.", [{"who": "신입 순경", "text": "넵! 꼭 붙어 다니겠습니다!", "anim": "salute"}]],
		["먼저 파출소 들어가 있어.", [{"who": "신입 순경", "text": "아... 알겠습니다. 파출소에서 기다릴게요!", "anim": "wave"}, {"do": _go_home}]],
	]})
	world.dialogue.start(convo, self)


# ---------------------------------------------------------------- 반응

func soak(_amount: float, _dir: Vector3, _knock: float) -> void:
	if not active or _hidden or _wet_cd > 0.0:
		return
	_wet_cd = 4.0
	soaked_today += 1
	_act("soaked" if soaked_today % 2 == 1 else "surprise", 0.1)
	_gesture_t = 1.8
	Sfx.play_at("voice_adult", global_position + Vector3.UP * 1.5, 0.0, 1.25)
	var line: String = WET.pick_random()
	if soaked_today == 3:
		line = "선배님... 저 오늘만 세 번째예요..."
	world.hud.radio(line, "신입 순경", true)


func wants_water() -> bool:
	return false


func on_catch(_task: String, pos: Vector3) -> void:
	## 선배가 단속에 성공하면 박수
	if not active or _hidden or global_position.distance_to(pos) > 22.0:
		return
	_face(pos)
	_act("cheer", 0.15)
	_gesture_t = 1.6
	if _cheer_cd <= 0.0 and randf() < 0.35 and not world.hud.radio_busy():
		_cheer_cd = 25.0
		world.hud.radio(CHEER.pick_random(), "신입 순경", true)


# ---------------------------------------------------------------- 따라다니기

func _physics_process(delta: float) -> void:
	_cheer_cd -= delta
	_wet_cd -= delta
	_gesture_t -= delta
	if not active:
		return
	# 차를 타거나 건물에 들어가면 같이 타고/밖에서 기다린다 (안 보임). 돌아오면 바로 옆에.
	var away: bool = world.vehicle != null or world.inside != "" or not world.playing
	if away != _hidden:
		_set_hidden(away)
		if not away:
			_teleport_behind()
	if _hidden:
		return
	var to: Vector3 = player.global_position - global_position
	to.y = 0
	var dist := to.length()
	if dist > 26.0 or absf(player.global_position.y - global_position.y) > 3.0:
		_teleport_behind()
		return
	var move := Vector3.ZERO
	if dist > FOLLOW + 0.6:
		var spd := RUN if dist > 8.0 else WALK + (dist - FOLLOW) * 0.9
		move = to.normalized() * minf(spd, RUN)
	# 막혀서 못 따라오면 순간이동
	if dist > FOLLOW + 2.0:
		_stuck_t += delta
		if _stuck_t > 1.2:
			if global_position.distance_to(_last_pos) < 0.8:
				_teleport_behind()
				return
			_stuck_t = 0.0
			_last_pos = global_position
	else:
		_stuck_t = 0.0
		_last_pos = global_position
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if _gesture_t <= 0.0:
		var hs := move.length()
		var an := "sprint" if hs > 4.0 else ("walk" if hs > 0.3 else "idle")
		human.play(an, 0.25)
		human.anim.speed_scale = Human.stride_rate(an, hs, 1.62)
		if hs > 0.3:
			_face(global_position + move)
		elif dist > 0.5:
			_face(player.global_position)
	_spot_t -= delta
	if _spot_t <= 0.0:
		_spot_t = randf_range(14.0, 22.0)
		_spot()


func _act(anim_name: String, blend := 0.2) -> void:
	## 몸짓은 원래 빠르기로
	human.anim.speed_scale = 1.0
	human.play(anim_name, blend)


func _face(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 0.25)


func _spot() -> void:
	## 선배가 아직 못 본 것 같은 근처 사건을 무전으로 알려 준다 (방향과 거리까지)
	if world.hud.radio_busy():
		_spot_t = 2.0
		return
	if world.mission.size() > 0 and randf() < 0.5:
		return
	var best: Node3D = null
	var bd := SPOT_RANGE
	for n in get_tree().get_nodes_in_group("incident"):
		if not is_instance_valid(n) or _pointed.has(n.get_instance_id()):
			continue
		if n.has_method("is_active_incident") and not n.is_active_incident():
			continue
		if n.get("done") == true:
			continue
		var d: float = n.global_position.distance_to(player.global_position)
		# 담배는 신입도 냄새로만 안다
		if n is Npc and n.has_cigarette() and d > 18.0:
			continue
		if d > 9.0 and d < bd:
			bd = d
			best = n
	if best == null:
		return
	_pointed[best.get_instance_id()] = true
	var task: String = best.task() if best.has_method("task") else ""
	if not SPOT.has(task):
		return
	_face(best.global_position)
	_act("explain", 0.15)
	_gesture_t = 2.0
	world.hud.radio("%s  (%s %dm)" % [SPOT[task].pick_random(), _side(best.global_position), int(bd)], "신입 순경", true)


func _side(p: Vector3) -> String:
	## 선배가 보는 방향 기준으로 앞/뒤/왼쪽/오른쪽
	var fwd: Vector3 = -player.global_basis.z
	fwd.y = 0
	var to := p - player.global_position
	to.y = 0
	var a := rad_to_deg(fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP))
	if absf(a) < 45.0:
		return "앞"
	if absf(a) > 135.0:
		return "뒤"
	return "왼쪽" if a > 0.0 else "오른쪽"
