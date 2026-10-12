class_name Npc
extends CharacterBody3D
## 동네 사람. kind 에 따라 하는 짓이 다르다.
##   ped(행인), normal/runner/angry/boss(성인 흡연자: 물), litter(무단투기: 물),
##   jaywalker(무단횡단: 도로 위에서 촬영), teen_smoker/teen_drinker(미성년: 촬영),
##   bully/victim(학교폭력 현장: 촬영), thief(소매치기: 물/태클/차로 잡고 가방 돌려주기),
##   fighter(길거리 싸움: 물), tagger(낙서범: 물), pee(노상방뇨: 물)
## 미성년자와 행인에게 물을 뿌리면 민원이 들어온다.

signal resolved(npc: Npc, task: String)
signal annoyed(npc: Npc, minor: bool)
signal hurt_player(npc: Npc, amount: int)
signal dropped_trash(pos: Vector3)
signal dropped_bag(pos: Vector3, owner_npc: Node)
signal shout(npc: Npc, text: String)

enum State { WALK, SMOKING, FLEE, CHARGE, LEAVING, STAGGER, CROSSING, HANGOUT, DOWN }

## 역할마다 어울리는 VARCO 실사 인물 (assets/people/<이름>.glb)
const POOLS := {
	"ped": ["m_office", "f_office", "m_hiker", "f_ajumma", "m_grandpa", "f_grandma", "m_college", "f_college",
			"m_delivery", "f_trench", "m_worker", "f_mom", "m_gamer", "m_jogger"],
	"normal": ["m_office", "m_hiker", "m_worker", "m_delivery", "m_gamer", "f_trench", "f_office", "m_college", "m_grandpa"],
	"runner": ["m_jogger", "m_college", "m_delivery"],
	"angry": ["m_thug", "m_hiker", "f_ajumma", "m_track"],
	"boss": ["m_boss"],
	"litter": ["m_office", "m_gamer", "m_worker", "m_hiker", "f_college"],
	"jaywalker": ["f_grandma", "m_grandpa", "m_delivery", "f_ajumma", "f_mom"],
	"teen_smoker": ["t_badboy", "t_badgirl"],
	"teen_drinker": ["t_badboy", "t_badgirl"],
	"bully": ["t_badboy", "t_badgirl"],
	"victim": ["t_nerd", "t_boy", "t_girl"],
	"thief": ["m_thief"],
	"fighter": ["m_thug", "m_track", "m_drunk"],
	"tagger": ["m_tagger"],
	"pee": ["m_drunk", "m_office"],
}
const FEMALE := ["f_office", "f_ajumma", "f_grandma", "f_college", "f_trench", "f_mom", "t_girl", "t_badgirl"]
const OLD := ["m_grandpa", "f_grandma"]
## 예전 이름 -> 공용 애니메이션 이름
const ANIM_MAP := {"emote-no": "wave_off", "emote-yes": "laugh", "attack-melee-right": "punch", "attack-kick-right": "kick",
	"holding-both": "shield", "die": "fall", "pick-up": "getup", "interact-right": "drink"}
const ADULT_SMOKERS := ["normal", "runner", "angry", "boss"]
const MINORS := ["teen_smoker", "teen_drinker", "bully", "victim"]
const LINES := {
	"done": ["앗 차가워!", "죄송합니다...", "에이 씨...", "알겠다고요!", "끄라면 끄지!", "으악 내 담배!", "아 축축해..."],
	"ped": ["뭐야?!", "저 아무것도 안 했어요!", "민원 넣는다!", "아 왜 나한테!", "옷 젖었잖아요!"],
	"minor": ["애한테 물을 뿌려요?!", "엄마한테 이를 거야!", "아동학대다!"],
	"runner": ["단속이다!", "튀어!", "못 잡지롱~"],
	"angry": ["너 뭐야!", "이게 미쳤나!", "한판 붙자!", "감히 나한테!"],
	"boss": ["후우우우...", "내가 이 동네 골초왕이다!", "물 따위로 날 끌 수 있을까?"],
	"litter_done": ["주, 주울게요!", "잘못했어요...", "쓰레기통이 없어서..."],
	"jaywalk": ["찰칵? 설마...", "아 급해서요!", "벌금 나오나요?"],
	"teen_caught": ["헉 사진 찍혔다!", "선생님한테 가요?!", "아 망했다..."],
	"bully_caught": ["야 튀어!", "찍혔다!", "학교에 알려진다!"],
	"victim": ["감사합니다!", "살았다...", "고맙습니다 아저씨!"],
	"victim_help": ["도와주세요!", "그만해...", "아파..."],
	"wet1": ["앗 차가!", "뭐, 뭐야?!", "비 와?"],
	"wet2": ["으아 차가워!!", "그만 쏴!!", "옷 다 젖잖아!"],
	"wet3": ["살려줘어!!", "알았어 알았다고!!", "으아아아!!"],
	"thief": ["못 잡지롱~", "비켜비켜!", "헉헉..."],
	"thief_done": ["잘못했어요!!", "가방 돌려드릴게요...", "으악 잡혔다!"],
	"robbed": ["도둑이야!!", "내 가방!!", "저 사람 잡아요!!"],
	"fight": ["이 자식이!", "너 몇 살이야!", "한 대 맞아볼래?", "덤벼!"],
	"fight_done": ["진정할게요...", "형이 참는다", "추워..."],
	"tagger_done": ["예술을 모르시네!", "으악 내 스프레이!", "튀어!"],
	"pee": ["♪~", "후아~", "급해서..."],
	"pee_done": ["으악 바지!!", "다 젖었잖아!", "죄송합니다!!"],
	"hit_by_car": ["으악!", "운전 똑바로 해요!!", "사람 쳤어!!"],
}
const SPLAT := ["철퍽!", "촥!", "쏴아!", "푸확!", "첨벙!"]
## 머리 위 글씨는 없다. 연기, 쓰레기 버리기, 스프레이, 가방 들고 뛰기 같은 행동으로 알아본다.
## (골초왕만 이름표)
const LABELS := {"boss": "골초왕"}

