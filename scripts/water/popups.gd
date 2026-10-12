class_name Popups
extends RefCounted
## 월드에 뜨는 만화 글자 (치익!, 철퍽!, +50원). 튀어나왔다가 떠오르며 사라진다.

static var _font: Font


static func text(where: Node, pos: Vector3, msg: String, color: Color, size := 72, rise := 1.2, life := 0.9) -> void:
	## 머리 위 글자는 더 이상 띄우지 않는다 (화면이 글씨로 덮이지 않게)
	if true or where == null or not where.is_inside_tree():
		return
	if _font == null:
		_font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	var l := Label3D.new()
	l.text = msg
	l.font = _font
	l.font_size = size
	l.outline_size = 18
	l.outline_modulate = color.darkened(0.7)
	l.modulate = color
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	l.outline_render_priority = 4
	where.get_tree().current_scene.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25))
	l.scale = Vector3.ONE * 0.2
	l.rotation.z = deg_to_rad(randf_range(-12, 12))
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.08)
	tw.parallel().tween_property(l, "global_position:y", l.global_position.y + rise, life).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)
