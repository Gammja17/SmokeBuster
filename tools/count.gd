extends SceneTree
func _initialize(): _run.call_deferred()
func _run():
	change_scene_to_file(OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "res://scenes/world.tscn")
	for i in 10: await physics_frame
	var meshes := 0; var surfaces := 0; var tris := 0; var mats := {}
	for mi in current_scene.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible or mi.mesh == null: continue
		meshes += 1
		for s in mi.mesh.get_surface_count():
			surfaces += 1
			var m = mi.get_active_material(s)
			mats[m] = true
			var idx = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx else mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()) / 3
	var merged = current_scene.find_child("Merged", true, false); print("merged city meshes=", merged.get_child_count() if merged else -1); print("MeshInstances=", meshes, " surfaces(draw calls)=", surfaces, " materials=", mats.size(), " tris=", tris)
	print("Label3D=", current_scene.find_children("*", "Label3D", true, false).size(), " CPUParticles=", current_scene.find_children("*", "CPUParticles3D", true, false).size(), " overlay meshes=", current_scene.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.material_overlay != null).size())
	quit()