var kind := "ped"
var city: CityBuilder
var player: Node3D
var state := State.WALK
var group_id := 0           # 같은 무리 (음주 미자, 학폭)
var victim: Npc             # 학폭 가해자가 노리는 대상
var partner: Npc            # 싸움 상대
var graffiti: Label3D       # 낙서범이 그리는 낙서
var stolen_from: Node       # 도둑이 가방을 뺏은 사람

var need := 1.0
var wet := 0.0
var walk_speed := 1.6
var run_speed := 5.2
var done := false

var _model: Human
var _anim: AnimationPlayer
var model_name := ""
var force_model := ""     # 정해진 인물로 (조직 두목 등)
var title := ""           # 머리 위 이름 (두목)
var interior := false     # 건물 안에 있는 사람 (길 그래프를 쓰지 않는다)
var _walk_anim := "walk"
var _cur_anim := ""
var _busy_t := 0.0
var _hand: Node3D
var _overlay: StandardMaterial3D
var _meshes: Array = []
var _overlay_on := false
var _cig: Node3D
var _smoke: CPUParticles3D
var _puff: CPUParticles3D
var _label: Label3D
var _say: Label3D
var _bar_bg: MeshInstance3D
var _bar_fill: MeshInstance3D
var _bar_mesh: QuadMesh

var _target := Vector3.ZERO
var _from_node := -1
var _to_node := -1
var _timer := 0.0
var _last_hit := 0.0
var _annoy_cd := 0.0
var _kick_cd := 0.0
var _litter_t := 0.0
var _knock := Vector3.ZERO
var _flee_dir := Vector3.ZERO
var _cross_to := Vector3.ZERO
var _spot: Dictionary = {}
var _puff_t := 0.0
var _scale := 0.65

# 맞을 때 반응
var _voice_cd := 0.0
var _voice_pitch := 1.0
var _squash_cd := 0.0
var _splat_cd := 0.0
var _shield_t := 0.0
var _line_stage := 0
var _down_t := 0.0
var _down_cd := 0.0
var _slip_cd := 0.0
var _prev_state := State.WALK
var _leave_after_down := false
var _drip: CPUParticles3D
var _water: Node


func setup(p_kind: String, p_city: CityBuilder, p_player: Node3D) -> void:
	kind = p_kind
	city = p_city
	player = p_player


func _ready() -> void:
	add_to_group("npc")
	add_to_group("soakable")
	collision_layer = 2
	collision_mask = 1
	match kind:
		"boss":
			need = 14.0
			walk_speed = 1.3
			run_speed = 2.6
		"angry":
			need = 1.6
		"runner":
			run_speed = 5.6
		"litter":
			need = 0.8
			_litter_t = randf_range(3.0, 6.0)
		"jaywalker":
			walk_speed = 1.25
		"thief":
			need = 1.3
			run_speed = 6.3
			_snatch_t = randf_range(4.0, 9.0)
		"fighter", "tagger":
			need = 0.9
		"pee":
			need = 0.6
	if is_minor():
		walk_speed = 1.9

	model_name = force_model if force_model != "" else (POOLS.get(kind, POOLS.ped) as Array).pick_random()
	var height := randf_range(1.66, 1.84)
	if model_name in FEMALE:
		height = randf_range(1.58, 1.70)
	if model_name in OLD:
		height = randf_range(1.55, 1.64)
		_walk_anim = "walk_old"
	elif model_name in FEMALE:
		_walk_anim = "walk_f"
	elif model_name == "m_drunk":
		_walk_anim = "stumble"
	if is_minor():
		height = randf_range(1.55, 1.68)
	if kind == "boss":
		height = 2.2
	_scale = height / 1.75 * 0.65

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 * _scale / 0.65
	cap.height = 1.75 * _scale / 0.65
	col.shape = cap
	col.position.y = cap.height / 2
	add_child(col)

	_model = Human.make(model_name, height)
	add_child(_model)
	_anim = _model.anim
	_anim.speed_scale = randf_range(0.9, 1.1)

	_overlay = StandardMaterial3D.new()
	_overlay.albedo_color = Color(0.3, 0.55, 1.0, 0.0)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_meshes = _model.find_children("*", "MeshInstance3D", true, false)
	for m in _meshes:
		# 멀리 있는 사람은 그리지 않는다
		m.visibility_range_end = 75.0

	_voice_pitch = randf_range(0.85, 1.2) * (0.75 if kind == "boss" else 1.0)
	_build_drip()

	_say = _make_label(Color.WHITE, 40)
	_say.position.y = _head_y() + 0.45
	_say.visible = false

	if is_minor():
		_add_backpack()
	if kind in ADULT_SMOKERS or kind == "teen_smoker":
		_build_cigarette()
	if kind in ADULT_SMOKERS:
		add_to_group("smoker")
	if kind == "teen_drinker":
		_build_bottle()
	if kind in ADULT_SMOKERS or kind in ["litter", "thief", "fighter", "tagger", "pee"]:
		_build_bar()
	if kind == "tagger":
		_build_spray_can()
	if task() != "":
		add_to_group("incident")
	# 머리 위 이름표는 달지 않는다 (두목은 덩치와 연기로 알아본다)
	match kind:
		"normal", "runner", "angry", "boss", "teen_smoker":
			_set_state(State.SMOKING)
		"teen_drinker", "bully", "victim", "fighter", "tagger", "pee":
			_set_state(State.HANGOUT)
		_:
			_set_state(State.WALK)


func _head_y() -> float:
	return 1.95 * _scale / 0.65


# ---------------------------------------------------------------- 분류

func is_minor() -> bool:
	return kind in MINORS


func is_smoker_kind() -> bool:
	return kind in ADULT_SMOKERS


func is_smoking() -> bool:
	return kind in ADULT_SMOKERS and not done and state in [State.SMOKING, State.FLEE, State.CHARGE, State.STAGGER]


