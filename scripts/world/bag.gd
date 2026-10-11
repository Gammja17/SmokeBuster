class_name StolenBag
extends Node3D
## 도둑이 떨어뜨린 가방. E로 주우면 주인에게 돌려준다.

var victim: Node = null
var _picked := false


func _ready() -> void:
	add_to_group("pickup")
	add_to_group("bag")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.3, 0.15)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.2, 0.35)
	bm.material = mat
	mi.mesh = bm
	mi.position.y = 0.15
	add_child(mi)
	var strap := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.12
	tm.outer_radius = 0.14
	strap.mesh = tm
	strap.rotation_degrees.x = 90
	strap.position.y = 0.32
	add_child(strap)
	var l := Label3D.new()
	l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	l.text = "가방 (E)"
	l.font_size = 40
	l.pixel_size = 0.006
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position.y = 0.8
	add_child(l)
	var tw := create_tween().set_loops()
	tw.tween_property(mi, "position:y", 0.3, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mi, "position:y", 0.15, 0.5).set_trans(Tween.TRANS_SINE)


func pick() -> bool:
	if _picked:
		return false
	_picked = true
	remove_from_group("pickup")
	remove_from_group("bag")
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y + 0.8, 0.15)
	tw.parallel().tween_property(self, "scale", Vector3.ONE * 0.1, 0.2)
	tw.tween_callback(queue_free)
	return true
