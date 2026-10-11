extends Node
## 메인 메뉴. VARCO 로 뽑은 밤거리 그림 위에 큰 제목과 메뉴 목록.
## 고른 줄은 양옆 괄호와 윗줄로 감싼다. ↑↓/W S 로 고르고 Enter, 마우스로 눌러도 된다.

const BG := "res://assets/ui/menu_bg.png"

@onready var _ui: CanvasLayer = $UI
@onready var _bg: TextureRect = $UI/BG
@onready var _menu: VBoxContainer = $UI/Center/MenuBox/Menu
@onready var _selector: Control = $UI/Center/MenuBox/Selector
@onready var _howto: PanelContainer = $UI/HowToPanel

var _items: Array[Label] = []
var _sel := 0
var _sel_tw: Tween


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ResourceLoader.exists(BG):
		_bg.texture = load(BG)
	var save_label: Label = $UI/Center/Save
	var cont: Label = _menu.get_node("Continue")
	if Game.has_save():
		save_label.text = "저장된 순찰: %s · ₩%d" % [Game.rank_name(), Game.money]
	else:
		save_label.text = " "
		cont.visible = false
	for c in _menu.get_children():
		if c.visible:
			_items.append(c)
	for i in _items.size():
		_items[i].mouse_entered.connect(_select.bind(i))
		_items[i].gui_input.connect(_on_item_input.bind(i))
	_selector.draw.connect(_draw_selector)
	_select.call_deferred(0, false)
	Sfx.music(true)
	# 배경을 아주 천천히 밀고 당긴다
	_bg.pivot_offset = _bg.size / 2
	var tw := create_tween().set_loops()
	tw.tween_property(_bg, "scale", Vector2.ONE * 1.06, 14.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_bg, "scale", Vector2.ONE, 14.0).set_trans(Tween.TRANS_SINE)


func _select(i: int, sound := true) -> void:
	if _howto.visible:
		return
	if sound and i != _sel:
		Sfx.play("select", -12.0)
	_sel = i
	for j in _items.size():
		_items[j].add_theme_color_override("font_color", Color.WHITE if j == i else Color(1, 1, 1, 0.62))
	var target := _items[i].position.y
	if _sel_tw:
		_sel_tw.kill()
	if not sound:
		_selector.position.y = target
	else:
		_sel_tw = create_tween()
		_sel_tw.tween_property(_selector, "position:y", target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_selector.queue_redraw()


func _draw_selector() -> void:
	## [: 고른 줄 :]  과 그 위의 가는 선
	var w := _selector.size.x
	var h := _selector.size.y
	var col := Color(1, 1, 1, 0.9)
	_selector.draw_line(Vector2(14, 1), Vector2(w - 14, 1), Color(1, 1, 1, 0.55), 1.5)
	for x in [0.0, w - 4.0]:
		_selector.draw_rect(Rect2(x, 4, 4, h - 8), col)
		var dx: float = 8.0 if x == 0.0 else -6.0
		_selector.draw_rect(Rect2(x + dx, 10, 2, 4), col)
		_selector.draw_rect(Rect2(x + dx, h - 14, 2, 4), col)


func _on_item_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(i, false)
		_activate()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if _howto.visible:
		if k in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_howto.visible = false
			Sfx.play("click")
		return
	if k in [KEY_UP, KEY_W]:
		_select((_sel - 1 + _items.size()) % _items.size())
	elif k in [KEY_DOWN, KEY_S]:
		_select((_sel + 1) % _items.size())
	elif k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_activate()


func _activate() -> void:
	Sfx.play("click")
	match _items[_sel].name:
		"Continue":
			_start(false)
		"New":
			_start(true)
		"HowTo":
			_howto.visible = true
		"Quit":
			get_tree().quit()


func _start(fresh: bool) -> void:
	if fresh:
		Game.new_game()
	get_tree().change_scene_to_file("res://scenes/world.tscn")
