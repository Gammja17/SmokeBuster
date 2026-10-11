extends SceneTree
## 월드에서 삼각형을 많이 먹는 메시를 이름별로 모아 보여준다.  godot --headless --path . -s tools/tris.gd


func _initialize() -> void:
	_run.call_deferred()


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx = a[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null and idx.size() > 0 else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n


func _run() -> void:
	var game = root.get_node("Game")
	game.new_game()
	change_scene_to_file("res://scenes/world.tscn")
	for i in 10:
		await process_frame
	var w = current_scene
	w._start()
	for i in 30:
		await process_frame
	var sums := {}
	var counts := {}
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var key: String = mi.mesh.resource_path.get_file() if mi.mesh.resource_path != "" else (mi.get_parent().name + "/" + mi.name)
		key = key.left(40)
		sums[key] = sums.get(key, 0) + _tris(mi.mesh)
		counts[key] = counts.get(key, 0) + 1
	for mm in w.find_children("*", "MultiMeshInstance3D", true, false):
		if mm.multimesh and mm.multimesh.mesh:
			var key := "MM:" + mm.name
			sums[key] = sums.get(key, 0) + _tris(mm.multimesh.mesh) * mm.multimesh.visible_instance_count if mm.multimesh.visible_instance_count >= 0 else _tris(mm.multimesh.mesh) * mm.multimesh.instance_count
			counts[key] = 1
	var keys := sums.keys()
	keys.sort_custom(func(a, b): return sums[a] > sums[b])
	var total := 0
	for k in keys:
		total += sums[k]
	print("total tris %dk" % (total / 1000))
	for k in keys.slice(0, 22):
		print("%8dk  x%-4d %s" % [sums[k] / 1000, counts[k], k])
	quit()
