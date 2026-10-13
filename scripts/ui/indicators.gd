extends Control
## 화면 밖에 있는 가까운 사건 방향을 화면 가장자리 화살표로 알려준다.
## 담배 피우는 사람은 화살표/지도에 안 나온다. 가까이(SMELL) 가면 그쪽에서 냄새가 풍긴다.

const RANGE := 40.0
const SMELL := 15.0

var player: Node3D
var _smelled := {}        # 냄새 알림을 이미 띄운 흡연자
var _smell_msg_t := 0.0


static func known(n: Node) -> bool:
	## 직접 봤거나(발견) 누가 알려 준 사건만 지도/화살표에 나온다. 골초왕은 처음부터
	return n.has_meta("seen") or (n is Npc and n.kind == "boss")


static func hidden_smoker(n: Node) -> bool:
	## 냄새로 찾아야 하는 사람 (골초왕은 워낙 커서 지도에 나온다)
	return n is Npc and n.kind != "boss" and n.has_cigarette()


func _process(delta: float) -> void:
	_smell_msg_t -= delta
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
		_draw_mission(w, cam, rect, center)
	_draw_smell(cam, rect, center)
	_draw_car(w, cam, rect, center)
	for n in get_tree().get_nodes_in_group("incident"):
		if not n.is_active_incident() or hidden_smoker(n) or not known(n):
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
		var pos := _avoid_hud(center + dir * t)
		var a := 1.0 - dist / RANGE * 0.6
		var col := Color(1, 0.55, 0.25, a)
		var tip := pos + dir * 16
		var side := dir.orthogonal() * 12
		draw_colored_polygon(PackedVector2Array([tip, pos - dir * 6 + side, pos - dir * 6 - side]), col)
		draw_string(get_theme_default_font(), pos - dir * 40 - Vector2(45, -6), "%dm" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 90, 16, col)


func _draw_smell(cam: Camera3D, rect: Rect2, center: Vector2) -> void:
	## 가장 가까운 흡연자 쪽 화면 가장자리에 담배 연기가 스멀스멀 (가까울수록 진하게)
	var best: Node3D = null
	var bd := SMELL
	for n in get_tree().get_nodes_in_group("npc"):
		if not hidden_smoker(n):
			continue
		var d: float = n.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = n
	if best == null:
		return
	var id := best.get_instance_id()
	if not _smelled.has(id):
		_smelled[id] = true
		_smell_msg_t = 2.4
	var strength := 1.0 - bd / SMELL
	var wp: Vector3 = best.global_position + Vector3.UP * 1.5
	var sp := cam.unproject_position(wp)
	var behind := cam.is_position_behind(wp)
	var dir := sp - center
	if behind:
		dir = -dir
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.UP
	var on_screen := not behind and rect.has_point(sp)
	var t: float = min(abs(rect.size.x / 2 / dir.x) if dir.x != 0 else INF, abs(rect.size.y / 2 / dir.y) if dir.y != 0 else INF)
	var edge := center + dir * (t + 40.0)
	var now := Time.get_ticks_msec() * 0.001
	var a := (0.2 if on_screen else 0.5) * (0.4 + strength)
	for k in 9:
		var ph := now * 0.6 + k * 0.7
		var drift := fmod(ph, 1.0)
		var p := edge - dir * (drift * 150.0) + dir.orthogonal() * sin(ph * 2.3 + k) * 50.0
		draw_circle(p, 34.0 + drift * 46.0, Color(0.72, 0.66, 0.52, a * (1.0 - drift)))
	if _smell_msg_t > 0.0:
		var f := get_theme_default_font()
		var msg := "어우, 담배 냄새..." if strength < 0.6 else "냄새 진하다... 이 근처다!"
		var w := f.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var c := Color(0.95, 0.9, 0.78, clampf(_smell_msg_t, 0.0, 1.0))
		draw_string_outline(f, center + Vector2(-w / 2, 120), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, c.a * 0.7))
		draw_string(f, center + Vector2(-w / 2, 120), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c)


func my_car(w: Node) -> Node3D:
	## 마지막에 탄 차, 없으면 순찰차
	if w == null or not "last_vehicle" in w:
		return null
	if is_instance_valid(w.last_vehicle):
		return w.last_vehicle
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v.kind == "police":
			return v
	return null


