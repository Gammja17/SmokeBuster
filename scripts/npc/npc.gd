class_name Npc
extends CharacterBody3D
## 행인과 흡연자. kind: "ped"(행인), "normal", "runner"(보면 도망), "angry"(맞으면 달려와 발차기), "boss"
## 흡연자는 물을 need 만큼 맞으면 담배가 꺼지고 떠난다.

signal extinguished(npc: Npc)
signal annoyed(npc: Npc)
signal hurt_player(npc: Npc, amount: int)

enum State { WALK, SMOKING, FLEE, CHARGE, LEAVING, STAGGER }

const MODELS := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r"]
const LINES := {
	"done": ["앗 차가워!", "죄송합니다...", "에이 씨...", "알겠다고요!", "끄라면 끄지!", "으악 내 담배!", "아 축축해..."],
	"ped": ["뭐야?!", "저 담배 안 피워요!", "민원 넣는다!", "아 왜 나한테!", "옷 젖었잖아요!"],
	"runner": ["단속이다!", "튀어!", "못 잡지롱~"],
	"angry": ["너 뭐야!", "이게 미쳤나!", "한판 붙자!", "감히 나한테!"],
	"boss": ["후우우우...", "내가 이 동네 골초왕이다!", "물 따위로 날 끌 수 있을까?"],
}

var kind := "ped"
var city: CityBuilder
var player: Node3D
var state := State.WALK

var need := 1.0
var wet := 0.0
var walk_speed := 1.6
var run_speed := 5.2

var _model: Node3D
var _anim: AnimationPlayer
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
var _knock := Vector3.ZERO
var _flee_dir := Vector3.ZERO
var _spot: Dictionary = {}
var _puff_t := 0.0
var _scale := 0.65


func setup(p_kind: String, p_city: CityBuilder, p_player: Node3D) -> void:
	kind = p_kind
	city = p_city
	player = p_player


func _ready() -> void:
	add_to_group("npc")
	collision_layer = 2
	collision_mask = 1
	if kind == "boss":
		_scale = 1.15
		need = 14.0
		walk_speed = 1.3
		run_speed = 2.6
	elif kind == "angry":
		need = 1.6
	elif kind == "runner":
		run_speed = 5.6

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35 * _scale / 0.65
	cap.height = 1.75 * _scale / 0.65
	col.shape = cap
	col.position.y = cap.height / 2
	add_child(col)

	_model = load("res://assets/chars/character-%s.glb" % MODELS.pick_random()).instantiate()
	_model.scale = Vector3.ONE * _scale
	_model.rotation.y = PI
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	for a in ["idle", "walk", "sprint"]:
		_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_anim.speed_scale = randf_range(0.9, 1.1)

	_overlay = StandardMaterial3D.new()
	_overlay.albedo_color = Color(0.3, 0.55, 1.0, 0.0)
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_meshes = _model.find_children("*", "MeshInstance3D", true, false)
	for m in _meshes:
		# 멀리 있는 사람은 그리지 않는다
		m.visibility_range_end = 75.0

	_say = _make_label(Color.WHITE, 40)
	_say.position.y = 2.25 * _scale / 0.65
	_say.visible = false

	if is_smoker_kind():
		_build_cigarette()
		_build_bar()
		_label = _make_label(Color(1, 0.35, 0.25), 34)
		_label.position.y = 2.0 * _scale / 0.65
		_label.text = {"normal": "흡연중", "runner": "흡연중 (도망 주의)", "angry": "흡연중 (성질 주의)", "boss": "골초왕"}[kind]
		if kind == "boss":
			_label.font_size = 64
			_label.modulate = Color(1, 0.8, 0.1)

	if is_smoker_kind():
		_set_state(State.SMOKING)
	else:
		_set_state(State.WALK)


func is_smoker_kind() -> bool:
	return kind != "ped"


func is_smoking() -> bool:
	return is_smoker_kind() and state in [State.SMOKING, State.FLEE, State.CHARGE, State.STAGGER]


## 걷는 행인이 그 자리에서 담배를 꺼내 문다.
func light_up(new_kind: String) -> void:
	kind = new_kind
	if kind == "angry":
		need = 1.6
	_build_cigarette()
	_build_bar()
	_label = _make_label(Color(1, 0.35, 0.25), 34)
	_label.position.y = 2.0
	_label.text = {"normal": "흡연중", "runner": "흡연중 (도망 주의)", "angry": "흡연중 (성질 주의)"}[kind]
	_set_state(State.SMOKING)


