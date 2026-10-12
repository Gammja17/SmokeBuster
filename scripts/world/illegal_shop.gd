class_name IllegalShop
extends StaticBody3D
## 건물 정면에 붙는 불법업소. 네온 간판과 스피커에 물을 뿌려 합선시키고(1단계),
## E 연타로 간판을 뜯어내거나 순찰차로 들이받으면(2단계) 철거 완료.
## 이 노드의 +Z 가 길 쪽을 본다.

signal resolved(shop: IllegalShop, task: String)
signal shorted(shop: IllegalShop)
signal ripped(shop: IllegalShop, rammed: bool)

const TUGS := 3

const TYPES := {
	"massage": {"text": "수상한 마사지", "color": Color(1, 0.3, 0.7), "music": "lounge"},
	"karaoke": {"text": "24시 노래방", "color": Color(0.7, 0.45, 1), "music": "karaoke"},
	"bar": {"text": "쿵쿵 술집", "color": Color(1, 0.6, 0.2), "music": "club"},
}

var type := "massage"
var need := 5.0
var power := 5.0
var done := false          # 간판까지 뜯겨 철거 끝
var is_shorted := false    # 합선돼서 전원이 나감 (이제 간판을 뜯을 수 있다)
var _tugs := 0
var _sign_root: Node3D
var _sign_shape: CollisionShape3D

var _sign: Label3D
var _power_label: Label3D
var _light: OmniLight3D
var _music: AudioStreamPlayer3D
var _speakers: Array[Node3D] = []
var _sparks: CPUParticles3D
var _spark_cd := 0.0
var _beat_t := 0.0


func _ready() -> void:
	add_to_group("soakable")
	add_to_group("incident")
	collision_layer = 2
	collision_mask = 0
	var info: Dictionary = TYPES[type]
	var color: Color = info.color

	add_to_group("illegal_shop")
	# 간판 (판 + 글씨 + 네온 테두리를 한 덩어리로: 나중에 통째로 뜯겨 떨어진다)
	_sign_root = Node3D.new()
	_sign_root.position = Vector3(0, 4.3, 0.2)
	add_child(_sign_root)
	var board := _box(Vector3(5.2, 1.5, 0.25), Vector3.ZERO, Color(0.08, 0.06, 0.1), false)
	board.reparent(_sign_root, false)
	var neon := StandardMaterial3D.new()
	neon.albedo_color = color
	neon.emission_enabled = true
	neon.emission = color
	neon.emission_energy_multiplier = 2.5
	for e in [[Vector3(5.3, 0.07, 0.07), Vector3(0, 0.78, 0.14)], [Vector3(5.3, 0.07, 0.07), Vector3(0, -0.78, 0.14)],
			[Vector3(0.07, 1.6, 0.07), Vector3(-2.65, 0, 0.14)], [Vector3(0.07, 1.6, 0.07), Vector3(2.65, 0, 0.14)]]:
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = e[0]
		sm.material = neon
		strip.mesh = sm
		strip.position = e[1]
		_sign_root.add_child(strip)
	# 벽에 박힌 쇠 브래킷 (뜯기면 남는다)
	for bx in [-2.0, 2.0]:
		_box(Vector3(0.12, 0.5, 0.35), Vector3(bx, 5.1, 0.12), Color(0.35, 0.35, 0.38), false)
	_sign_shape = CollisionShape3D.new()
	var sbs := BoxShape3D.new()
	sbs.size = Vector3(5.2, 1.5, 0.25)
	_sign_shape.shape = sbs
	_sign_shape.position = Vector3(0, 4.3, 0.2)
	add_child(_sign_shape)
	_sign = Label3D.new()
	_sign.text = info.text
	_sign.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	_sign.font_size = 110
	_sign.pixel_size = 0.0075
	_sign.modulate = color.lightened(0.3)
	_sign.outline_modulate = color
	_sign.outline_size = 24
	_sign.position = Vector3(0, 0, 0.14)
	_sign.shaded = false
	_sign_root.add_child(_sign)
	var tw := create_tween().set_loops()
	tw.tween_property(_sign, "modulate:a", 0.55, 0.12)
	tw.tween_property(_sign, "modulate:a", 1.0, 0.12)
	tw.tween_interval(randf_range(0.6, 1.6))

	_power_label = Label3D.new()
	_power_label.font = load("res://assets/fonts/Pretendard-SemiBold.otf")
	_power_label.font_size = 48
	_power_label.pixel_size = 0.006
	_power_label.outline_size = 10
	_power_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_power_label.position = Vector3(0, 5.5, 0.4)
	_power_label.modulate = Color(1, 0.9, 0.4)
	_power_label.visible = false   # 물을 맞기 시작하면 합선 % 가 보인다
	add_child(_power_label)

	# 스피커 두 개
	for sx in [-2.3, 2.3]:
		var sp := _box(Vector3(0.8, 1.2, 0.6), Vector3(sx, 0.6, 0.6), Color(0.07, 0.07, 0.08), true)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.28
		cm.bottom_radius = 0.28
		cm.height = 0.05
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.25, 0.25, 0.28)
		cm.material = cmat
		cone.mesh = cm
		cone.rotation_degrees.x = 90
		cone.position = Vector3(0, 0.1, 0.31)
		sp.add_child(cone)
		_speakers.append(sp)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 2.5
	_light.omni_range = 8.0
	_light.position = Vector3(0, 3.3, 1.6)
	add_child(_light)

	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.amount = 30
	_sparks.lifetime = 0.6
	_sparks.direction = Vector3(0, 0.5, 1)
	_sparks.spread = 70
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 5.0
	_sparks.gravity = Vector3(0, -9, 0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.04, 0.04, 0.12)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1, 0.85, 0.3)
	smat.emission_enabled = true
	smat.emission = Color(1, 0.7, 0.2)
	smat.emission_energy_multiplier = 3.0
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material = smat
	_sparks.mesh = spark_mesh
	_sparks.position = Vector3(0, 4.3, 0.5)
	_sparks.local_coords = false
	add_child(_sparks)

	_music = Sfx.loop_player_3d(info.music, self, 6.0)
	_music.unit_size = 6.0
	_music.max_distance = 45.0
	_music.position = Vector3(0, 1.5, 1.0)
	_music.play()


