extends Control
## 왼쪽 아래 GTA식 미니맵. 플레이어 방향이 위로 오게 지도를 돌린다.
## 도로/블록/공원/역할 건물을 그리고, 사건(주황), 쓰레기(연두), 행인(회색), 출동 현장(파랑)을 찍는다.

var range_m := 45.0

var world: Node
var player: Node3D

const COL_BG := Color(0.16, 0.18, 0.17, 0.92)
const COL_BLOCK := Color(0.27, 0.29, 0.28)
const COL_ROAD := Color(0.55, 0.57, 0.58)
const COL_PARK := Color(0.26, 0.42, 0.26)
const COL_OUT := Color(0.05, 0.05, 0.06, 0.92)
const ROLE_COL := {"station": Color(0.35, 0.6, 1), "store": Color(0.4, 0.85, 0.4), "hospital": Color(1, 0.35, 0.35), "school": Color(1, 0.8, 0.3), "hideout": Color(1, 0.1, 0.1)}


func _ready() -> void:
	clip_contents = true


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_OUT)
	if player == null or world == null:
		return
	if world.inside != "":
		var f := get_theme_default_font()
		var t: String = world.interiors.rooms[world.inside].name
		var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(f, size / 2 + Vector2(-tw / 2, 8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.7))
		return
	var c := size / 2 + Vector2(0, size.y * 0.12)   # GTA처럼 플레이어를 조금 아래에
	var yaw := player.global_rotation.y
	var p := player.global_position
	var k := size.y / (range_m * 1.6)              # 1m 당 픽셀
	var xf := Transform2D(yaw, c) * Transform2D(0.0, Vector2(-p.x, -p.z) * k)
	draw_set_transform_matrix(xf)
	var city: CityBuilder = world.city
	var e := CityBuilder.EDGE
	var z: Rect2 = city.zone
	draw_rect(Rect2(z.position * k, z.size * k), COL_BG)
	for b in city.block_centers:
		var col := COL_PARK if b == city.park_center else COL_BLOCK
		var h := CityBuilder.BLOCK_HALF
		draw_rect(Rect2((b - Vector2(h, h)) * k, Vector2(h, h) * 2 * k), col)
	for r in [-CityBuilder.PITCH, 0.0, CityBuilder.PITCH]:
		var w := CityBuilder.ROAD_W * k
		draw_rect(Rect2(Vector2(r - CityBuilder.ROAD_W / 2, -e) * k, Vector2(w, e * 2 * k)), COL_ROAD)
		draw_rect(Rect2(Vector2(-e, r - CityBuilder.ROAD_W / 2) * k, Vector2(e * 2 * k, w)), COL_ROAD)
	# 관할 구역 경계
	draw_rect(Rect2(z.position * k, z.size * k), Color(1, 0.75, 0.2, 0.7), false, 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	for d in player.doors:
		if d.pos.y > -50.0 and ROLE_COL.has(d.role):
			_icon(xf, k, d.pos, ROLE_COL[d.role], 8.0 if d.role == "hideout" else 6.0, true, d.role == "hideout")
	for t in get_tree().get_nodes_in_group("trash"):
		_dot(xf, k, t.global_position, Color(0.6, 0.9, 0.4, 0.85), 2.5)
	for n in get_tree().get_nodes_in_group("npc"):
		if n.task() == "":
			_dot(xf, k, n.global_position, Color(0.85, 0.85, 0.85, 0.55), 2.5)
	var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01)
	for n in get_tree().get_nodes_in_group("incident"):
		if not n.is_active_incident():
			continue
		var big: bool = n is Npc and n.kind == "boss"
		_icon(xf, k, n.global_position, Color(1, 0.45, 0.2, blink), 7.5 if big else 5.0, false, true)
	if world.mission.size() > 0:
		_icon(xf, k, world.mission.pos, Color(0.3, 0.65, 1, blink), 8.0, true, true)
	# 플레이어 화살표
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(7, 7), c + Vector2(0, 3), c + Vector2(-7, 7)]), Color.WHITE)
	# 북쪽 표시
	var north := c + Vector2(0, -size.y).rotated(yaw)
	var nr := Rect2(Vector2(10, 10), size - Vector2(20, 20))
	north = Vector2(clamp(north.x, nr.position.x, nr.end.x), clamp(north.y, nr.position.y, nr.end.y))
	draw_circle(north, 8, Color(0, 0, 0, 0.7))
	draw_string(get_theme_default_font(), north + Vector2(-5, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _dot(xf: Transform2D, k: float, w: Vector3, color: Color, r: float) -> void:
	var v := xf * (Vector2(w.x, w.z) * k)
	if Rect2(Vector2.ZERO, size).has_point(v):
		draw_circle(v, r, color)


func _icon(xf: Transform2D, k: float, w: Vector3, color: Color, r: float, square := false, clamp_edge := false) -> void:
	var v := xf * (Vector2(w.x, w.z) * k)
	var inner := Rect2(Vector2(r + 2, r + 2), size - Vector2(r + 2, r + 2) * 2)
	if not inner.has_point(v):
		if not clamp_edge:
			return
		v = Vector2(clamp(v.x, inner.position.x, inner.end.x), clamp(v.y, inner.position.y, inner.end.y))
	if square:
		draw_rect(Rect2(v - Vector2(r, r), Vector2(r, r) * 2), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(v - Vector2(r - 2, r - 2), Vector2(r - 2, r - 2) * 2), color)
	else:
		draw_circle(v, r + 1.5, Color(0, 0, 0, 0.8))
		draw_circle(v, r, color)
