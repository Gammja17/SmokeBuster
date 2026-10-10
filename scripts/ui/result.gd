extends CanvasLayer
## 근무 결과 창. Game.last_result 를 보여준다.


func _ready() -> void:
	$Panel/V/Next.pressed.connect(func():
		_go("res://scenes/shop.tscn"))
	$Panel/V/Retry.pressed.connect(func():
		_go("res://scenes/world.tscn"))
	$Panel/V/ToTitle.pressed.connect(func():
		_go("res://scenes/title.tscn"))
	for b in [$Panel/V/Next, $Panel/V/Retry, $Panel/V/ToTitle]:
		b.mouse_entered.connect(Sfx.play.bind("select", -12.0))


func show_result() -> void:
	var r: Dictionary = Game.last_result
	var ok: bool = r.success
	$Panel/V/Title.text = "근무 완료!" if ok else r.get("fail_reason", "근무 실패...")
	$Panel/V/Title.modulate = Color.WHITE if ok else Color(1, 0.5, 0.45)
	$Panel/V/Sub.text = r.day_text
	var lines := "단속 %d / %d\n민원 %d건\n최고 콤보 x%.1f\n번 돈 %d원" % [r.caught, r.quota, r.complaints, r.best_combo, r.earned]
	if not ok:
		lines += "\n(실패해서 절반만 받았어요)"
	$Panel/V/Stats.text = lines
	$Panel/V/Next.visible = ok
	$Panel/V/Retry.visible = not ok
	$Panel/V/Next.text = "장비 사러 가기 (%d일차 준비)" % Game.day
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p: Control = $Panel
	p.pivot_offset = p.size / 2
	p.scale = Vector2.ONE * 0.7
	create_tween().tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("fanfare" if ok else "error", -2.0)


func _go(path: String) -> void:
	Sfx.play("click", -6.0)
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
