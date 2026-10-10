extends HBoxContainer
## 업무 목록 한 줄: 색 점, 이름, 해결 방법, 개수.

@onready var _dot: ColorRect = $Dot
@onready var _name: Label = $Name
@onready var _how: Label = $How
@onready var _count: Label = $Count


func setup(id: String) -> void:
	var t: Dictionary = Game.TASKS[id]
	_dot.color = t.color
	_name.text = t.name
	_how.text = Game.HOW_TEXT[t.how]


func set_count(cur: int, need: int) -> void:
	_count.text = "%d/%d" % [min(cur, need), need]
	var ok := cur >= need
	modulate = Color(0.6, 1, 0.6, 0.85) if ok else Color.WHITE
	_count.text = ("✓ " if ok else "") + _count.text
