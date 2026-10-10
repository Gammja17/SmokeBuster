class_name FireTruck
extends Node3D
## 소방차 호출. 플레이어와 가까운 도로를 따라 끝에서 끝까지 달리며 양옆으로 물대포를 쏜다.

const SPEED := 14.0
const REACH := 13.0

var water: WaterSystem
var player: Node3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _len := 1.0
var _spray_t := 0.0
var _cannons: Array[Node3D] = []
var _siren: AudioStreamPlayer3D


func launch(along_x: bool, line: float, lane: float) -> void:
	var e := CityBuilder.EDGE + 4.0
	if along_x:
		_from = Vector3(-e, 0.02, line + lane)
		_to = Vector3(e, 0.02, line + lane)
	else:
		_from = Vector3(line + lane, 0.02, -e)
		_to = Vector3(line + lane, 0.02, e)
	if randf() < 0.5:
		var tmp := _from
		_from = _to
		_to = tmp
	_len = _from.distance_to(_to)
	global_position = _from
	look_at(_to, Vector3.UP)


func _ready() -> void:
	var m: Node3D = load("res://assets/cars/firetruck.glb").instantiate()
	m.scale = Vector3.ONE * 2.2
	m.rotation.y = PI
	add_child(m)
	for s in [-1, 1]:
		var c := Node3D.new()
		c.position = Vector3(s * 0.9, 3.6, 0.5)
		add_child(c)
		_cannons.append(c)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.15, 0.1)
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.position = Vector3(0, 4.5, -2.0)
	add_child(light)
	var tw := create_tween().set_loops()
	tw.tween_property(light, "light_color", Color(0.2, 0.3, 1), 0.25)
	tw.tween_property(light, "light_color", Color(1, 0.15, 0.1), 0.25)
	_siren = Sfx.loop_player_3d("siren", self, 4.0)
	_siren.play()
	Sfx.play("horn", 0.0)


func _physics_process(delta: float) -> void:
	_t += SPEED * delta
	if _t >= _len:
		queue_free()
		return
	global_position = _from.lerp(_to, _t / _len)
	if player and global_position.distance_to(player.global_position) < 3.5:
		player.take_hit(0, global_position)

	_spray_t += delta
	if _spray_t < 0.03:
		return
	_spray_t = 0.0
	var targets: Array = []
	for n in get_tree().get_nodes_in_group("smoker"):
		if n.is_smoking() and n.global_position.distance_to(global_position) < REACH:
			targets.append(n)
	for c in _cannons:
		var muzzle := c.global_position
		var aim: Vector3
		var side := (c.global_position - global_position)
		side.y = 0
		side = side.normalized()
		var best: Node3D = null
		for n in targets:
			if (n.global_position - global_position).dot(side) > 0:
				best = n
				break
		if best:
			aim = best.global_position + Vector3.UP * 1.2
		else:
			aim = global_position + side * 10.0 + global_basis.z * sin(Time.get_ticks_msec() * 0.004) * 4.0
		var to := aim - muzzle
		var flat := Vector3(to.x, 0, to.z)
		var t: float = max(flat.length() / 18.0, 0.2)
		var v := flat / t
		v.y = (to.y + 0.5 * 10.0 * t * t) / t
		water.spawn(muzzle, v, 0.12, 2.0, 10.0, 0.0, 0.16)