func start_walking(from_node: int) -> void:
	_from_node = from_node
	_pick_next_node()


func occupy(spot: Dictionary) -> void:
	_spot = spot
	spot.busy = true


# ---------------------------------------------------------------- 물 맞기

func soak(amount: float, dir: Vector3, knock: float) -> void:
	if state == State.LEAVING:
		return
	_last_hit = 0.0
	if knock > 0.0:
		_knock += Vector3(dir.x, 0, dir.z).normalized() * knock / (_scale / 0.65)
	if not is_smoker_kind():
		wet = min(wet + amount, 1.0)
		_update_wet_visual()
		if _annoy_cd <= 0.0:
			_annoy_cd = 3.5
			say(LINES.ped.pick_random(), Color(1, 0.8, 0.5))
			_play("emote-no", 0.1)
			annoyed.emit(self)
			_timer = 2.0
			_set_state(State.STAGGER)
		return

	wet += amount
	_update_wet_visual()
	if wet >= need:
		_extinguish()
		return
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


func _extinguish() -> void:
	wet = need
	_update_wet_visual()
	Sfx.play_at("sizzle", global_position + Vector3.UP * 1.5, 2.0)
	if _smoke:
		_smoke.emitting = false
	if _cig:
		var steam := _make_steam()
		steam.global_position = _cig.global_position
		steam.emitting = true
		_cig.queue_free()
		_cig = null
	if _label:
		_label.queue_free()
		_label = null
	_bar_bg.visible = false
	say(LINES.done.pick_random(), Color(0.7, 0.9, 1))
	remove_from_group("smoker")
	remove_from_group("npc")
	collision_layer = 0
	extinguished.emit(self)
	_play("emote-no", 0.1)
	if not _spot.is_empty():
		_spot.busy = false
	_timer = 1.4
	_set_state(State.LEAVING)


# ---------------------------------------------------------------- 상태

func _set_state(s: State) -> void:
	state = s
	match s:
		State.WALK:
			_play("walk")
		State.SMOKING:
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

	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5

	var move := Vector3.ZERO
	match state:
		State.WALK:
			move = _walk_step()
		State.SMOKING:
			move = _smoke_step(delta)
		State.FLEE:
			move = _flee_step()
		State.CHARGE:
			move = _charge_step()
		State.STAGGER:
			if _timer <= 0.0:
				if is_smoker_kind():
					_set_state(State.SMOKING)
				else:
					_set_state(State.WALK)
					if _to_node < 0:
						start_walking(city.nearest_nav(global_position))
		State.LEAVING:
			if _timer <= 0.0 and _timer > -0.1:
				_play("walk")
				var away := global_position - player.global_position
				away.y = 0
				_flee_dir = away.normalized()
			if _timer < 0.0:
				move = _flee_dir * walk_speed * 1.4
				if is_on_wall():
					_flee_dir = _flee_dir.rotated(Vector3.UP, PI / 2)
			if _timer < -6.0:
				var tw := create_tween()
				tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
				tw.tween_callback(queue_free)
				_timer = 999.0

	# 마르기 (보스 제외)
	if is_smoking() and kind != "boss" and _last_hit > 2.0 and wet > 0.0:
		wet = max(wet - 0.08 * delta, 0.0)
		_update_wet_visual()

	_knock = _knock.move_toward(Vector3.ZERO, 12.0 * delta)
	velocity.x = move.x + _knock.x
	velocity.z = move.z + _knock.z
	if move.length_squared() > 0.01:
		var target_yaw := atan2(-move.x, -move.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 10.0 * delta)
	move_and_slide()


func _walk_step() -> Vector3:
	if _to_node < 0:
		return Vector3.ZERO
	var to := _target - global_position
	to.y = 0
	if to.length() < 0.6:
		_pick_next_node()
		return Vector3.ZERO
	return to.normalized() * walk_speed


func _pick_next_node() -> void:
	var options: Array = city.nav_edges[_from_node if _to_node < 0 else _to_node].duplicate()
	var cur := _from_node if _to_node < 0 else _to_node
	if options.size() > 1 and _to_node >= 0:
		options.erase(_from_node)
	_from_node = cur
	_to_node = options.pick_random()
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.45
	_target = city.nav_nodes[_to_node] + side


