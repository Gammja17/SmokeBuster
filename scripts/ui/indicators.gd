extends Control
## 화면 밖에 있는 가까운 사건 방향을 화면 가장자리 화살표로 알려준다.

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
	var w = player.get_parent()
	if w and "mission" in w and w.mission.size() > 0:
		var mp: Vector3 = w.mission.pos + Vector3.UP * 2.0
		if cam.is_position_behind(mp) or not rect.has_point(cam.unproject_position(mp)):
			var sp := cam.unproject_position(mp)
			var dir := (sp - center)
			if cam.is_position_behind(mp):
				dir = -dir
			dir = dir.normalized() if dir.length() > 1.0 else Vector2.DOWN
			var t: float = min(abs(rect.size.x / 2 / dir.x) if dir.x != 0 else INF, abs(rect.size.y / 2 / dir.y) if dir.y != 0 else INF)
			var pos := center + dir * t
			var col := Color(0.35, 0.7, 1)
			draw_colored_polygon(PackedVector2Array([pos + dir * 22, pos - dir * 8 + dir.orthogonal() * 16, pos - dir * 8 - dir.orthogonal() * 16]), col)
			draw_string(get_theme_default_font(), pos - dir * 50 - Vector2(55, -6), "출동 %dm" % int(mp.distance_to(player.global_position)), HORIZONTAL_ALIGNMENT_CENTER, 110, 20, col)
	for n in get_tree().get_nodes_in_group("incident"):
		if not n.is_active_incident():
			continue
		var wp: Vector3 = n.incident_pos()
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
		var col := Color(1, 0.55, 0.25, a)
		var tip := pos + dir * 16
		var side := dir.orthogonal() * 12
		draw_colored_polygon(PackedVector2Array([tip, pos - dir * 6 + side, pos - dir * 6 - side]), col)
		draw_string(get_theme_default_font(), pos - dir * 40 - Vector2(45, -6), "! %dm" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 90, 16, col)
