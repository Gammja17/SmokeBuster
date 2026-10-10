class_name IllegalShop
extends StaticBody3D
## 건물 정면에 붙는 불법업소. 네온 간판과 스피커에 물을 뿌려 합선시키면 철거된다.
## 이 노드의 +Z 가 길 쪽을 본다.

signal resolved(shop: IllegalShop, task: String)

const TYPES := {
	"massage": {"text": "수상한 마사지", "color": Color(1, 0.3, 0.7), "music": "lounge"},
	"karaoke": {"text": "24시 노래방", "color": Color(0.7, 0.45, 1), "music": "karaoke"},
	"bar": {"text": "쿵쿵 술집", "color": Color(1, 0.6, 0.2), "music": "club"},
}

var type := "massage"
var need := 5.0
var power := 5.0
var done := false

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

	# 간판 판
	_box(Vector3(5.2, 1.5, 0.25), Vector3(0, 4.3, 0.2), Color(0.08, 0.06, 0.1), true)
	_sign = Label3D.new()
	_sign.text = info.text
	_sign.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	_sign.font_size = 110
	_sign.pixel_size = 0.0075
	_sign.modulate = color.lightened(0.3)
	_sign.outline_modulate = color
	_sign.outline_size = 24
	_sign.position = Vector3(0, 4.3, 0.34)
	_sign.shaded = false
	add_child(_sign)
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
	_power_label.text = "불법영업 · 간판에 물을 뿌려 합선!"
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
	return not done


func soak(amount: float, _dir: Vector3, _knock: float) -> void:
	if done:
		return
	power -= amount
	if _spark_cd <= 0.0:
		_spark_cd = 0.35
		_sparks.restart()
		Sfx.play_at("spark", incident_pos(), -4.0, randf_range(0.9, 1.2))
	var pct := int(clamp(power / need, 0.0, 1.0) * 100)
	_power_label.text = "합선까지 %d%%" % pct
	_power_label.modulate = Color(1, 0.9, 0.4).lerp(Color(1, 0.3, 0.2), 1.0 - pct / 100.0)
	if power <= 0.0:
		_short_out()


func _short_out() -> void:
	done = true
	remove_from_group("incident")
	remove_from_group("soakable")
	collision_layer = 0
	_sparks.amount = 80
	_sparks.restart()
	Sfx.play_at("spark", incident_pos(), 4.0, 0.7)
	Sfx.play_at("sizzle", incident_pos(), 2.0)
	_music.stop()
	_light.visible = false
	_sign.modulate = Color(0.3, 0.3, 0.3)
	_sign.outline_modulate = Color(0.1, 0.1, 0.1)
	_power_label.text = "철거 완료!"
	_power_label.modulate = Color(0.5, 1, 0.5)
	for sp in _speakers:
		var t := sp.create_tween()
		t.tween_property(sp, "rotation_degrees:x", -85.0, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	resolved.emit(self, "shop")
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func():
		_sign.text = "임대문의"
		_sign.modulate = Color(0.95, 0.95, 0.95)
		_sign.outline_modulate = Color(0.2, 0.2, 0.2)
		_power_label.visible = false)