func _smoke_step(delta: float) -> Vector3:
	_puff_t -= delta
	if _puff_t <= 0.0:
		_puff_t = randf_range(2.5, 4.5)
		_play("interact-right", 0.15)
		get_tree().create_timer(0.5).timeout.connect(_puff_out)
	if _anim.current_animation == "interact-right" and not _anim.is_playing():
		_play("idle")
	if not _anim.is_playing():
		_play("idle")
	# 플레이어를 바라보지 않고 가끔 두리번
	if kind == "runner" and player:
		var d := global_position.distance_to(player.global_position)
		if d < 9.0:
			_start_flee()
	if kind == "boss" and player and global_position.distance_to(player.global_position) < 22.0:
		_set_state(State.CHARGE)
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
			get_tree().create_timer(0.25).timeout.connect(_kick_land)
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 0.3)
		return Vector3.ZERO
	if _anim.current_animation != "sprint" and _kick_cd < 1.0:
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
	if not is_instance_valid(self) or not is_smoking() or _puff == null:
		return
	_puff.restart()


func say(text: String, color := Color.WHITE) -> void:
	_say.text = text
	_say.modulate = color
	_say.visible = true
	_say.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(_say, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.8)
	tw.tween_callback(func(): _say.visible = false)


func _play(anim: String, blend := 0.2) -> void:
	if _anim.has_animation(anim):
		_anim.play(anim, blend)


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


func _build_cigarette() -> void:
	var arm: Node3D = _model.find_child("arm-right", true, false)
	_cig = Node3D.new()
	var tip_pos := Vector3.ZERO
	if arm and arm is MeshInstance3D and arm.mesh:
		var a: AABB = arm.mesh.get_aabb()
		tip_pos = Vector3(a.get_center().x, a.position.y + 0.02, a.end.z)
	(arm if arm else _model).add_child(_cig)
	_cig.position = tip_pos
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
	smoke_mat.albedo_texture = load("res://assets/fx/smoke_07.png")
	smoke_mat.albedo_color = Color(0.8, 0.8, 0.82, 0.6)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	quad.material = smoke_mat
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.7))
	fade.set_color(1, Color(1, 1, 1, 0))
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 1.6))

	_smoke = CPUParticles3D.new()
	_smoke.amount = 14
	_smoke.lifetime = 3.0
	_smoke.local_coords = false
	_smoke.mesh = quad
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.initial_velocity_min = 0.3
	_smoke.initial_velocity_max = 0.6
	_smoke.gravity = Vector3(0.15, 0.35, 0)
	_smoke.color_ramp = fade
	_smoke.scale_amount_curve = grow
	_smoke.angle_min = -180
	_smoke.angle_max = 180
	ember.add_child(_smoke)

	# 내뿜는 연기: 입 앞에서 한 번에 터지는 one_shot
	_puff = _smoke.duplicate()
	_puff.emitting = false
	_puff.one_shot = true
	_puff.explosiveness = 0.85
	_puff.amount = 8 if kind != "boss" else 40
	_puff.lifetime = 2.2
	_puff.direction = Vector3(0, 0.3, -1)
	_puff.spread = 25.0
	_puff.initial_velocity_min = 0.4 if kind != "boss" else 1.5
	_puff.initial_velocity_max = 0.9 if kind != "boss" else 3.0
	_puff.scale_amount_min = 1.5
	_puff.scale_amount_max = 3.0 if kind != "boss" else 9.0
	_puff.position = Vector3(0, 1.65 * _scale / 0.65, -0.25)
	add_child(_puff)
	add_to_group("smoker")


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
	_bar_bg.position.y = 2.2 * _scale / 0.65 + 0.05
	_bar_bg.visible = false
	add_child(_bar_bg)

	_bar_fill = MeshInstance3D.new()
	_bar_mesh = QuadMesh.new()
	_bar_mesh.material = fill_mat
	_bar_fill.mesh = _bar_mesh
	_bar_fill.position.z = 0.0
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
		_bar_bg.visible = r > 0.0
		var w: float = 0.9 * (_scale / 0.65)
		_bar_mesh.size = Vector2(max(w * r, 0.001), 0.09)
		_bar_mesh.center_offset = Vector3(-w / 2 + w * r / 2, 0, 0.001)
		if _say.visible == false and _label:
			_label.position.y = 2.45 * _scale / 0.65


func _make_steam() -> CPUParticles3D:
	var p: CPUParticles3D = _smoke.duplicate()
	p.amount = 24
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.9
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0
	p.spread = 60
	get_tree().current_scene.add_child(p)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	return p
