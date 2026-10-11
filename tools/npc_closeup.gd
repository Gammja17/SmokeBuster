extends SceneTree
## 흡연자 한 명을 가까이서 찍는다 (연기/담배 확인용)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(900, 600)
	var game = root.get_node("Game")
	game.day = 4
	change_scene_to_file("res://scenes/world.tscn")
	for i in 10:
		await process_frame
	var w = current_scene
	w.cfg.spawns = []
	for n in w.npcs.get_children():
		n.queue_free()
	var s = w._new_npc("normal")
	s.position = Vector3(-8.5, 0.1, -20)
	s.rotation.y = 0.0
	w.npcs.add_child(s)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.global_position = Vector3(-7.6, 1.7, -22.6)
	cam.look_at(Vector3(-8.5, 1.6, -20))
	w.hud.visible = false
	cam.current = true
	for k in 3:
		for i in 60:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/shots/close_%d.png" % k)
		if k == 0:
			s._puff.visible = false
		if k == 1:
			s._smoke.visible = false
	game.new_game()
	quit()
