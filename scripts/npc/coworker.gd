class_name Coworker
extends StaticBody3D
## 파출소 동료와 동네 사람들(가게 주인 등). 가만히 서서 자기 일을 하다가, 플레이어가 오면 돌아보고 인사한다.
## E 로 말을 걸 수 있다. role 은 assets/people/<role>.glb 이름과 같다.

const DATA := {
	"chief": {"name": "소장님", "idle": "cross_arms", "greet": "salute", "lines": [
		"오늘도 동네 평화를 부탁하네!", "민원은 줄이고 실적은 올리고! 허허", "승진 심사 때 잘 봐주지.", "무전 오면 지체 말고 출동하게!"]},
	"ops": {"name": "상황실 요원", "idle": "talk", "greet": "wave", "lines": [
		"파란 빛기둥이 출동 현장이에요.", "상황실 업그레이드하면 출동 보상이 올라가요.", "지금도 신고 전화가 계속 와요...", "음주운전 차는 순찰차로 들이받아도 돼요."]},
	"mechanic": {"name": "정비 담당", "idle": "breathe", "greet": "wave", "lines": [
		"순찰차 기름 가득 넣어놨어!", "정비고 업그레이드하면 차가 확 빨라지지.", "소방차 키는 장비실에서 팔아. 물대포가 끝내줘!", "차 부수고 오지 마라잉."]},
	"rookie": {"name": "신입 순경", "idle": "idle", "greet": "salute", "lines": [
		"서, 선배님! 오늘도 화이팅입니다!", "도둑은 달리다 부딪히면 태클로 잡힌대요!", "저도 언젠가 소방호스 써보고 싶어요...", "학생들한텐 물 말고 사진이요! 저번에 혼났어요."]},
	"s_clerk": {"name": "편의점 알바", "idle": "idle", "greet": "wave", "town": true, "lines": [
		"어서오세요~ 생수 30원이요.", "가게 앞에서 담배 피우는 아저씨 좀 어떻게 해주세요...", "야간 알바 3년째예요. 별일 다 봤죠.", "에너지 음료 마시면 멘탈 회복돼요!"]},
	"s_doctor": {"name": "병원 원장님", "idle": "hands_back", "greet": "wave", "town": true, "lines": [
		"멘탈이 바닥이면 들어오세요. 100원이면 충분해요.", "물 맞은 환자가 또 왔네요...", "간접흡연이 얼마나 해로운지 아세요?", "무리하지 마세요, 경관님."]},
	"s_teacher": {"name": "학생부장 선생님", "idle": "cross_arms", "greet": "wave", "town": true, "lines": [
		"우리 학생들 담배 피우면 사진 찍어서 보내주세요.", "학생한테 물 뿌리면 안 됩니다! 사진이요, 사진.", "학교 폭력 보시면 바로 신고 부탁드려요.", "요즘 애들이 참..."]},
	"s_vendor": {"name": "분식집 사장님", "idle": "explain", "greet": "wave", "town": true, "lines": [
		"떡볶이 한 접시 하고 가요~", "우리 가게 앞 쓰레기 좀 치워줘서 고마워요!", "저기 노래방 시끄러워서 장사가 안 돼!", "순경 양반, 배고프면 들러요!"]},
	"f_mom": {"name": "포차 이모", "idle": "idle", "greet": "wave", "town": true, "lines": [
		"어서 와~ 오뎅 국물 서비스!", "근무 끝나고 와야지, 근무 중엔 안 팔아!", "오늘도 고생했어 우리 순경 양반.", "단골들 여기 다 모여~ 한 잔 하고 가."]},
	"s_shady": {"name": "업소 사장", "idle": "look_around", "greet": "wave_off", "town": true, "lines": [
		"아이고 경관님~ 우린 합법이에요 합법.", "못 본 걸로 해주시면 안 될까요? 허허", "음악 소리 좀 키운 것뿐인데...", "다음 주에 정식 허가 나와요, 진짜로!"]},
}

var role := "chief"
var human: Human
var _marker: MeshInstance3D
var _greeted := false
var _player: Node3D
var _bob := 0.0


