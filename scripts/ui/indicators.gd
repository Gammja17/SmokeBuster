extends Control
## 화면 밖에 있는 가까운 흡연자 방향을 화면 가장자리 화살표로 알려준다.

const RANGE := 40.0

var player: Node3D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rect := get_viewport_rect().grow(-60)
	var center := rect.get_center()
	for n in get_tree().get_nodes_in_group("smoker"):
		if not n.is_smoking():
			continue
		var wp: Vector3 = n.global_position + Vector3.UP * 1.8
		var dist := wp.distance_to(player.global_position)
		if dist > RANGE:
			continue
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		if not behind and rect.has_point(sp):
			continue
		var dir := (sp - center)
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		dir = dir.normalized()
		# 사각형 테두리와 만나는 점
		var t: float = min(abs(rect.size.x / 2 / dir.x) if dir.x != 0 else INF, abs(rect.size.y / 2 / dir.y) if dir.y != 0 else INF)
		var pos := center + dir * t
		var a := 1.0 - dist / RANGE * 0.6
		var col := Color(1, 0.3, 0.2, a)
		var tip := pos + dir * 16
		var side := dir.orthogonal() * 12
		draw_colored_polygon(PackedVector2Array([tip, pos - dir * 6 + side, pos - dir * 6 - side]), col)
		draw_string(get_theme_default_font(), pos - dir * 34 - Vector2(14, -6), "%dm" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 40, 18, col)
