extends CanvasLayer
## 일시정지 창. Esc로 열고 닫는다. 웹에서는 마우스 잠금이 풀리면 자동으로 열린다.

signal resumed

@onready var _resume: Button = $Panel/V/Resume


func _ready() -> void:
	_resume.pressed.connect(close)
	$Panel/V/Restart.pressed.connect(func():
		get_tree().paused = false
		get_tree().reload_current_scene())
	$Panel/V/Title2.pressed.connect(func():
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/title.tscn"))
	for b in [$Panel/V/Resume, $Panel/V/Restart, $Panel/V/Title2]:
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