## 이 사람이 걸린 업무 (없으면 "")
func task() -> String:
	match kind:
		"normal", "runner", "angry", "boss": return "smoke"
		"litter": return "litter"
		"jaywalker": return "jaywalk"
		"teen_smoker": return "teen_smoke"
		"teen_drinker": return "teen_drink"
		"bully", "victim": return "bully"
		"thief": return "thief"
		"fighter": return "fight"
		"tagger": return "graffiti"
		"pee": return "pee"
	return ""


func is_active_incident() -> bool:
	if done or task() == "":
		return false
	if kind == "jaywalker":
		return state == State.CROSSING and city.is_on_road(global_position)
	if kind == "thief":
		return _stolen
	return true


func incident_pos() -> Vector3:
	return global_position + Vector3.UP * _head_y() * 0.7


## 카메라로 찍으면 해결되는 업무 (지금 찍을 수 없으면 "")
func photo_task() -> String:
	if not is_active_incident():
		return ""
	return task() if Game.TASKS[task()].how == "photo" else ""


func wants_water() -> bool:
	return is_active_incident() and Game.TASKS[task()].how in ["water", "chase"]


## 차로 들이받거나 태클로 잡을 수 있는 사람 (어른 문제아만)
func can_be_caught() -> bool:
	return wants_water() and not is_minor()


## 걷는 행인이 그 자리에서 담배를 꺼내 문다.
func light_up(new_kind: String) -> void:
	kind = new_kind
	if kind == "angry":
		need = 1.6
	_build_cigarette()
	_build_bar()
	add_to_group("smoker")
	add_to_group("incident")
	_set_state(State.SMOKING)


func start_walking(from_node: int) -> void:
	_from_node = from_node
	_to_node = -1
	_pick_next_node()


## 무단횡단: 지금 자리에서 cross_to 까지 도로를 가로지른다.
func start_crossing(cross_to: Vector3) -> void:
	_cross_to = cross_to
	_set_state(State.CROSSING)


func occupy(spot: Dictionary) -> void:
	_spot = spot
	spot.busy = true


# ---------------------------------------------------------------- 물 맞기

func soak(amount: float, dir: Vector3, knock: float) -> void:
	_hit_react(amount, dir, knock)
	if state == State.LEAVING or done:
		return
	_last_hit = 0.0
	if not wants_water():
		# 물로 해결하는 대상이 아님 → 민원
		wet = min(wet + amount, 1.0)
		_update_wet_visual()
		if _annoy_cd <= 0.0:
			_annoy_cd = 3.5
			say((LINES.minor if is_minor() else LINES.ped).pick_random(), Color(1, 0.8, 0.5))
			_play("emote-no", 0.1)
			annoyed.emit(self, is_minor())
			if state == State.WALK:
				_timer = 2.0
				_set_state(State.STAGGER)
		return

	wet += amount
	_update_wet_visual()
	if wet >= need:
		_finish_water()
		return
	_escalate_lines()
	match kind:
		"runner":
			if state == State.SMOKING:
				_start_flee()
		"angry":
			if state != State.CHARGE:
				say(LINES.angry.pick_random(), Color(1, 0.4, 0.3))
				_set_state(State.CHARGE)
		"boss":
			if state == State.SMOKING:
				_set_state(State.CHARGE)


func _finish_water() -> void:
	wet = need
	_update_wet_visual()
	if _cig:
		Sfx.play_at("sizzle", global_position + Vector3.UP * 1.5, 2.0)
		if _smoke:
			_smoke.emitting = false
		var steam := _make_steam()
		steam.global_position = _cig.global_position
		steam.emitting = true
		_cig.queue_free()
		_cig = null
	if _bar_bg:
		_bar_bg.visible = false
	# 단속 완료: 비명 지르며 꽈당 넘어졌다가 일어나 도망
	Popups.text(self, global_position + Vector3.UP * _head_y(), "치이익!" if kind in ADULT_SMOKERS else "철퍽!", Color(0.75, 0.92, 1), 90)
	Sfx.play_at("voice_scream" if kind != "boss" else "voice_boss", global_position + Vector3.UP * 1.5, 0.0, _voice_pitch)
	_knockdown(global_basis.z if _knock.length() < 0.1 else _knock.normalized(), 3.5)
	_resolve(0.0, true)
	_later(1.2, func():
		if is_instance_valid(self):
			say(_done_line(), Color(0.7, 0.9, 1)))
	_drop_bag()


func _resolve(leave_delay: float, run: bool) -> void:
	if done:
		return
	done = true
	if _label:
		_label.queue_free()
		_label = null
	remove_from_group("smoker")
	remove_from_group("npc")
	remove_from_group("soakable")
	remove_from_group("incident")
	collision_layer = 0
	if not _spot.is_empty():
		_spot.busy = false
	resolved.emit(self, task())
	_timer = leave_delay
	if run:
		walk_speed = run_speed / 1.4
	if state == State.DOWN:
		_leave_after_down = true
	else:
		_set_state(State.LEAVING)


# ---------------------------------------------------------------- 촬영

func on_photographed() -> void:
	if done:
		return
	match kind:
		"jaywalker":
			say(LINES.jaywalk.pick_random(), Color(1, 0.95, 0.5))
			_resolve(0.0, false)
			# 마저 건너간 뒤 평범한 행인처럼 사라진다
		"teen_smoker":
			say(LINES.teen_caught.pick_random(), Color(1, 0.7, 0.85))
			if _smoke:
				_smoke.emitting = false
			if _cig:
				_cig.queue_free()
				_cig = null
			_play("emote-no", 0.1)
			_resolve(1.0, true)
		"teen_drinker":
			for n in get_tree().get_nodes_in_group("teen_drink_%d" % group_id):
				if not n.done:
					n.say(LINES.teen_caught.pick_random(), Color(0.85, 0.7, 1))
					n._play("emote-no", 0.1)
					n._resolve(0.8, true)
		"bully", "victim":
			var first := true
			for n in get_tree().get_nodes_in_group("bully_%d" % group_id):
				if n.done:
					continue
				if n.kind == "victim":
					n.say(LINES.victim.pick_random(), Color(0.7, 1, 0.7))
					n._play("emote-yes", 0.1)
					# 피해 학생은 업무 집계에서 빼고 조용히 떠난다
					n.done = true
					n.remove_from_group("incident")
					n.remove_from_group("npc")
					n.remove_from_group("soakable")
					n.collision_layer = 0
					if n._label:
						n._label.queue_free()
						n._label = null
					n._timer = 1.6
					n._set_state(State.LEAVING)
				else:
					n.say(LINES.bully_caught.pick_random(), Color(1, 0.6, 0.6))
					if first:
						# 무리 중 한 명만 업무 집계 (한 건으로 친다)
						n._resolve(0.2, true)
						first = false
					else:
						n._quiet_leave(0.2, true)


