extends CanvasLayer
## 조준점, 물 게이지, 점수, 조작 안내.

var water_bar: ProgressBar
var score_label: Label
var message_label: Label


func _ready() -> void:
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 28)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(crosshair)

	var box := VBoxContainer.new()
	box.position = Vector2(20, 20)
	add_child(box)

	var water_label := Label.new()
	water_label.text = "물"
	box.add_child(water_label)

	water_bar = ProgressBar.new()
	water_bar.custom_minimum_size = Vector2(220, 20)
	box.add_child(water_bar)

	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 22)
	box.add_child(score_label)

	var hint := Label.new()
	hint.text = "WASD 이동 · 좌클릭 분사 · R 리필 · Esc 마우스 풀기"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position += Vector2(20, -40)
	add_child(hint)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 32)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message_label.position.y += 80
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(message_label)


func set_water(current: float, maximum: float) -> void:
	water_bar.max_value = maximum
	water_bar.value = current


func set_score(value: int) -> void:
	score_label.text = "끈 담배: %d" % value


func flash_message(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(message_label, "modulate:a", 0.0, 0.5)
