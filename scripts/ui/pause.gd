extends CanvasLayer
## 일시정지 창. Esc로 열고 닫는다. 웹에서는 마우스 잠금이 풀리면 자동으로 열린다.

signal resumed
signal shop_requested

@onready var _resume: Button = $Panel/V/Resume


func _ready() -> void:
	_resume.pressed.connect(close)
	$Panel/V/Shop.pressed.connect(func(): shop_requested.emit())
	$Panel/V/Title2.pressed.connect(func():
		Game.save_game()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/title.tscn"))
	# 그래픽 품질: 누를 때마다 높음 -> 낮음 -> 보통 -> 높음
	var gfx: Button = $Panel/V/Gfx
	gfx.text = "그래픽 품질: " + Game.QUALITY_NAMES[Game.quality]
	gfx.pressed.connect(func():
		Game.set_quality((Game.quality + 1) % 3, get_parent())
		gfx.text = "그래픽 품질: " + Game.QUALITY_NAMES[Game.quality])
	for b in [$Panel/V/Resume, $Panel/V/Shop, $Panel/V/Gfx, $Panel/V/Title2]:
		b.mouse_entered.connect(Sfx.play.bind("select", -12.0))


func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false
	Sfx.play("click", -6.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()