func _quiet_leave(delay: float, run: bool) -> void:
	done = true
	remove_from_group("incident")
	remove_from_group("npc")
	remove_from_group("soakable")
	collision_layer = 0
	_timer = delay
	if run:
		walk_speed = run_speed / 1.4
	_set_state(State.LEAVING)


# ---------------------------------------------------------------- 상태

func _set_state(s: State) -> void:
	state = s
	match s:
		State.WALK, State.CROSSING:
			_play("walk")
		State.SMOKING, State.HANGOUT:
			_play("idle")
			_puff_t = randf_range(1.0, 3.0)
		State.FLEE, State.CHARGE:
			_play("sprint")
		State.LEAVING:
			pass


func _physics_process(delta: float) -> void:
	_last_hit += delta
	_annoy_cd -= delta
	_kick_cd -= delta
	_timer -= delta
	_voice_cd -= delta
	_squash_cd -= delta
	_splat_cd -= delta
	_busy_t -= delta
	_down_cd -= delta
	_slip_cd -= delta
	if _shield_t > 0.0:
		_shield_t -= delta
		if _shield_t <= 0.0 and state != State.DOWN:
			_resume_anim()
	if _drip and _drip.emitting and _last_hit > 3.0 and not done:
		_drip.emitting = false

	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5

	var move := Vector3.ZERO
	match state:
		State.WALK:
			move = _walk_step(delta)
		State.SMOKING:
			move = _smoke_step(delta)
		State.HANGOUT:
			move = _hangout_step(delta)
		State.CROSSING:
			move = _cross_step()
		State.FLEE:
			move = _thief_step() if kind == "thief" else _flee_step()
		State.CHARGE:
			move = _charge_step()
		State.STAGGER:
			if _timer <= 0.0:
				_set_state(State.WALK)
				start_walking(city.nearest_nav(global_position))
		State.LEAVING:
			move = _leave_step()
		State.DOWN:
			move = _down_step(delta)
	if _shield_t > 0.0 and state in [State.WALK, State.CROSSING]:
		move *= 0.2
	_check_slip()

	# 마르기 (보스 제외)
	if is_smoking() and kind != "boss" and _last_hit > 2.0 and wet > 0.0:
		wet = max(wet - 0.08 * delta, 0.0)
		_update_wet_visual()

	_knock = _knock.move_toward(Vector3.ZERO, (5.0 if state == State.DOWN else 12.0) * delta)
	velocity.x = move.x + _knock.x
	velocity.z = move.z + _knock.z
	if move.length_squared() > 0.01 and _shield_t <= 0.0:
		var target_yaw := atan2(-move.x, -move.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 10.0 * delta)
	move_and_slide()


func _walk_step(delta: float) -> Vector3:
	if kind == "thief" and not done and not _stolen:
		_snatch_t -= delta
		if _snatch_t <= 0.0:
			_snatch_t = 2.0
			_try_snatch()
	if kind == "litter" and not done:
		_litter_t -= delta
		if _litter_t <= 0.0:
			_litter_t = randf_range(5.0, 9.0)
			_play("interact-right", 0.1)
			dropped_trash.emit(global_position + global_basis.z * -0.4 + Vector3.UP * 0.05)
			_later(0.6, func():
				if is_instance_valid(self) and state == State.WALK:
					_play("walk"))
	if _to_node < 0:
		return Vector3.ZERO
	var to := _target - global_position
	to.y = 0
	if to.length() < 0.6:
		_pick_next_node()
		return Vector3.ZERO
	return to.normalized() * walk_speed


func _pick_next_node() -> void:
	var cur := _from_node if _to_node < 0 else _to_node
	var options: Array = city.nav_edges[cur].duplicate()
	if options.size() > 1 and _to_node >= 0:
		options.erase(_from_node)
	_from_node = cur
	_to_node = options.pick_random()
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.45
	_target = city.nav_nodes[_to_node] + side


func _cross_step() -> Vector3:
	var on_road := city.is_on_road(global_position)
	if _label:
		_label.visible = on_road and not done
	var to := _cross_to - global_position
	to.y = 0
	if to.length() < 0.5:
		# 다 건넜다 → 평범한 행인
		if not done:
			done = true
			remove_from_group("incident")
			if _label:
				_label.queue_free()
				_label = null
		kind = "ped"
		_set_state(State.WALK)
		start_walking(city.nearest_nav(global_position))
		return Vector3.ZERO
	return to.normalized() * walk_speed


func _smoke_step(delta: float) -> Vector3:
	_puff_t -= delta
	if _puff_t <= 0.0:
		_puff_t = randf_range(2.5, 4.5)
		_play("interact-right", 0.15)
		_later(0.5, _puff_out)
	if _busy_t <= 0.0:
		_play("idle")
	if kind == "runner" and player:
		if global_position.distance_to(player.global_position) < 9.0:
			_start_flee()
	if kind == "boss" and player and global_position.distance_to(player.global_position) < 22.0:
		_set_state(State.CHARGE)
	return Vector3.ZERO


