extends SceneTree
## 실사 캐릭터 5명이 각자 다른 애니메이션을 하는 모습을 찍는다


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1500, 650)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/world_env.tres")
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 20)
	floor.mesh = pm
	floor.material_override = Mats.pavement()
	scene.add_child(floor)
	var setup := [["player", "walk"], ["chief", "cross_arms"], ["ops", "talk"], ["mechanic", "wave"], ["rookie", "salute"]]
	for i in setup.size():
		var h := Human.make(setup[i][0], 1.75)
		h.position = Vector3(-4.0 + i * 2.0, 0, 0)
		h.rotation.y = PI
		scene.add_child(h)
		h.play(setup[i][1], 0.0)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 6.5)
	cam.fov = 60
	scene.add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	for t in [30, 70]:
		for i in t:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/shots/people_%d.png" % t)
	quit()
