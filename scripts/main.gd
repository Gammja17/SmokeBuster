extends Node3D
## 거리 맵(그레이박스)을 만들고 플레이어, 흡연자, HUD를 배치한다.

const PlayerScript = preload("res://scripts/player.gd")
const SmokerScript = preload("res://scripts/smoker.gd")
const HudScript = preload("res://scripts/hud.gd")

const STREET_HALF_LEN := 90.0
const ROAD_HALF_W := 3.0
const SIDEWALK_HALF_W := 6.0
const MAX_SMOKERS := 6

var player: CharacterBody3D
var hud: CanvasLayer
var score := 0
var spawn_points: Array[Vector3] = []


func _ready() -> void:
	randomize()
	_build_environment()
	_build_street()

	player = PlayerScript.new()
	player.position = Vector3(0, 1, STREET_HALF_LEN - 5)
	add_child(player)

	hud = HudScript.new()
	add_child(hud)
	player.water_changed.connect(hud.set_water)
	hud.set_water(player.water, player.WATER_MAX)
	hud.set_score(score)

	for i in MAX_SMOKERS:
		_spawn_smoker()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_street() -> void:
	var street_len := STREET_HALF_LEN * 2
	# 도로와 인도
	_make_box(Vector3(ROAD_HALF_W * 2, 0.2, street_len), Vector3(0, -0.1, 0), Color(0.22, 0.22, 0.24))
	for side in [-1, 1]:
		var sw_w := SIDEWALK_HALF_W - ROAD_HALF_W
		_make_box(Vector3(sw_w, 0.35, street_len), Vector3(side * (ROAD_HALF_W + sw_w / 2), 0.0, 0), Color(0.62, 0.6, 0.56))

	# 양쪽 건물. 블록 사이 틈이 골목이 된다.
	for side in [-1, 1]:
		var z := -STREET_HALF_LEN
		while z < STREET_HALF_LEN:
			var depth := randf_range(10.0, 18.0)
			depth = min(depth, STREET_HALF_LEN - z)
			var h := randf_range(6.0, 20.0)
			var tint := randf_range(0.45, 0.8)
			var col := Color(tint, tint * randf_range(0.85, 1.0), tint * randf_range(0.8, 1.0))
			_make_box(Vector3(10, h, depth), Vector3(side * (SIDEWALK_HALF_W + 5), h / 2, z + depth / 2), col)
			z += depth
			# 골목
			if z < STREET_HALF_LEN - 6:
				var alley_w := 3.0
				_make_box(Vector3(10, 0.3, alley_w), Vector3(side * (SIDEWALK_HALF_W + 5), 0.0, z + alley_w / 2), Color(0.35, 0.33, 0.3))
				_make_box(Vector3(0.5, 6, alley_w), Vector3(side * (SIDEWALK_HALF_W + 10), 3, z + alley_w / 2), Color(0.3, 0.3, 0.3))
				spawn_points.append(Vector3(side * (SIDEWALK_HALF_W + 6), 0.5, z + alley_w / 2))
				z += alley_w

	# 거리 양 끝 벽
	for end in [-1, 1]:
		_make_box(Vector3(SIDEWALK_HALF_W * 2, 4, 1), Vector3(0, 2, end * (STREET_HALF_LEN + 0.5)), Color(0.4, 0.4, 0.45))

	# 인도 위 스폰 지점
	for i in 20:
		var side := -1 if randf() < 0.5 else 1
		spawn_points.append(Vector3(side * randf_range(3.8, 5.5), 0.5, randf_range(-STREET_HALF_LEN + 5, STREET_HALF_LEN - 15)))


func _make_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)


func _spawn_smoker() -> void:
	var smoker := SmokerScript.new()
	smoker.player = player
	smoker.position = spawn_points.pick_random()
	smoker.rotation.y = randf() * TAU
	smoker.extinguished.connect(_on_smoker_extinguished)
	add_child(smoker)


func _on_smoker_extinguished() -> void:
	score += 1
	hud.set_score(score)
	hud.flash_message("꺼짐! +1")
	get_tree().create_timer(3.0).timeout.connect(_spawn_smoker)