func _hangout_step(delta: float) -> Vector3:
	_puff_t -= delta
	match kind:
		"teen_drinker":
			if _puff_t <= 0.0:
				_puff_t = randf_range(2.0, 5.0)
				_play("interact-right" if randf() < 0.6 else "emote-yes", 0.15)
		"bully":
			if victim and is_instance_valid(victim):
				var to := victim.global_position - global_position
				rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 0.1)
				if _puff_t <= 0.0:
					_puff_t = randf_range(1.5, 3.0)
					_play("attack-melee-right" if randf() < 0.5 else "attack-kick-right", 0.1)
					victim._on_bullied()
		"victim":
			if _puff_t <= 0.0:
				_puff_t = randf_range(3.0, 5.0)
				say(LINES.victim_help.pick_random(), Color(1, 0.85, 0.85))
		"fighter":
			_fight_step()
		"tagger":
			_tag_step()
		"pee":
			if _puff_t <= 0.0:
				_puff_t = randf_range(3.0, 6.0)
				say(LINES.pee.pick_random(), Color(1, 0.95, 0.6))
	if _busy_t <= 0.0:
		_play("idle")
	return Vector3.ZERO


func _on_bullied() -> void:
	_play("emote-no", 0.05)


func _leave_step() -> Vector3:
	if _timer <= 0.0 and _timer > -0.1:
		_play("sprint" if walk_speed > 2.5 else "walk")
		var away := global_position - player.global_position
		away.y = 0
		_flee_dir = away.normalized()
	if _timer < 0.0:
		if is_on_wall():
			_flee_dir = _flee_dir.rotated(Vector3.UP, PI / 2)
		if _timer < -6.0:
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
			tw.tween_callback(queue_free)
			_timer = 999.0
		return _flee_dir * walk_speed * 1.4
	return Vector3.ZERO


func _start_flee() -> void:
	say(LINES.runner.pick_random(), Color(1, 0.9, 0.4))
	var away := global_position - player.global_position
	away.y = 0
	_flee_dir = away.normalized().rotated(Vector3.UP, randf_range(-0.5, 0.5))
	_timer = randf_range(4.0, 6.0)
	if not _spot.is_empty():
		_spot.busy = false
		_spot = {}
	_set_state(State.FLEE)


func _flee_step() -> Vector3:
	if is_on_wall():
		var n := get_wall_normal()
		n.y = 0
		_flee_dir = (_flee_dir + n * 1.5).normalized().rotated(Vector3.UP, randf_range(-0.6, 0.6))
	if _timer <= 0.0 and global_position.distance_to(player.global_position) > 14.0:
		_set_state(State.SMOKING)
		return Vector3.ZERO
	return _flee_dir * run_speed


func _charge_step() -> Vector3:
	var to := player.global_position - global_position
	to.y = 0
	var dist := to.length()
	var reach := 1.5 * _scale / 0.65
	if kind == "angry" and dist > 25.0:
		_set_state(State.SMOKING)
		return Vector3.ZERO
	if dist < reach:
		if _kick_cd <= 0.0:
			_kick_cd = 1.6 if kind == "angry" else 2.2
			_play("attack-kick-right", 0.05)
			_later(0.25, _kick_land)
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 0.3)
		return Vector3.ZERO
	if _cur_anim != "sprint" and _kick_cd < 1.0:
		_play("sprint")
	return to.normalized() * run_speed


func _kick_land() -> void:
	if state != State.CHARGE or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) < 2.2 * _scale / 0.65:
		Sfx.play_at("kick", global_position + Vector3.UP, 4.0)
		hurt_player.emit(self, 2 if kind == "boss" else 1)


# ---------------------------------------------------------------- 연출

func _puff_out() -> void:
	if not is_instance_valid(self) or done or _puff == null:
		return
	_puff.restart()


# ---------------------------------------------------------------- 맞을 때 반응

