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
	var lines := "%s\n해결한 일 %d건 · 민원 %d건\n최고 콤보 x%.1f\n번 돈 %d원" % [r.tasks_text, r.resolved, r.complaints, r.best_combo, r.earned]
	if not ok:
		lines += "\n(실패해서 절반만 받았어요)"
	if ok and r.get("bonus", 0) > 0:
		lines += "\n(%s 등급 보너스 +%d원 포함)" % [r.grade, r.bonus]
	$Panel/V/Stats.text = lines
	# 등급 도장
	var grade: Label = $Panel/V/Grade
	grade.text = r.get("grade", "F")
	grade.add_theme_color_override("font_color", {"S": Color(1, 0.8, 0.2), "A": Color(0.4, 0.9, 1), "B": Color(0.7, 1, 0.6), "F": Color(1, 0.35, 0.3)}[grade.text])
	grade.pivot_offset = grade.size / 2
	grade.scale = Vector2.ONE * 3.0
	grade.modulate.a = 0.0
	grade.rotation = deg_to_rad(-12)
	var gt := create_tween()
	gt.tween_interval(0.45)
	gt.tween_property(grade, "modulate:a", 1.0, 0.01)
	gt.tween_property(grade, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	gt.tween_callback(Sfx.play.bind("thud", 2.0))
	# 승진
	var rank: Label = $Panel/V/Rank
	rank.visible = r.get("promoted", false)
	rank.text = "승진! 이제 %s 계급" % r.get("rank", "")
	# 오늘 찍은 사진
	var box: HBoxContainer = $Panel/V/Photos
	for c in box.get_children():
		c.queue_free()
	for tex in r.get("photos", []):
		var frame := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.97, 0.96, 0.92)
		sb.content_margin_left = 4
		sb.content_margin_right = 4
		sb.content_margin_top = 4
		sb.content_margin_bottom = 10
		frame.add_theme_stylebox_override("panel", sb)
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(104, 60)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		frame.add_child(tr)
		frame.rotation = deg_to_rad(randf_range(-5, 5))
		box.add_child(frame)
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
