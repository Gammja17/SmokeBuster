extends CanvasLayer
## 엔딩: 검은 화면 → 동네일보 호외가 툭 떨어지고 → 크레딧이 올라간다 → 계속 순찰 / 타이틀로.

signal continue_play

const CREDITS := """DO NOT SMOKE HERE



기획 · 지시
감자 (Gammja17)

만든 이
Claude

캐릭터 · 애니메이션
VARCO 3D

소품 · 하늘 · 바닥
Poly Haven (CC0)
Kenney (CC0)

글꼴
Pretendard (OFL)
D2Coding (OFL)

엔진
Godot 4



그리고 우리 동네 주민 여러분



골목에 다시 맑은 공기를"""


func _ready() -> void:
	$Buttons/Continue.pressed.connect(func():
		Sfx.play("click")
		visible = false
		get_tree().paused = false
		continue_play.emit())
	$Buttons/Title.pressed.connect(func():
		Sfx.play("click")
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/title.tscn"))


func play(stats: Dictionary) -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var paper: Control = $Paper
	var roll: Label = $Credits/Roll
	var buttons: Control = $Buttons
	$Paper/V/Sub.text = "물대포 파출소 %s, 근무 %d일 만에 골목 담배파부터 꽁초 카르텔까지 다섯 조직 두목을 모두 검거. 주민들 \"이제 창문 열고 산다\"" % [stats.rank, stats.days]
	$Paper/V/Stats.text = "근무 일수      %d일\n총 단속        %d건\n최고 성적      %s\n평균 정화도    %d%%\n모은 돈        ₩%d" % [stats.days, stats.caught, stats.best, stats.clean, stats.money]
	roll.text = CREDITS
	$Black.modulate.a = 0.0
	paper.modulate.a = 0.0
	paper.scale = Vector2.ONE * 1.6
	paper.rotation = deg_to_rad(-8)
	roll.modulate.a = 0.0
	buttons.modulate.a = 0.0
	buttons.visible = false
	var tw := create_tween()
	tw.tween_property($Black, "modulate:a", 1.0, 1.2)
	tw.tween_interval(0.6)
	# 신문이 툭 떨어진다
	tw.tween_callback(Sfx.play.bind("thud", 0.0, 0.8))
	tw.tween_property(paper, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(paper, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(paper, "rotation", deg_to_rad(-2), 0.35)
	tw.tween_interval(6.0)
	tw.tween_property(paper, "modulate:a", 0.0, 0.8)
	# 크레딧
	tw.tween_callback(func():
		roll.modulate.a = 1.0
		roll.position.y = get_viewport().get_visible_rect().size.y)
	tw.tween_property(roll, "position:y", -1300.0, 26.0)
	tw.tween_callback(func(): buttons.visible = true)
	tw.tween_property(buttons, "modulate:a", 1.0, 0.6)
	# 신문이 걷히면 버튼을 먼저 띄워 크레딧 중에도 넘어갈 수 있게
	var tb := create_tween()
	tb.tween_interval(9.2)
	tb.tween_callback(func(): buttons.visible = true)
	tb.tween_property(buttons, "modulate:a", 1.0, 0.6)