func _hit_react(amount: float, dir: Vector3, knock: float) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 0.001:
		flat = global_basis.z
	flat = flat.normalized()
	var weight := _scale / 0.65
	# 물살에 밀린다 (분무기도 살짝)
	_knock += flat * (0.25 + knock) / weight
	_knock = _knock.limit_length(7.0)
	# 움찔 (납작했다가 튕겨 돌아옴)
	if _squash_cd <= 0.0:
		_squash_cd = 0.14
		var tw := create_tween()
		tw.tween_property(_model, "scale", Vector3(1.18, 0.8, 1.18), 0.05)
		tw.tween_property(_model, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 비명
	if _voice_cd <= 0.0 and state != State.DOWN:
		_voice_cd = randf_range(0.7, 1.2)
		var v := "voice_boss" if kind == "boss" else ("voice_kid" if is_minor() else "voice_adult")
		Sfx.play_at(v, global_position + Vector3.UP * _head_y(), -1.0, _voice_pitch)
	# 철퍽! 글자 (센 물줄기일수록 자주)
	if _splat_cd <= 0.0 and (amount >= 0.05 or knock >= 1.0 or _last_hit > 1.5):
		_splat_cd = 0.6
		Popups.text(self, global_position + Vector3.UP * (_head_y() + 0.2), SPLAT.pick_random(), Color(0.55, 0.85, 1), 64, 0.8, 0.6)
	# 물방울 뚝뚝
	if _drip and not _drip.emitting:
		_drip.emitting = true
	# 팔로 얼굴 가리며 물줄기 쪽을 본다
	if state in [State.WALK, State.SMOKING, State.HANGOUT, State.CROSSING, State.STAGGER]:
		if _shield_t <= 0.0:
			_play("holding-both", 0.06)
		_shield_t = 0.45
		rotation.y = atan2(flat.x, flat.z)
	# 소방호스/양동이는 사람을 넘어뜨린다
	if knock >= 2.0 and _down_cd <= 0.0 and state != State.DOWN:
		Popups.text(self, global_position + Vector3.UP * _head_y(), "꽈당!", Color(1, 0.85, 0.3), 84)
		Sfx.play_at("voice_scream", global_position + Vector3.UP * 1.5, 0.0, _voice_pitch)
		_knockdown(flat, knock)


func _escalate_lines() -> void:
	var r := wet / need
	var stage := 3 if r > 0.75 else (2 if r > 0.45 else (1 if r > 0.1 else 0))
	if stage > _line_stage:
		_line_stage = stage
		say(LINES["wet%d" % stage].pick_random(), Color(0.75, 0.9, 1))


func _knockdown(dir: Vector3, power: float) -> void:
	if state == State.DOWN:
		return
	_prev_state = state if state != State.STAGGER else State.WALK
	state = State.DOWN
	_shield_t = 0.0
	_down_t = 1.4 + min(power * 0.15, 0.8)
	_knock = dir.normalized() * (2.5 + power * 1.2) / (_scale / 0.65)
	_play("die", 0.05)
	Sfx.play_at("slip", global_position, -2.0)


func _down_step(delta: float) -> Vector3:
	_down_t -= delta
	if _down_t <= 0.0:
		_down_t = 99.0   # 일어나는 중 (한 번만)
		_play("pick-up", 0.15)
		_later(0.45, _get_up)
	return Vector3.ZERO


func _get_up() -> void:
	if not is_instance_valid(self) or state != State.DOWN:
		return
	_down_cd = 2.5
	if _leave_after_down or done:
		_leave_after_down = false
		Sfx.play_at("voice_achoo", global_position + Vector3.UP * 1.5, -2.0, _voice_pitch)
		Popups.text(self, global_position + Vector3.UP * _head_y(), "에취!", Color(1, 1, 1), 70)
		_timer = 0.0
		_set_state(State.LEAVING)
		return
	_set_state(_prev_state)
	if _prev_state == State.WALK:
		start_walking(city.nearest_nav(global_position))


func _resume_anim() -> void:
	match state:
		State.WALK, State.CROSSING:
			_play("walk")
		State.SMOKING, State.HANGOUT, State.STAGGER:
			_play("idle")
		State.FLEE, State.CHARGE:
			_play("sprint")


func _check_slip() -> void:
	## 물웅덩이 위를 뛰다가 미끄러진다
	if _slip_cd > 0.0 or state == State.DOWN or done:
		return
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv < 3.0:
		return
	_slip_cd = 0.25
	if _water == null:
		_water = get_tree().get_first_node_in_group("water_system")
	if _water and _water.is_wet(global_position):
		_slip_cd = 3.0
		Popups.text(self, global_position + Vector3.UP * _head_y(), "미끄덩!", Color(0.6, 1, 0.9), 80)
		Sfx.play_at("voice_scream", global_position + Vector3.UP * 1.5, -2.0, _voice_pitch * 1.1)
		_knockdown(Vector3(velocity.x, 0, velocity.z), 2.0)


func _build_drip() -> void:
	_drip = CPUParticles3D.new()
	_drip.emitting = false
	_drip.amount = 12
	_drip.lifetime = 0.6
	_drip.local_coords = false
	_drip.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drip.emission_box_extents = Vector3(0.25, 0.5, 0.15) * (_scale / 0.65)
	_drip.direction = Vector3.DOWN
	_drip.spread = 10
	_drip.initial_velocity_min = 0.2
	_drip.initial_velocity_max = 0.6
	_drip.gravity = Vector3(0, -9.8, 0)
	var m := SphereMesh.new()
	m.radius = 0.025
	m.height = 0.06
	m.radial_segments = 4
	m.rings = 2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	_drip.mesh = m
	_drip.position.y = 1.0 * _scale / 0.65
	add_child(_drip)


# ---------------------------------------------------------------- 도둑, 싸움, 낙서, 노상방뇨

var _snatch_t := 0.0
var _stolen := false
var _bag: Node3D
var _escape_t := 0.0
var _hit_t := 0.0
var _spray_fx: CPUParticles3D


func _done_line() -> String:
	match kind:
		"litter": return LINES.litter_done.pick_random()
		"thief": return LINES.thief_done.pick_random()
		"fighter": return LINES.fight_done.pick_random()
		"tagger": return LINES.tagger_done.pick_random()
		"pee": return LINES.pee_done.pick_random()
	return LINES.done.pick_random()


## 차에 치이거나 태클 당해 잡힌다
func caught(by: String, dir: Vector3) -> void:
	if done:
		return
	Popups.text(self, global_position + Vector3.UP * _head_y(), "태클!" if by == "tackle" else "쾅!", Color(1, 0.8, 0.3), 96)
	Sfx.play_at("voice_scream", global_position + Vector3.UP * 1.5, 0.0, _voice_pitch)
	Sfx.play_at("kick", global_position, 4.0)
	_knockdown(dir, 5.0)
	_resolve(0.0, true)
	if _smoke:
		_smoke.emitting = false
	_later(1.0, func():
		if is_instance_valid(self):
			say(_done_line(), Color(0.7, 0.9, 1)))
	_drop_bag()


## 행인이 차에 치였다 (넘어지고 화낸다)
func run_over(dir: Vector3, spd: float) -> void:
	if state == State.DOWN:
		return
	Popups.text(self, global_position + Vector3.UP * _head_y(), "꽈당!", Color(1, 0.6, 0.4), 84)
	Sfx.play_at("voice_scream", global_position + Vector3.UP * 1.5, 0.0, _voice_pitch)
	Sfx.play_at("thud", global_position, 4.0)
	_knockdown(dir, min(spd * 0.4, 6.0))
	_later(1.6, func():
		if is_instance_valid(self):
			say(LINES.hit_by_car.pick_random(), Color(1, 0.6, 0.5)))


func _try_snatch() -> void:
	## 근처 행인의 가방을 낚아채서 달아난다
	var best: Npc = null
	var bd := 4.0
	for n in get_parent().get_children():
		if n is Npc and n != self and n.kind == "ped" and n.state == State.WALK:
			var d: float = n.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = n
	if best == null:
		return
	_stolen = true
	stolen_from = best
	add_to_group("incident")
	best.say(LINES.robbed.pick_random(), Color(1, 0.4, 0.4))
	best._play("emote-no", 0.05)
	shout.emit(best, "도둑이야!!")
	Sfx.play_at("voice_scream", best.global_position + Vector3.UP * 1.5, 4.0, 1.2)
	# 손에 가방
	var hand: Array = _hand_tip()
	_bag = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.3, 0.15) / _scale
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.2, 0.35)
	bm.material = mat
	(_bag as MeshInstance3D).mesh = bm
	hand[0].add_child(_bag)
	_bag.position = hand[1]
	_escape_t = 0.0
	_to_node = -1
	_set_state(State.FLEE)


