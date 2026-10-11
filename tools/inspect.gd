extends SceneTree
func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D: t = xf * n.transform
	if n is MeshInstance3D and n.mesh:
		var a: AABB = t * n.mesh.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	for c in n.get_children(): _aabb(c, t, acc)
func _init():
	var files := []
	for dir in OS.get_cmdline_user_args():
		var d := DirAccess.open(dir)
		for f in d.get_files():
			if f.ends_with(".glb") or f.ends_with(".gltf"): files.append(dir + "/" + f)
	for f in files:
		var s = load(f)
		if s == null: print(f, " LOAD FAIL"); continue
		var inst: Node = s.instantiate()
		var acc := [null]
		_aabb(inst, Transform3D.IDENTITY, acc)
		var anims := ""
		var ap = inst.find_child("AnimationPlayer", true, false)
		if ap: anims = str(ap.get_animation_list())
		var a: AABB = acc[0] if acc[0] != null else AABB()
		print(f.get_file(), " size=", a.size.snapped(Vector3.ONE*0.01), " pos=", a.position.snapped(Vector3.ONE*0.01), " ", anims)
		inst.free()
	quit()
