extends Control
## GTA식 무기 휠. Tab 을 누르고 있으면 열리고(시간이 느려짐), 마우스를 미는 쪽 칸이 골라지고, 떼면 장착.

var player: Node3D
var selected := ""
var _aim := Vector2.ZERO

@onready var _stats: PanelContainer = $Stats
@onready var _bars := {"power": $Stats/V/Power/Bar, "rate": $Stats/V/Rate/Bar, "range": $Stats/V/Range/Bar, "tank": $Stats/V/Tank/Bar}

const R_OUT := 250.0
const R_IN := 120.0


func _ready() -> void:
	add_to_group("weapon_wheel")
	visible = false


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func open() -> void:
	selected = player.current
	var i: int = Game.WEAPON_ORDER.find(selected)
	_aim = Vector2.from_angle(_seg_angle(i)) * 60.0
	visible = true
	Engine.time_scale = 0.3
	Sfx.play("select", -10.0)
	_update_stats()


func close() -> String:
	visible = false
	Engine.time_scale = 1.0
	return selected


func feed(relative: Vector2) -> void:
	## 마우스 움직임을 모아서 그 방향의 칸을 고른다
	_aim = (_aim + relative).limit_length(80.0)
	if _aim.length() < 25.0:
		return
	var n: int = Game.WEAPON_ORDER.size()
	var a := fposmod(_aim.angle() + PI / 2 + PI / n, TAU)
	var id: String = Game.WEAPON_ORDER[int(a / (TAU / n)) % n]
	if id in Game.owned and id != selected:
		selected = id
		Sfx.play("select", -14.0, 1.3)
		_update_stats()


func _seg_angle(i: int) -> float:
	## i번 칸 가운데 각도 (0번이 맨 위, 시계 방향)
	return -PI / 2 + i * TAU / Game.WEAPON_ORDER.size()


func _process(_delta: float) -> void:
	if visible:
		if player == null or not player.input_enabled or get_tree().paused:
			close()
			return
		# Tab 뗌을 다른 곳(GUI 포커스 이동 등)이 먹어도 여기서 마무리한다
		if not Input.is_key_pressed(KEY_TAB) and not Input.is_physical_key_pressed(KEY_TAB):
			var id := close()
			if id != player.current and id in Game.owned:
				player.equip(id)
			return
		queue_redraw()


func _draw() -> void:
	var c := size / 2
	var n: int = Game.WEAPON_ORDER.size()
	var span := TAU / n
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	for i in n:
		var id: String = Game.WEAPON_ORDER[i]
		var a0 := _seg_angle(i) - span / 2
		var owned := id in Game.owned
		var col := Color(0.12, 0.12, 0.13, 0.82)
		if id == selected:
			col = Color(0.55, 0.57, 0.6, 0.85)
		_ring(c, R_IN, R_OUT, a0 + 0.012, a0 + span - 0.012, col)
		if id == selected:
			_ring(c, R_OUT - 6, R_OUT, a0 + 0.012, a0 + span - 0.012, Color(1, 0.831, 0, 1))
		var mid := c + Vector2.from_angle(a0 + span / 2) * (R_IN + R_OUT) / 2
		var w: Dictionary = Game.WEAPONS[id]
		var name_col := Color.WHITE if owned else Color(1, 1, 1, 0.3)
		_text(font, mid + Vector2(0, -6), w.name if owned else "잠김", 24, name_col)
		if owned:
			var cur: float = player.ammo.get(id, 0.0)
			var mx: float = Game.weapon_stat(id, "tank")
			_text(font, mid + Vector2(0, 24), "%d / %d" % [int(ceil(cur)), int(mx)], 17, Color(1, 1, 1, 0.75))
		else:
			_text(font, mid + Vector2(0, 24), "%d원" % w.price, 17, Color(1, 1, 1, 0.3))
	if selected != "":
		_text(font, c + Vector2(0, -14), Game.WEAPONS[selected].name, 30, Color.WHITE)




func _ring(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 24
	for s in steps + 1:
		pts.append(c + Vector2.from_angle(lerp(a0, a1, float(s) / steps)) * r1)
	for s in range(steps, -1, -1):
		pts.append(c + Vector2.from_angle(lerp(a0, a1, float(s) / steps)) * r0)
	draw_colored_polygon(pts, col)


func _text(font: Font, at: Vector2, s: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w / 2, -fs * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _update_stats() -> void:
	## 오른쪽 위 무기 능력치 (GTA 의 Damage / Fire Rate / Accuracy / Range 자리)
	var id := selected
	var soak: float = Game.weapon_stat(id, "soak") * Game.WEAPONS[id].drops / Game.WEAPONS[id].interval
	_bars.power.value = clamp(soak / 5.5, 0.05, 1.0) if Game.WEAPONS[id].mode != "throw" else 0.85
	_bars.rate.value = clamp(0.05 / Game.WEAPONS[id].interval, 0.05, 1.0)
	_bars.range.value = clamp(Game.WEAPONS[id].speed / 30.0, 0.05, 1.0)
	_bars.tank.value = clamp(Game.weapon_stat(id, "tank") / 400.0, 0.05, 1.0)
