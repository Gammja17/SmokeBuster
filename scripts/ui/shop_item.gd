extends PanelContainer
## 상점 한 줄. 이름/설명/가격 버튼.

signal buy

@onready var _name: Label = $H/Text/Name
@onready var _desc: Label = $H/Text/Desc
@onready var _buy: Button = $H/Buy


func _ready() -> void:
	_buy.pressed.connect(func(): buy.emit())
	_buy.mouse_entered.connect(Sfx.play.bind("select", -14.0))


func setup(title: String, desc: String, button_text: String, enabled: bool) -> void:
	_name.text = title
	_desc.text = desc
	_buy.text = button_text
	_buy.disabled = not enabled
