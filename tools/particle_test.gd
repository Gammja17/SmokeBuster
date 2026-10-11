extends SceneTree
## 연기 파티클 검은 덩어리 원인 확인: 아직 안 나온 입자가 검게 그려지는지


func _initialize() -> void:
	_run.call_deferred()


func _make(preprocess: bool, one_shot_idle: bool) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = FxPool.soft_puff()
	mat.albedo_color = Color(0.86, 0.86, 0.88, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	quad.material = mat
	var p := CPUParticles3D.new()
	p.amount = 26
	p.lifetime = 4.5
	p.local_coords = false
	p.mesh = quad
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0.2, 0.45, 0)
	if preprocess:
		p.preprocess = 4.5
	if one_shot_idle:
		p.one_shot = true
		p.emitting = false
	return p


func _run() -> void:
	root.size = Vector2i(1000, 500)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/world_env.tres")
	scene.add_child(env)
	var labels := ["plain", "preprocess", "one_shot idle"]
	for v in 3:
		var p := _make(v == 1, v == 2)
		p.position = Vector3(-2 + v * 2, 0, 0)
		scene.add_child(p)
		var l := Label3D.new()
		l.text = labels[v]
		l.position = p.position + Vector3(0, -0.5, 0)
		scene.add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 7)
	scene.add_child(cam)
	cam.look_at(Vector3(0, 1.2, 0))
	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/shots/particles_1s.png")
	for i in 360:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/shots/particles_7s.png")
	quit()
