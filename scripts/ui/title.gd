extends Node3D
## 타이틀. 뒤에 동네를 만들어 두고 카메라가 천천히 돈다.

@onready var _pivot: Node3D = $Pivot
@onready var _camera: Camera3D = $Pivot/Camera
@onready var _ui: CanvasLayer = $UI

var _city := CityBuilder.new()


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Sun.rotation_degrees = Vector3(-50, -35, 0)
	_city.build(self, 77)
	_pivot.position = Vector3(0, 0, 30)
	_camera.position = Vector3(0, 5.5, 0)
	_spawn_extras()

	var cont: Button = _ui.get_node("Left/Continue")
	var fresh: Button = _ui.get_node("Left/New")
	var save_label: Label = _ui.get_node("Left/Save")
	if Game.has_save():
		save_label.text = "이어하기: %s · %d원" % [Game.rank_name(), Game.money]
	else:
		save_label.visible = false
		cont.visible = false
		fresh.text = "순찰 시작"
	cont.pressed.connect(_start.bind(false))
	fresh.pressed.connect(_start.bind(true))
	for b in [cont, fresh]:
		b.mouse_entered.connect(Sfx.play.bind("select", -12.0))
	(cont if cont.visible else fresh).grab_focus()
	Sfx.music(true)

	var logo: Control = _ui.get_node("Left/Logo")
	logo.pivot_offset = Vector2(0, logo.size.y / 2)
	var tw := create_tween().set_loops()
	tw.tween_property(logo, "rotation", deg_to_rad(-1.5), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(logo, "rotation", deg_to_rad(1.5), 1.2).set_trans(Tween.TRANS_SINE)


func _spawn_extras() -> void:
	# 배경에 걷는 행인과 담배 피우는 사람
	var dummy := Node3D.new()
	dummy.position = Vector3(-27, 0, -27)
	add_child(dummy)
	for i in 10:
		var n := Npc.new()
		n.setup("ped", _city, dummy)
		var node := randi() % _city.nav_nodes.size()
		n.position = _city.nav_nodes[node]
		add_child(n)
		n.start_walking(node)
	for i in 4:
		var spot: Dictionary = _city.spots[randi() % _city.spots.size()]
		var s := Npc.new()
		s.setup("normal", _city, dummy)
		s.position = spot.pos
		s.rotation.y = randf() * TAU
		add_child(s)


var _t := 0.0


func _process(delta: float) -> void:
	# 가운데 도로를 따라 천천히 왕복하며 대각선 앞을 본다
	_t += delta * 0.05
	var z := sin(_t) * 40.0
	_pivot.position = Vector3(1.5, 0, z)
	_camera.look_at(Vector3(-14, 2.0, z - 22.0 * cos(_t)))


func _start(fresh: bool) -> void:
	Sfx.play("click")
	if fresh:
		Game.new_game()
	get_tree().change_scene_to_file("res://scenes/world.tscn")
