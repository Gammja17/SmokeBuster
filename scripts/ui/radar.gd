extends Control
## 오른쪽 위 원형 레이더. 플레이어가 위를 보도록 돌려서 사건(업무별 색), 쓰레기(연두), 행인(회색), 소화전(파랑)을 찍는다.

const RANGE := 45.0

var world: Node
var player: Node3D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var r := size.x / 2
	var c := size / 2
	draw_circle(c, r, Color(0.04, 0.08, 0.15, 0.75))
	draw_arc(c, r, 0, TAU, 48, Color(0.35, 0.7, 1, 0.9), 3.0, true)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(0.35, 0.7, 1, 0.25), 1.0, true)
	if player == null or world == null:
		return
	var yaw := player.global_rotation.y
	var p := player.global_position

	for h in world.city.hydrants:
		_dot(c, r, p, yaw, h, Color(0.3, 0.6, 1), 3.5)
	for t in get_tree().get_nodes_in_group("trash"):
		_dot(c, r, p, yaw, t.global_position, Color(0.6, 0.85, 0.4, 0.8), 2.0)
	for n in get_tree().get_nodes_in_group("npc"):
		if n.task() == "":
			_dot(c, r, p, yaw, n.global_position, Color(0.75, 0.75, 0.75, 0.5), 2.0)
	var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01)
	for n in get_tree().get_nodes_in_group("incident"):
		if not n.is_active_incident():
			continue
		var col: Color = Game.TASKS[n.task()].color
		col.a = blink
		var big: bool = n is Npc and n.kind == "boss"
		var size := 8.0 if big or n.task() in ["shop", "drunk", "bully"] else 5.0
		_dot(c, r, p, yaw, n.global_position, col, size, true)
	# 플레이어 화살표
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 6), c + Vector2(-6, 6)]), Color(1, 1, 1))


func _dot(c: Vector2, r: float, p: Vector3, yaw: float, w: Vector3, color: Color, size_px: float, clamp_edge := false) -> void:
	var d := Vector2(w.x - p.x, w.z - p.z).rotated(yaw)
	var v := d / RANGE * r
	if v.length() > r - 6:
		if not clamp_edge:
			return
		v = v.normalized() * (r - 6)
	draw_circle(c + v, size_px, color)
