extends CanvasLayer
## 물대포폰 (GTA 폰처럼). B 로 꺼내고 B/Esc 로 넣는다. 배치는 ui/phone.tscn.
## 폴리스몰(장비·강화), 연락처(상황실/정비 담당/소장님/신입에게 전화), 오늘 할 일, 사진첩.

signal closed
signal shop_requested

var world: Node

@onready var _time: Label = $Body/Screen/V/Status/Time
@onready var _money: Label = $Body/Screen/V/Status/Money
@onready var _title: Label = $Body/Screen/V/Title
@onready var _home: GridContainer = $Body/Screen/V/Home
@onready var _page: ScrollContainer = $Body/Screen/V/Page
@onready var _list: VBoxContainer = $Body/Screen/V/Page/List
@onready var _grid: GridContainer = $Body/Screen/V/Page/List/Grid
@onready var _body: Control = $Body


func _ready() -> void:
	$Body/Screen/V/Home/Mall.pressed.connect(func():
		Sfx.play("click")
		shop_requested.emit())
	$Body/Screen/V/Home/Contacts.pressed.connect(_contacts)
	$Body/Screen/V/Home/Memo.pressed.connect(_memo)
	$Body/Screen/V/Home/Photos.pressed.connect(_photos)
	$Body/Screen/V/Bottom/HomeBtn.pressed.connect(_show_home)
	$Body/Screen/V/Bottom/CloseBtn.pressed.connect(close)


func open() -> void:
	visible = true
	_show_home()
	_time.text = world.day.clock_text()
	_money.text = "₩%d" % Game.money
	Sfx.play("select", -6.0, 1.3)
	var y := _body.position.y
	_body.position.y = y + 500.0
	create_tween().tween_property(_body, "position:y", y, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	visible = false
	Sfx.play("click", -6.0, 0.8)
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_B]:
		get_viewport().set_input_as_handled()
		close()


func _show_home() -> void:
	_title.text = "물대포폰"
	_home.visible = true
	_page.visible = false


func _open_page(title: String) -> void:
	_title.text = title
	_home.visible = false
	_page.visible = true
	for c in _list.get_children():
		if c != _grid:
			c.queue_free()
	for c in _grid.get_children():
		c.queue_free()
	Sfx.play("select", -10.0)


func _row(text: String, fn := Callable()) -> Button:
	var b: Button = $RowTemplate.duplicate()
	b.visible = true
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	if fn.is_valid():
		b.pressed.connect(fn)
	else:
		b.disabled = true
	_list.add_child(b)
	return b


func _text(text: String, color := Color(0.85, 0.88, 0.92)) -> Label:
	var l: Label = $TextTemplate.duplicate()
	l.visible = true
	l.text = text
	l.add_theme_color_override("font_color", color)
	_list.add_child(l)
	return l


# ---------------------------------------------------------------- 앱

func _contacts() -> void:
	_open_page("연락처")
	for c in [["ops", "상황실 — 출동 하나 주세요"], ["mech", "정비 담당 — 내 차 여기로 (₩50)"],
			["chief", "소장님 — 오늘 지시 다시 듣기"], ["rookie", "신입 순경 — 같이 가자 / 들어가 있어"]]:
		_row(c[1], _call.bind(c[0]))


func _call(who: String) -> void:
	## 전화 걸면 대답이 화면에 뜨고 무전으로도 들린다
	var reply: Array = world.phone_call(who)
	_text(reply[0] + ": " + reply[1], Color(1, 0.9, 0.55))
	_money.text = "₩%d" % Game.money
	Sfx.play("radio", -6.0)


func _memo() -> void:
	_open_page("오늘 할 일")
	var sh = world.shift
	_text(sh.quota_text())
	if not sh.order.is_empty():
		_text(sh.order_text(), Color(1, 0.831, 0) if not sh.order_cleared else Color(0.5, 1, 0.6))
	var any := false
	for role in Talks.FAVORS:
		var st: String = world.favor_status(role)
		if st == "active":
			_text("부탁 · %s  %s" % [Coworker.DATA[role].name, world.favor_progress(role)], Color(0.6, 0.9, 1))
			any = true
		elif st == "done":
			_text("부탁 · %s  완료!" % Coworker.DATA[role].name, Color(0.5, 1, 0.6))
			any = true
	if not any:
		_text("맡은 부탁 없음. 노란 표시 있는 동네 사람한테 말 걸어 봐요.", Color(0.65, 0.7, 0.75))
	if world.mission.size() > 0:
		_text("출동 중 · %s (%s)" % [world.mission.title, world.mission.place], Color(0.6, 0.85, 1))


func _photos() -> void:
	_open_page("사진첩")
	if world.photos.is_empty():
		_text("아직 찍은 사진이 없어요. [우클릭] 카메라로 단속 현장을 찍어 봐요.", Color(0.65, 0.7, 0.75))
		return
	for i in range(world.photos.size() - 1, -1, -1):
		var t: TextureRect = $PhotoTemplate.duplicate()
		t.visible = true
		t.texture = world.photos[i]
		_grid.add_child(t)