func _box(size: Vector3, pos: Vector3, color: Color, collide: bool) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	if collide:
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		shape.position = pos
		add_child(shape)
	return mi


func _process(delta: float) -> void:
	if done:
		return
	_spark_cd -= delta
	# 쿵쿵 (스피커가 들썩)
	_beat_t += delta * 2.2
	var pulse: float = 1.0 + 0.08 * max(sin(_beat_t * TAU), 0.0)
	for sp in _speakers:
		sp.scale = Vector3.ONE * pulse
	_light.light_energy = 2.0 + 1.0 * sin(_beat_t * TAU * 0.5)


# ---------------------------------------------------------------- 사건 인터페이스

func task() -> String:
	return "shop"


func is_active_incident() -> bool:
	return not done


func incident_pos() -> Vector3:
	return global_position + global_basis * Vector3(0, 4.3, 0.3)


func photo_task() -> String:
	return ""


func wants_water() -> bool:
	return not is_shorted


func soak(amount: float, _dir: Vector3, _knock: float) -> void:
	if is_shorted:
		return
	power -= amount
	if _spark_cd <= 0.0:
		_spark_cd = 0.35
		_sparks.restart()
		Sfx.play_at("spark", incident_pos(), -4.0, randf_range(0.9, 1.2))
	_power_label.visible = true
	var pct := int(clamp(power / need, 0.0, 1.0) * 100)
	_power_label.text = "합선까지 %d%%" % pct
	_power_label.modulate = Color(1, 0.9, 0.4).lerp(Color(1, 0.3, 0.2), 1.0 - pct / 100.0)
	if power <= 0.0:
		_short_out()


