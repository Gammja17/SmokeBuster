class_name IllegalParking
extends StaticBody3D
## 횡단보도나 교차로 앞에 비상등 켜고 세운 차. 사진 찍으면 견인된다.

signal resolved(car: IllegalParking, task: String)

const MODELS := ["sedan", "suv", "van", "hatchback-sports", "delivery"]

var done := false
var _label: Label3D
var _blinkers: Array[MeshInstance3D] = []
var _model: Node3D


func _ready() -> void:
	add_to_group("incident")
	collision_layer = 1
	_model = load("res://assets/cars/%s.glb" % MODELS.pick_random()).instantiate()
	_model.scale = Vector3.ONE * 1.6
	_model.rotation.y = PI
	add_child(_model)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.0, 4.6)
	col.shape = box
	col.position.y = 1.0
	add_child(col)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.6, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.55, 0.05)
	mat.emission_energy_multiplier = 3.0
	for x in [-0.95, 0.95]:
		for z in [-2.2, 2.2]:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.25, 0.15, 0.08)
			bm.material = mat
			b.mesh = bm
			b.position = Vector3(x, 0.9, z)
			add_child(b)
			_blinkers.append(b)
	var tw := create_tween().set_loops()
	tw.tween_callback(func(): for b in _blinkers: b.visible = not b.visible)
	tw.tween_interval(0.45)
	_label = Label3D.new()
	_label.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	_label.text = "불법주차"
	_label.font_size = 56
	_label.pixel_size = 0.008
	_label.outline_size = 12
	_label.modulate = Game.TASKS.parking.color
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.9
	_label.visibility_range_end = 60.0
	add_child(_label)


func task() -> String:
	return "parking"


func is_active_incident() -> bool:
	return not done


func incident_pos() -> Vector3:
	return global_position + Vector3.UP * 1.2


func photo_task() -> String:
	return "parking" if not done else ""


func wants_water() -> bool:
	return false


func on_photographed() -> void:
	if done:
		return
	done = true
	remove_from_group("incident")
	_label.text = "견인합니다!"
	_label.modulate = Color(0.6, 1, 0.6)
	resolved.emit(self, "parking")
	Sfx.play_at("horn", global_position, -2.0, 0.6)
	# 견인: 앞이 들리면서 끌려간다
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(_model, "rotation:x", deg_to_rad(-12), 0.5)
	tw.tween_property(self, "global_position", global_position - global_basis.z * 30.0, 4.0).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