func _thief_step() -> Vector3:
	## 길을 따라 플레이어에게서 먼 쪽으로 달린다. 오래 못 잡으면 사라진다.
	_escape_t += get_physics_process_delta_time()
	if _escape_t > 50.0 and global_position.distance_to(player.global_position) > 35.0:
		done = true
		remove_from_group("incident")
		shout.emit(self, "도둑을 놓쳤어요...")
		queue_free()
		return Vector3.ZERO
	if _to_node < 0 or Vector2(global_position.x - _target.x, global_position.z - _target.z).length() < 0.8:
		var cur := city.nearest_nav(global_position) if _to_node < 0 else _to_node
		var best := cur
		var bd := -1.0
		for j in city.nav_edges[cur]:
			var d: float = city.nav_nodes[j].distance_to(player.global_position) + randf() * 6.0
			if d > bd:
				bd = d
				best = j
		_from_node = cur
		_to_node = best
		_target = city.nav_nodes[best]
		if randf() < 0.3:
			say(LINES.thief.pick_random(), Color(1, 0.6, 0.6))
	var to := _target - global_position
	to.y = 0
	return to.normalized() * run_speed


func _drop_bag() -> void:
	if _bag == null:
		return
	_bag.queue_free()
	_bag = null
	dropped_bag.emit(global_position + global_basis.z * 0.6, stolen_from)


func _fight_step() -> void:
	if partner == null or not is_instance_valid(partner) or partner.done:
		return
	var to := partner.global_position - global_position
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 0.2)
	if _puff_t <= 0.0:
		_puff_t = randf_range(0.8, 1.6)
		_play(["attack-melee-right", "attack-melee-left", "attack-kick-right"].pick_random(), 0.05)
		_later(0.2, func():
			if is_instance_valid(partner) and not partner.done and partner.state == State.HANGOUT:
				partner._hit_react(0.0, partner.global_position - global_position, 0.0)
				Sfx.play_at("kick", partner.global_position + Vector3.UP, -2.0))
		if randf() < 0.35:
			say(LINES.fight.pick_random(), Color(1, 0.6, 0.4))


func _tag_step() -> void:
	if _puff_t <= 0.0:
		_puff_t = randf_range(0.3, 0.6)
		_play("interact-right", 0.1)
		if _spray_fx:
			_spray_fx.restart()
		# 낙서가 점점 커진다
		if graffiti and is_instance_valid(graffiti):
			graffiti.scale = (graffiti.scale + Vector3.ONE * 0.06).clamp(Vector3.ONE * 0.2, Vector3.ONE * 1.4)


func _build_spray_can() -> void:
	var hand: Array = _hand_tip()
	var can := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 0.16
	var mat := StandardMaterial3D.new()
	var col: Color = [Color(1, 0.2, 0.3), Color(0.2, 0.8, 1), Color(1, 0.85, 0.1)].pick_random()
	mat.albedo_color = col
	cm.material = mat
	can.mesh = cm
	can.scale = Vector3.ONE / _scale
	hand[0].add_child(can)
	can.position = hand[1]
	_spray_fx = CPUParticles3D.new()
	_spray_fx.emitting = false
	_spray_fx.one_shot = true
	_spray_fx.explosiveness = 0.5
	_spray_fx.amount = 16
	_spray_fx.lifetime = 0.5
	_spray_fx.local_coords = false
	_spray_fx.direction = Vector3(0, 0, -1)
	_spray_fx.spread = 15
	_spray_fx.initial_velocity_min = 2.0
	_spray_fx.initial_velocity_max = 3.0
	_spray_fx.gravity = Vector3.ZERO
	var pm := SphereMesh.new()
	pm.radius = 0.03
	pm.height = 0.06
	pm.radial_segments = 4
	pm.rings = 2
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = col
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.material = pmat
	_spray_fx.mesh = pm
	_spray_fx.position = Vector3(0, 1.3 * _scale / 0.65, -0.3)
	add_child(_spray_fx)


func say(text: String, color := Color.WHITE) -> void:
	## 머리 위 말풍선은 띄우지 않는다 (목소리와 몸짓만). 대화는 대화창에서.
	return
	_say.text = text
	_say.modulate = color
	_say.visible = true
	_say.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(_say, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.8)
	tw.tween_callback(func(): _say.visible = false)


func _play(anim: String, blend := 0.2) -> void:
	## 예전(Kenney) 이름으로 불러도 역할/몸에 맞는 실사 애니메이션으로 바꿔 튼다
	_cur_anim = anim
	var a: String = ANIM_MAP.get(anim, anim)
	match a:
		"walk":
			a = _walk_anim
		"sprint":
			if is_minor():
				a = "run_kid"
		"drink":
			if kind == "litter":
				a = "throw"
			elif kind == "tagger":
				a = "wave"
		"wave_off":
			if kind == "victim":
				a = "fear"
	# 몸짓은 잠깐만 하고 다시 서 있게 (_busy_t 가 끝나면 호출한 쪽이 idle 로 돌린다)
	_busy_t = 2.2 if anim in ["interact-right", "emote-yes", "emote-no", "attack-melee-right", "attack-kick-right"] else 0.0
	if a == _model.playing():
		_anim.seek(0.0)
	_model.play(a, blend)


func _make_label(color: Color, size: int) -> Label3D:
	var l := Label3D.new()
	l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	l.font_size = size
	l.outline_size = 10
	l.pixel_size = 0.006
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.visibility_range_end = 60.0
	add_child(l)
	return l


func _hand_tip() -> Array:
	## 오른손 끝 (붙일 부모 노드, 위치). 손 뼈에 붙이고, 붙인 물건 크기는 예전처럼 _scale 기준으로 맞춘다.
	if _hand == null:
		var skels := _model.find_children("*", "Skeleton3D", true, false)
		if skels.is_empty():
			return [_model, Vector3(0.25, 1.0, -0.2) / _scale]
		var ba := BoneAttachment3D.new()
		ba.bone_name = "RightHand"
		skels[0].add_child(ba)
		_hand = Node3D.new()
		ba.add_child(_hand)
		var gs: float = ba.global_transform.basis.get_scale().x / max(global_transform.basis.get_scale().x, 0.001)
		_hand.scale = Vector3.ONE * (_scale / max(gs, 0.001))
	return [_hand, Vector3(0, 0.09, 0.03) / _scale]


