class_name DayCycle
extends Node
## 하루 시간 흐름. 해/달, 하늘, 안개, 가로등, 간판 밝기, 비를 시간에 맞춰 바꾼다.
## hour 는 0~24 를 넘어 계속 늘어날 수 있다 (새벽 2시 = 26).

signal hour_passed(hour: int)

const DAY_SKY := preload("res://assets/pbr/sky.hdr")
const NIGHT_SKY := preload("res://assets/pbr/sky_night.hdr")

var hour := 10.0
var speed := 16.0 / 720.0        # 게임 시간/실제 초 (16시간 근무 = 12분)
var running := false
var indoor := false              # 건물 안 (비 안 보이고 빗소리 작게)
var raining := false
var rain := 0.0                  # 실제 비 세기 (천천히 따라감)

var _sun: DirectionalLight3D
var _env: Environment
var _sky: PanoramaSkyMaterial
var _city: CityBuilder
var _rain_fx: GPUParticles3D
var _rain_sound: AudioStreamPlayer
var _last_hour := -1
var _night_tex := false


func setup(world: Node3D, city: CityBuilder) -> void:
	_sun = world.get_node("Sun")
	_env = world.get_node("Env").environment
	_sky = _env.sky.sky_material
	_city = city
	_build_rain(world)
	apply()


func _process(delta: float) -> void:
	if running:
		hour += delta * speed
	var h := int(hour)
	if h != _last_hour:
		if _last_hour >= 0:
			hour_passed.emit(h)
		_last_hour = h
	rain = move_toward(rain, 1.0 if raining else 0.0, delta * 0.15)
	apply()
	var cam := get_viewport().get_camera_3d()
	if cam and _rain_fx:
		_rain_fx.global_position = cam.global_position + Vector3(0, 9, 0)


func daylight() -> float:
	## 0 = 밤, 1 = 낮
	var h := fposmod(hour, 24.0)
	return smoothstep(5.5, 7.5, h) * (1.0 - smoothstep(18.0, 19.8, h))


func clock_text() -> String:
	var h := fposmod(hour, 24.0)
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60) / 10 * 10]


func apply() -> void:
	var d := daylight()
	var h := fposmod(hour, 24.0)
	# 노을: 해 지기 직전과 뜬 직후에 주황빛
	var golden := clampf(1.0 - absf(h - 18.4) / 1.4, 0.0, 1.0) + clampf(1.0 - absf(h - 6.6) / 1.0, 0.0, 1.0) * 0.6
	var wet := rain
	# 해는 낮에 동쪽에서 서쪽으로, 밤에는 같은 빛을 달빛으로 쓴다
	if d > 0.02:
		var t := clampf((h - 6.0) / 13.0, 0.0, 1.0)
		_sun.rotation_degrees = Vector3(-lerpf(8.0, 62.0, sin(t * PI)), lerpf(-110.0, 70.0, t), 0)
	else:
		_sun.rotation_degrees = Vector3(-55, 30, 0)
	var sun_col := Color(1, 0.92, 0.8).lerp(Color(1.0, 0.55, 0.3), golden * 0.8)
	_sun.light_color = Color(0.55, 0.65, 1.0).lerp(sun_col, d)
	_sun.light_energy = lerpf(0.14, 2.0, d) * lerpf(1.0, 0.45, wet)
	# 하늘: 어두워지면 밤하늘로 바꾼다 (어두울 때 바꿔서 티가 안 남)
	var want_night := d < 0.2
	if want_night != _night_tex:
		_night_tex = want_night
		_sky.panorama = NIGHT_SKY if want_night else DAY_SKY
	_sky.energy_multiplier = (lerpf(0.5, 1.0, d) if not want_night else 0.45) * lerpf(1.0, 0.55, wet)
	_env.ambient_light_energy = lerpf(0.14, 0.8, d) * lerpf(1.0, 0.8, wet)
	var fog_day := Color(0.7, 0.78, 0.9).lerp(Color(0.95, 0.7, 0.55), golden * 0.6)
	_env.fog_light_color = Color(0.1, 0.12, 0.2).lerp(fog_day, d).lerp(Color(0.45, 0.5, 0.58) * lerpf(0.3, 1.0, d), wet * 0.6)
	_env.fog_density = lerpf(0.005, 0.003, d) + wet * 0.006
	_env.volumetric_fog_albedo = Color(0.35, 0.4, 0.55).lerp(Color(0.92, 0.94, 1), d)
	_env.volumetric_fog_density = 0.006 + wet * 0.01
	_env.tonemap_exposure = lerpf(1.35, 1.05, d)
	_env.glow_intensity = lerpf(0.9, 0.55, d)
	# 간판, 창문, 가로등
	var night := 1.0 - d
	Mats.set_night(night)
	Mats.set_wet(wet)
	for l in _city.lamp_lights:
		l.light_energy = night * 2.2
	# 비
	if _rain_fx:
		_rain_fx.emitting = rain > 0.05 and not indoor
		_rain_fx.amount_ratio = clampf(rain, 0.05, 1.0)
	if _rain_sound:
		if rain > 0.02 and not _rain_sound.playing:
			_rain_sound.play()
		elif rain <= 0.02 and _rain_sound.playing:
			_rain_sound.stop()
		_rain_sound.volume_db = linear_to_db(maxf(rain, 0.001)) - (16.0 if indoor else 4.0)


func _build_rain(world: Node3D) -> void:
	## 카메라 위에서 떨어지는 빗줄기 (화면 근처만)
	_rain_fx = GPUParticles3D.new()
	_rain_fx.amount = [1500, 3000, 5000][Game.quality]
	_rain_fx.lifetime = 1.1
	_rain_fx.emitting = false
	_rain_fx.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 45, 60))
	_rain_fx.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain_fx.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 0.95, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	_rain_fx.draw_pass_1 = q
	_rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_rain_fx)
	_rain_sound = Sfx.loop_player("rain", world, -60.0)
