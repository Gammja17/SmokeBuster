extends SceneTree
## VARCO 캐릭터를 게임 조명에서 찍어본다
func _initialize(): _run.call_deferred()
func _run():
	root.size = Vector2i(1000, 700)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/world_env.tres")
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor.mesh = pm
	floor.material_override = Mats.pavement()
	scene.add_child(floor)
	var path: String = OS.get_cmdline_user_args()[0]
	var m: Node3D = load(path).instantiate()
	scene.add_child(m)
	var acc := [null]
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mi.global_transform * mi.get_aabb()
		acc[0] = a if acc[0] == null else acc[0].merge(a)
	print("aabb ", acc[0])
	var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
	if ap:
		print("anims ", ap.get_animation_list())
		var al = ap.get_animation_list()
		if al.size() > 0:
			ap.play(al[0])
	var h: float = acc[0].size.y
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.position = Vector3(h * 0.4, h * 0.65, h * 1.4)
	cam.look_at(Vector3(0, h * 0.5, 0))
	for i in 40: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/shots/varco_view.png")
	quit()
