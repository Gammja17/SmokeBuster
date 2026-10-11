class_name Trash
extends Node3D
## 길에 떨어진 쓰레기. 플레이어가 가까이서 E 를 누르면 줍는다.

var _picked := false


func _ready() -> void:
	add_to_group("trash")
	add_to_group("pickup")
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match randi() % 5:
		0:  # 캔
			var c := CylinderMesh.new()
			c.top_radius = 0.06
			c.bottom_radius = 0.06
			c.height = 0.2
			mi.mesh = c
			mi.rotation_degrees = Vector3(90, randf() * 360, 0)
			mi.position.y = 0.06
			mat.albedo_color = [Color(0.85, 0.15, 0.15), Color(0.75, 0.78, 0.82), Color(0.2, 0.45, 0.85)].pick_random()
			mat.metallic = 0.7
		1:  # 종이봉투
			var b := BoxMesh.new()
			b.size = Vector3(0.3, 0.22, 0.2)
			mi.mesh = b
			mi.position.y = 0.11
			mat.albedo_color = Color(0.7, 0.55, 0.35)
		2:  # 페트병
			var c := CylinderMesh.new()
			c.top_radius = 0.035
			c.bottom_radius = 0.05
			c.height = 0.3
			mi.mesh = c
			mi.rotation_degrees = Vector3(90, randf() * 360, 0)
			mi.position.y = 0.05
			mat.albedo_color = Color(0.7, 0.9, 1, 0.7)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		3:  # 구겨진 종이
			var s := SphereMesh.new()
			s.radius = 0.1
			s.height = 0.18
			s.radial_segments = 6
			s.rings = 3
			mi.mesh = s
			mi.position.y = 0.08
			mat.albedo_color = Color(0.92, 0.92, 0.88)
		_:  # 꽁초 무더기
			var b := BoxMesh.new()
			b.size = Vector3(0.25, 0.04, 0.2)
			mi.mesh = b
			mi.position.y = 0.02
			mat.albedo_color = Color(0.9, 0.8, 0.55)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 50.0
	add_child(mi)
	rotation.y = randf() * TAU


func pick() -> bool:
	if _picked:
		return false
	_picked = true
	remove_from_group("trash")
	remove_from_group("pickup")
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y + 0.8, 0.15)
	tw.parallel().tween_property(self, "scale", Vector3.ONE * 0.1, 0.2)
	tw.tween_callback(queue_free)
	return true