func _short_out() -> void:
	is_shorted = true
	remove_from_group("soakable")
	_sparks.amount = 80
	_sparks.restart()
	Sfx.play_at("spark", incident_pos(), 4.0, 0.7)
	Sfx.play_at("sizzle", incident_pos(), 2.0)
	_music.stop()
	_light.visible = false
	_sign.modulate = Color(0.3, 0.3, 0.3)
	_sign.outline_modulate = Color(0.1, 0.1, 0.1)
	_power_label.text = "전원 차단!\nE 연타로 간판 뜯기"
	_power_label.modulate = Color(1, 0.85, 0.3)
	for sp in _speakers:
		var t := sp.create_tween()
		t.tween_property(sp, "rotation_degrees:x", -85.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# 간판이 축 처진다
	var sag := create_tween()
	sag.tween_property(_sign_root, "rotation_degrees:z", 6.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	shorted.emit(self)


# ---------------------------------------------------------------- 간판 뜯기

func can_rip() -> bool:
	return is_shorted and not done


func rip_point() -> Vector3:
	return global_position + global_basis * Vector3(0, 0.1, 1.6)


func tug(from: Vector3) -> void:
	## E 한 번 = 한 번 잡아당김. 세 번째에 뜯긴다
	if not can_rip():
		return
	_tugs += 1
	_sparks.amount = 30
	_sparks.restart()
	Sfx.play_at("spark", incident_pos(), 0.0, randf_range(0.8, 1.1))
	Sfx.play_at("kick", incident_pos(), 2.0, 0.6 + _tugs * 0.1)
	_power_label.text = "간판 뜯기 " + "■".repeat(_tugs) + "□".repeat(TUGS - _tugs)
	var tw := create_tween()
	var ang := 6.0 + _tugs * 7.0
	tw.tween_property(_sign_root, "rotation_degrees:z", ang + 8.0, 0.06)
	tw.tween_property(_sign_root, "rotation_degrees:z", ang, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_sign_root, "position:z", 0.2 + _tugs * 0.12, 0.1)
	if _tugs >= TUGS:
		rip((global_position - from).normalized() * -1.0, false)


func on_rammed() -> void:
	## 순찰차로 들이받으면 합선 여부와 상관없이 간판이 우르르
	if done:
		return
	if not is_shorted:
		_short_out()
	rip(global_basis.z, true)


func rip(pull_dir: Vector3, rammed: bool) -> void:
	if done:
		return
	done = true
	remove_from_group("incident")
	collision_layer = 0
	_sign_shape.disabled = true
	_power_label.visible = false
	# 간판을 물리 몸체로 옮겨서 떨어뜨린다
	var body := RigidBody3D.new()
	body.mass = 40.0
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(5.2, 1.5, 0.3)
	cs.shape = bs
	body.add_child(cs)
	get_parent().add_child(body)
	body.global_transform = _sign_root.global_transform
	_sign_root.reparent(body, true)
	var out := global_basis.z
	body.apply_central_impulse((out * (6.0 if rammed else 3.0) + pull_dir * 2.0 + Vector3.UP * 2.0) * body.mass)
	body.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 60.0)
	_sparks.amount = 120
	_sparks.restart()
	Sfx.play_at("spark", incident_pos(), 6.0, 0.6)
	Sfx.play_at("sizzle", incident_pos(), 4.0)
	# 떨어져 부딪히는 소리, 셔터가 내려오고 임대문의
	var tw := create_tween()
	tw.tween_interval(0.55)
	tw.tween_callback(func():
		Sfx.play_at("thud", body.global_position, 8.0, 0.7)
		Sfx.play_at("bucket", body.global_position, 2.0, 0.6))
	tw.tween_interval(0.6)
	tw.tween_callback(_close_shutter)
	# 몇 초 뒤 간판 잔해는 치운다
	var t2 := body.create_tween()
	t2.tween_interval(12.0)
	t2.tween_property(body, "scale", Vector3.ONE * 0.01, 0.5)
	t2.tween_callback(body.queue_free)
	ripped.emit(self, rammed)
	resolved.emit(self, "shop")


func _close_shutter() -> void:
	var shutter := _box(Vector3(5.0, 3.0, 0.08), Vector3(0, 4.5, 0.32), Color(0.62, 0.64, 0.66), false)
	var tw := create_tween()
	tw.tween_property(shutter, "position:y", 1.5, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	Sfx.play_at("thud", global_position + Vector3.UP, 2.0, 0.5)
	var paper := Label3D.new()
	paper.text = "임대문의\n010-XXXX-XXXX"
	paper.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	paper.font_size = 64
	paper.pixel_size = 0.006
	paper.outline_size = 0
	paper.modulate = Color(0.15, 0.15, 0.15)
	paper.position = Vector3(0, 1.6, 0.4)
	add_child(paper)
