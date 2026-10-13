extends CanvasLayer
## PC방 미니게임: 20초 동안 튀어나오는 꽁초를 클릭으로 맞힌다. 배치는 ui/aim_game.tscn.

signal finished(score: int)

const TIME := 20.0

var score := 0
var _left := TIME
var _spawn_t := 0.0
var _done := false

@onready var _field: Control = $Monitor/Field
@onready var _score: Label = $Monitor/Score


func _process(delta: float) -> void:
	if _done:
		return
	_left -= delta
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		# 시간이 갈수록 빨리, 동시에 여럿
		_spawn_t = lerpf(0.75, 0.35, 1.0 - _left / TIME)
		_spawn_target()
	_score.text = "%d점  %.1f초" % [score, maxf(_left, 0.0)]
	if _left <= 0.0:
		_finish()


func _spawn_target() -> void:
	var t: Button = $TargetTemplate.duplicate()
	t.visible = true
	t.position = Vector2(randf_range(0, _field.size.x - 70), randf_range(0, _field.size.y - 70))
	_field.add_child(t)
	t.pressed.connect(func():
		score += 1
		Sfx.play("coin", -8.0, 1.0 + score * 0.02)
		t.queue_free())
	# 잠깐 있다가 사라진다
	var tw := t.create_tween()
	tw.tween_interval(lerpf(1.3, 0.8, 1.0 - _left / TIME))
	tw.tween_property(t, "modulate:a", 0.0, 0.15)
	tw.tween_callback(t.queue_free)


func _finish() -> void:
	_done = true
	Sfx.play("fanfare", -6.0)
	finished.emit(score)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not _done:
		get_viewport().set_input_as_handled()
		_finish()
