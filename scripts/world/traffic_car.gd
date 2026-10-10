class_name TrafficCar
extends AnimatableBody3D
## 바깥 순환 도로를 도는 차. 앞에 플레이어가 있으면 멈추고 빵빵.

const MODELS := ["sedan", "taxi", "suv", "van", "police", "delivery", "hatchback-sports", "garbage-truck"]

var half := 51.5
var clockwise := true
var player: Node3D
var speed := 9.0

var _corners: Array[Vector3] = []
var _next := 0
var _cur_speed := 0.0
var _honk_cd := 0.0


func setup(p_half: float, p_clockwise: bool, start_index: int, p_player: Node3D) -> void:
	half = p_half
	clockwise = p_clockwise
	player = p_player
	var c := [Vector3(-half, 0.02, -half), Vector3(half, 0.02, -half), Vector3(half, 0.02, half), Vector3(-half, 0.02, half)]
	if not clockwise:
		c.reverse()
	for p in c:
		_corners.append(p)
	var a := _corners[start_index % 4]
	var b := _corners[(start_index + 1) % 4]
	position = a.lerp(b, randf_range(0.1, 0.8))
	_next = (start_index + 1) % 4
	speed = randf_range(8.0, 11.0)


func _ready() -> void:
	sync_to_physics = false
	var m: Node3D = load("res://assets/cars/%s.glb" % MODELS.pick_random()).instantiate()
	m.scale = Vector3.ONE * 1.6
	m.rotation.y = PI
	add_child(m)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.0, 4.6)
	col.shape = box
	col.position.y = 1.0
	add_child(col)
	var target := _corners[_next]
	look_at(Vector3(target.x, position.y, target.z), Vector3.UP)


func _physics_process(delta: float) -> void:
	_honk_cd -= delta
	var target := _corners[_next]
	var to := target - global_position
	to.y = 0
	if to.length() < 0.5:
		_next = (_next + 1) % 4
		return
	var dir := to.normalized()
	var want := speed
	if player:
		var rel := player.global_position - global_position
		var ahead := rel.dot(dir)
		var lateral := (rel - dir * ahead).length()
		if ahead > 0.0 and ahead < 8.0 and lateral < 2.0:
			want = 0.0
			if _honk_cd <= 0.0:
				_honk_cd = 3.0
				Sfx.play_at("horn", global_position, -2.0)
	_cur_speed = move_toward(_cur_speed, want, 14.0 * delta)
	global_position += dir * min(_cur_speed * delta, to.length())
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, 6.0 * delta)
