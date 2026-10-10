extends CharacterBody3D
## 1인칭 이동과 분무기. 좌클릭 분사, R 리필, Esc 마우스 풀기.

signal water_changed(current: float, maximum: float)

const SPEED := 5.0
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0025
const WATER_MAX := 100.0
const WATER_DRAIN := 20.0       # 초당 소모
const REFILL_TIME := 1.5
const SPRAY_RANGE := 4.0
const SPRAY_ANGLE_DEG := 12.0
const SOAK_PER_SEC := 1.0        # 흡연자 1명 끄는 데 약 1초

var water := WATER_MAX
var refilling := false
var camera: Camera3D
var spray: CPUParticles3D


func _ready() -> void:
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)

	camera = Camera3D.new()
	camera.position.y = 1.6
	camera.fov = 80
	add_child(camera)

	_build_spray_bottle()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_spray_bottle() -> void:
	# 화면 오른쪽 아래에 보이는 분무기
	var bottle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.05
	cyl.height = 0.22
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.6, 1.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = mat
	bottle.mesh = cyl
	bottle.position = Vector3(0.25, -0.22, -0.45)
	camera.add_child(bottle)

	spray = CPUParticles3D.new()
	spray.emitting = false
	spray.amount = 120
	spray.lifetime = 0.5
	spray.local_coords = false
	spray.direction = Vector3(0, 0, -1)
	spray.spread = SPRAY_ANGLE_DEG * 0.6
	spray.initial_velocity_min = 7.0
	spray.initial_velocity_max = 9.0
	spray.gravity = Vector3(0, -6, 0)
	var drop := SphereMesh.new()
	drop.radius = 0.025
	drop.height = 0.05
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.6, 0.85, 1.0, 0.8)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = drop_mat
	spray.mesh = drop
	spray.position = Vector3(0.22, -0.12, -0.6)
	camera.add_child(spray)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_R:
			_refill()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input.y -= 1
	if Input.is_key_pressed(KEY_S): input.y += 1
	if Input.is_key_pressed(KEY_A): input.x -= 1
	if Input.is_key_pressed(KEY_D): input.x += 1
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	move_and_slide()

	_update_spray(delta)


func _update_spray(delta: float) -> void:
	var wants := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var spraying := wants and water > 0.0 and not refilling
	spray.emitting = spraying
	if not spraying:
		return

	water = max(water - WATER_DRAIN * delta, 0.0)
	water_changed.emit(water, WATER_MAX)

	var origin := camera.global_position
	var forward := -camera.global_basis.z
	for smoker in get_tree().get_nodes_in_group("smokers"):
		var target: Vector3 = smoker.global_position + Vector3(0, 1.4, 0)
		var to_target := target - origin
		if to_target.length() > SPRAY_RANGE:
			continue
		if rad_to_deg(forward.angle_to(to_target)) > SPRAY_ANGLE_DEG:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, target, 0xFFFFFFFF, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider == smoker:
			smoker.soak(SOAK_PER_SEC * delta)


func _refill() -> void:
	if refilling or water >= WATER_MAX:
		return
	refilling = true
	await get_tree().create_timer(REFILL_TIME).timeout
	water = WATER_MAX
	refilling = false
	water_changed.emit(water, WATER_MAX)