func _ready() -> void:
	add_to_group("coworker")
	collision_layer = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	human = Human.make(role, 1.62 if role in ["rookie", "s_doctor", "s_vendor"] else 1.72)
	add_child(human)
	human.play(DATA[role].idle, 0.0)
	# 할 말이 있으면 머리 위에 작은 노란 표시 (글씨 없이)
	_marker = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.22, 0.22, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.831, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.831, 0)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	pm.material = mat
	_marker.mesh = pm
	_marker.rotation_degrees.z = 180.0
	_marker.position.y = 2.1
	add_child(_marker)
	_update_marker()


func has_topic() -> bool:
	if Talks.TOPIC_UNLOCK.has(role) and not Game.unlocked(Talks.TOPIC_UNLOCK[role]):
		return false
	return Talks.TOPICS.has(role) and not Game.flags.get("talk_" + role, false)


func _favor() -> String:
	## 동네 사람 부탁 상태 ("", "offer", "active", "done")
	var w := get_parent()
	return w.favor_status(role) if w and w.has_method("favor_status") else ""


func _update_marker() -> void:
	_marker.visible = has_topic() or _favor() == "offer"


func display_name() -> String:
	return DATA[role].name


func gesture(anim: String) -> void:
	## 대화 중 몸짓 (말하고 나면 원래 자세로)
	human.play(anim, 0.2)
	_later(2.4, func(): human.play(DATA[role].idle, 0.3))


func say(text: String, anim := "") -> void:
	## 머리 위 글씨 대신 몸짓만 (대사는 대화창으로)
	if anim != "":
		human.play(anim, 0.2)


func _process(delta: float) -> void:
	if _marker.visible:
		_bob += delta * 3.0
		_marker.position.y = 2.1 + sin(_bob) * 0.06
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		return
	var to := _player.global_position - global_position
	to.y = 0
	var near := to.length() < 5.0
	if near:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 4.0 * delta)
		if not _greeted:
			_greeted = true
			human.play(DATA[role].greet, 0.2)
			_later(2.0, func(): human.play(DATA[role].idle, 0.3))
	elif to.length() > 9.0:
		_greeted = false


func talk() -> void:
	## E: 처음엔 가르쳐 줄 이야기, 그다음부턴 한마디
	var world := get_tree().current_scene
	if world == null or not world.get("dialogue"):
		return
	var convo: Array
	var who: String = DATA[role].name
	if has_topic():
		Game.flags["talk_" + role] = true
		convo = Talks.TOPICS[role].duplicate()
	else:
		convo = [{"who": who, "text": DATA[role].lines.pick_random()}]
	match _favor():
		"offer":
			var f: Dictionary = Talks.FAVORS[role]
			convo.append({"who": who, "text": f.ask, "anim": "explain"})
			convo.append({"choices": [
				["맡겨 주세요!", [{"who": who, "text": f.yes, "anim": DATA[role].greet}, {"do": world.accept_favor.bind(role, self)}]],
				["오늘은 좀 바빠서요.", [{"who": who, "text": "그래요... 시간 나면 부탁해요."}]],
			]})
		"active":
			convo = [{"who": who, "text": "부탁한 거 %s 됐네요. 조금만 더 부탁해요!" % world.favor_progress(role)}]
	# 정비 담당: 순찰차 색 바꾸기
	if role == "mechanic" and not has_topic() and world.car_ok():
		var colors := [["경찰 하양", Color(0.95, 0.95, 0.97)], ["경찰 남색", Color(0.12, 0.2, 0.45)], ["형광 연두", Color(0.6, 0.95, 0.2)],
			["새빨강", Color(0.85, 0.1, 0.1)], ["무광 검정", Color(0.1, 0.1, 0.11)]]
		var picks := []
		for c in colors:
			picks.append([c[0], [{"do": world.buy_paint.bind(c[1])}, {"who": who, "text": "짜잔~ %s! 멋지지?" % c[0], "anim": "laugh"}]])
		picks.append(["그냥 둘게요.", []])
		convo.append({"who": who, "text": "순찰차 색 바꿔 줄까? 100원이면 돼.", "anim": "explain"})
		convo.append({"choices": picks})
	world.dialogue.start(convo, self)
	_update_marker()


func _later(t: float, fn: Callable) -> void:
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_callback(fn)
