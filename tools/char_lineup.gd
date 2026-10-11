extends SceneTree
## 캐릭터 18종을 나란히 찍는다


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1800, 500)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/world_env.tres")
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -20, 0)
	scene.add_child(sun)
	var ids := "abcdefghijklmnopqr"
	for i in ids.length():
		var m: Node3D = load("res://assets/chars/character-%s.glb" % ids[i]).instantiate()
		m.scale = Vector3.ONE * 0.65
		m.position = Vector3(-17 + i * 2.0, 0, 0)
		scene.add_child(m)
		var l := Label3D.new()
		l.text = ids[i]
		l.font_size = 64
		l.pixel_size = 0.006
		l.position = m.position + Vector3(0, 2.1, 0)
		scene.add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, 17)
	cam.fov = 60
	scene.add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/shots/chars.png")
	quit()