func _draw_car(w: Node, cam: Camera3D, rect: Rect2, center: Vector2) -> void:
	## 차에서 내려 멀어지면 "내 차" 위치 (화면 안이면 차 위에, 밖이면 가장자리)
	if w.vehicle != null or w.inside != "":
		return
	var car := my_car(w)
	if car == null:
		return
	var wp: Vector3 = car.global_position + Vector3.UP * 3.0
	var dist := wp.distance_to(player.global_position)
	if dist < 15.0:
		return
	var col := Color(0.55, 0.85, 1.0, 0.9)
	var f := get_theme_default_font()
	var sp := cam.unproject_position(wp)
	var behind := cam.is_position_behind(wp)
	var label := "내 차 %dm" % int(dist)
	if not behind and rect.has_point(sp):
		draw_circle(sp, 7, Color(0, 0, 0, 0.6))
		draw_circle(sp, 5, col)
		draw_string_outline(f, sp + Vector2(-40, -14), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 15, 5, Color(0, 0, 0, 0.7))
		draw_string(f, sp + Vector2(-40, -14), label, HORIZONTAL_ALIGNMENT_CENTER, 80, 15, col)
		return
	var dir := sp - center
	if behind:
		dir = -dir
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.DOWN
	var t: float = min(abs(rect.size.x / 2 / dir.x) if dir.x != 0 else INF, abs(rect.size.y / 2 / dir.y) if dir.y != 0 else INF)
	var pos := _avoid_hud(center + dir * t)
	draw_rect(Rect2(pos - Vector2(9, 9), Vector2(18, 18)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(pos - Vector2(7, 7), Vector2(14, 14)), col)
	draw_string(f, pos - dir * 44 - Vector2(45, -6), label, HORIZONTAL_ALIGNMENT_CENTER, 90, 16, col)


func _draw_mission(w: Node, cam: Camera3D, rect: Rect2, center: Vector2) -> void:
	## 출동 현장: 화면 안이면 현장 위에 큰 표식, 밖이면 가장자리에 크게 깜빡이는 화살표
	var mp: Vector3 = w.mission.pos + Vector3.UP * 2.2
	var dist := int(mp.distance_to(player.global_position))
	var f := get_theme_default_font()
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.008)
	var col := Color(0.3, 0.7, 1.0, pulse)
	var dark := Color(0, 0.05, 0.15, 0.85)
	var sp := cam.unproject_position(mp)
	var behind := cam.is_position_behind(mp)
	if not behind and rect.has_point(sp):
		var d := PackedVector2Array([sp + Vector2(0, -20), sp + Vector2(16, 0), sp + Vector2(0, 20), sp + Vector2(-16, 0)])
		draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -25), sp + Vector2(21, 0), sp + Vector2(0, 25), sp + Vector2(-21, 0)]), dark)
		draw_colored_polygon(d, col)
		var t := "출동 %dm" % dist
		draw_string_outline(f, sp + Vector2(-60, -34), t, HORIZONTAL_ALIGNMENT_CENTER, 120, 20, 7, dark)
		draw_string(f, sp + Vector2(-60, -34), t, HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color(0.6, 0.85, 1))
		return
	var dir := sp - center
	if behind:
		dir = -dir
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.DOWN
	var t2: float = min(abs(rect.size.x / 2 / dir.x) if dir.x != 0 else INF, abs(rect.size.y / 2 / dir.y) if dir.y != 0 else INF)
	var pos := _avoid_hud(center + dir * t2)
	var o := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([pos + dir * 40, pos - dir * 14 + o * 30, pos - dir * 14 - o * 30]), dark)
	draw_colored_polygon(PackedVector2Array([pos + dir * 32, pos - dir * 8 + o * 23, pos - dir * 8 - o * 23]), col)
	var lbl := "출동 %dm" % dist
	draw_string_outline(f, pos - dir * 62 - Vector2(60, -8), lbl, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, 7, dark)
	draw_string(f, pos - dir * 62 - Vector2(60, -8), lbl, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(0.6, 0.85, 1))


func _avoid_hud(pos: Vector2) -> Vector2:
	## 왼쪽 아래 미니맵, 왼쪽 위 단말기와 겹치면 비켜 그린다
	var vs := get_viewport_rect().size
	if pos.x < 360.0 and pos.y > vs.y - 270.0:
		pos.y = vs.y - 270.0
	if pos.x < 420.0 and pos.y < 300.0:
		pos.x = 420.0
	return pos
