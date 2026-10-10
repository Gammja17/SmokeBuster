extends CharacterBody3D
## 흡연자. 물을 충분히 맞으면 담배가 꺼지고 플레이어 반대쪽으로 도망친 뒤 사라진다.

signal extinguished

const FLEE_SPEED := 6.0
const FLEE_TIME := 4.0

var player: Node3D
var wetness := 0.0
var fleeing := false
var smoke: CPUParticles3D
var body_mat: StandardMaterial3D
var flee_dir := Vector3.ZERO


func _ready() -> void:
	add_to_group("smokers")

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	col.shape = capsule
	col.position.y = 0.9
	add_child(col)

	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = Color.from_hsv(randf(), 0.5, 0.7)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 1.3
	body_mesh.material = body_mat
	body.mesh = body_mesh
	body.position.y = 0.7
	add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.2
	head_mesh.height = 0.4
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.95, 0.8, 0.65)
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position.y = 1.55
	add_child(head)

	# 입에 문 담배와 연기
	var cig := MeshInstance3D.new()
	var cig_mesh := BoxMesh.new()
	cig_mesh.size = Vector3(0.02, 0.02, 0.12)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color.WHITE
	cig_mesh.material = white
	cig.mesh = cig_mesh
	cig.position = Vector3(0.05, 1.5, -0.24)
	add_child(cig)

	smoke = CPUParticles3D.new()
	smoke.amount = 24
	smoke.lifetime = 2.0
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.spread = 15
	smoke.initial_velocity_min = 0.3
	smoke.initial_velocity_max = 0.6
	smoke.gravity = Vector3(0, 0.2, 0)
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.5
	var puff := SphereMesh.new()
	puff.radius = 0.06
	puff.height = 0.12
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.75, 0.75, 0.75, 0.5)
	grey.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = grey
	smoke.mesh = puff
	smoke.position = Vector3(0.05, 1.5, -0.31)
	add_child(smoke)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	if fleeing:
		velocity.x = flee_dir.x * FLEE_SPEED
		velocity.z = flee_dir.z * FLEE_SPEED
	else:
		velocity.x = 0
		velocity.z = 0
	move_and_slide()


func soak(amount: float) -> void:
	if fleeing:
		return
	wetness += amount
	# 젖을수록 파랗게
	body_mat.albedo_color = body_mat.albedo_color.lerp(Color(0.3, 0.5, 0.9), amount)
	if wetness >= 1.0:
		_extinguish()


func _extinguish() -> void:
	fleeing = true
	remove_from_group("smokers")
	smoke.emitting = false
	flee_dir = global_position - player.global_position
	flee_dir.y = 0
	flee_dir = flee_dir.normalized() if flee_dir.length() > 0.01 else Vector3.FORWARD
	look_at(global_position + flee_dir, Vector3.UP)
	extinguished.emit()
	await get_tree().create_timer(FLEE_TIME).timeout
	queue_free()
