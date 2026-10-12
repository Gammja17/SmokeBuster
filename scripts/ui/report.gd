extends CanvasLayer
## 퇴근 성적표 + 다음 날 동네일보. 배치는 ui/report.tscn, 여기선 값만 채운다.

signal next_day

const COMMENTS := {
	"S": "전설의 물대포 순경! 소장님이 직접 칭찬했어요.",
	"A": "훌륭한 하루였어요. 동네가 확실히 달라졌어요.",
	"B": "무난한 근무. 내일은 조금 더 바쁘게!",
	"C": "할당량이 많이 모자라요... 소장님 표정이 굳었어요.",
}
const GRADE_COLORS := {"S": Color(1, 0.85, 0.3), "A": Color(0.5, 0.9, 1), "B": Color(0.7, 1, 0.6), "C": Color(1, 0.5, 0.45)}


func _ready() -> void:
	$Row/Card/V/Next.pressed.connect(func():
		Sfx.play("click")
		next_day.emit())


func show_report(r: Dictionary) -> void:
	## r: day, grade, stats(text), districts(text), pay, headline, sub, briefs, weather
	$Row/Card/V/Head.text = "DAY %d · 근무 성적표" % r.day
	$Row/Card/V/GradeRow/Grade.text = r.grade
	$Row/Card/V/GradeRow/Grade.add_theme_color_override("font_color", GRADE_COLORS[r.grade])
	$Row/Card/V/GradeRow/Comment.text = COMMENTS[r.grade]
	$Row/Card/V/Stats.text = r.stats
	$Row/Card/V/Districts.text = r.districts
	$Row/Card/V/Pay.text = "월급 ₩%d" % r.pay
	$Row/Card/V/Next.text = "다음 근무 시작 (DAY %d)" % (r.day + 1)
	$Row/Paper/V/Date.text = "제 %d호 · 내일 날씨: %s" % [r.day, r.weather]
	$Row/Paper/V/Headline.text = r.headline
	$Row/Paper/V/Sub.text = r.sub
	$Row/Paper/V/Briefs.text = r.briefs
	$Row/Paper/V/Photo.texture = r.get("photo")
	$Row/Paper/V/Photo.visible = r.get("photo") != null
	$Row/Paper/V/Caption.visible = r.get("photo") != null
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 등급 도장이 쾅 찍힌다
	var g: Label = $Row/Card/V/GradeRow/Grade
	g.pivot_offset = g.size / 2
	g.scale = Vector2.ONE * 2.5
	g.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(g, "modulate:a", 1.0, 0.05)
	tw.parallel().tween_property(g, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(Sfx.play.bind("thud", 2.0))
	$Row/Card/V/Next.grab_focus()