func _add_backpack() -> void:
	var bag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.42, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = [Color(0.2, 0.35, 0.8), Color(0.85, 0.3, 0.3), Color(0.2, 0.6, 0.35), Color(0.9, 0.75, 0.2)].pick_random()
	bm.material = mat
	bag.mesh = bm
	bag.position = Vector3(0, 1.0 * _scale / 0.65, 0.22 * _scale / 0.65)
	bag.scale = Vector3.ONE * _scale / 0.65
	add_child(bag)


func _build_bottle() -> void:
	var hand: Array = _hand_tip()
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.035
	cm.height = 0.22
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.55, 0.25, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.material = mat
	b.mesh = cm
	b.scale = Vector3.ONE / _scale
	hand[0].add_child(b)
	b.position = hand[1]


func _build_cigarette() -> void:
	var hand: Array = _hand_tip()
	_cig = Node3D.new()
	hand[0].add_child(_cig)
	_cig.position = hand[1]
	var inv := 1.0 / _scale
	var stick := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.025, 0.025, 0.16) * inv
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.93, 0.88)
	sm.material = white
	stick.mesh = sm
	stick.position = Vector3(0, 0, 0.06) * inv
	_cig.add_child(stick)
	var ember := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.03, 0.03, 0.03) * inv
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1, 0.35, 0.05)
	glow.emission_enabled = true
	glow.emission = Color(1, 0.3, 0.0)
	glow.emission_energy_multiplier = 4.0
	em.material = glow
	ember.mesh = em
	ember.position = Vector3(0, 0, 0.145) * inv
	_cig.add_child(ember)

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_texture = FxPool.soft_puff()
	smoke_mat.albedo_color = Color(0.72, 0.72, 0.75, 0.75)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.75, 0.75)
	quad.material = smoke_mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0))
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 3.2))

	_smoke = CPUParticles3D.new()
	# 멀리서도 보이게 길고 굵게 피어오르는 연기
	_smoke.amount = 34
	_smoke.lifetime = 3.5
	_smoke.preprocess = 3.5   # 미리 데워두지 않으면 시작점에 검은 덩어리가 생긴다
	_smoke.local_coords = false
	_smoke.mesh = quad
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.04
	_smoke.initial_velocity_min = 0.35
	_smoke.initial_velocity_max = 0.6
	_smoke.gravity = Vector3(0.2, 0.2, 0)
	_smoke.color_ramp = fade
	_smoke.scale_amount_curve = grow
	_smoke.angle_min = -180
	_smoke.angle_max = 180
	ember.add_child(_smoke)

	# 내뿜는 연기: 입 앞에서 한 번에 터지는 one_shot
	_puff = _smoke.duplicate()
	_puff.emitting = false
	_puff.one_shot = true
	_puff.preprocess = 0.0
	_puff.explosiveness = 0.85
	_puff.amount = 14 if kind != "boss" else 40
	_puff.lifetime = 2.2
	_puff.direction = Vector3(0, 0.3, -1)
	_puff.spread = 25.0
	_puff.initial_velocity_min = 0.4 if kind != "boss" else 1.5
	_puff.initial_velocity_max = 0.9 if kind != "boss" else 3.0
	_puff.scale_amount_min = 1.5
	_puff.scale_amount_max = 3.0 if kind != "boss" else 9.0
	_puff.position = Vector3(0, 1.65 * _scale / 0.65, -0.25)
	add_child(_puff)


func _build_bar() -> void:
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0, 0, 0, 0.6)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.billboard_keep_scale = true
	var fill_mat := bg_mat.duplicate()
	fill_mat.albedo_color = Color(0.35, 0.75, 1.0, 0.95)
	fill_mat.render_priority = 1

	var w := 0.9 * (_scale / 0.65)
	_bar_bg = MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(w + 0.06, 0.13)
	bgm.material = bg_mat
	_bar_bg.mesh = bgm
	_bar_bg.position.y = _head_y() + 0.3
	_bar_bg.visible = false
	add_child(_bar_bg)

	_bar_fill = MeshInstance3D.new()
	_bar_mesh = QuadMesh.new()
	_bar_mesh.material = fill_mat
	_bar_fill.mesh = _bar_mesh
	_bar_bg.add_child(_bar_fill)


func _update_wet_visual() -> void:
	var r: float = clamp(wet / need, 0.0, 1.0)
	_overlay.albedo_color.a = r * 0.45
	# 젖었을 때만 덧칠 (덧칠은 메시마다 한 번 더 그리는 비용이 든다)
	if (r > 0.0) != _overlay_on:
		_overlay_on = r > 0.0
		for m in _meshes:
			m.material_overlay = _overlay if _overlay_on else null
	if _bar_bg:
		_bar_bg.visible = r > 0.0 and not done
		var w: float = 0.9 * (_scale / 0.65)
		_bar_mesh.size = Vector2(max(w * r, 0.001), 0.09)
		_bar_mesh.center_offset = Vector3(-w / 2 + w * r / 2, 0, 0.001)
		if _label:
			_label.position.y = _head_y() + 0.5


func _make_steam() -> CPUParticles3D:
	var p: CPUParticles3D = _smoke.duplicate()
	p.amount = 24
	p.lifetime = 1.2
	p.preprocess = 0.0
	p.one_shot = true
	p.explosiveness = 0.9
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0
	p.spread = 60
	get_tree().current_scene.add_child(p)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	return p


## t초 뒤에 fn 실행. 이 노드가 사라지면 같이 취소된다.
func _later(t: float, fn: Callable) -> void:
	var tw := create_tween()
	tw.tween_interval(t)
	tw.tween_callback(fn)
