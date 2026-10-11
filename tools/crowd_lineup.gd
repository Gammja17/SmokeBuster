extends SceneTree
## VARCO 행인 30명을 세 줄로 세워 찍는다.  godot --path . -s tools/crowd_lineup.gd

const ROWS := [
	["m_office", "f_office", "m_hiker", "f_ajumma", "m_grandpa", "f_grandma", "m_college", "f_college", "m_delivery", "m_jogger"],
	["f_trench", "m_worker", "f_mom", "m_gamer", "m_thug", "m_track", "m_thief", "m_drunk", "m_boss", "m_tagger"],
	["t_boy", "t_girl", "t_badboy", "t_badgirl", "t_nerd", "s_clerk", "s_doctor", "s_teacher", "s_vendor", "s_shady"],
]
const ANIMS := ["walk", "walk_f", "idle2", "shield", "soaked", "dance", "fear", "throw", "wave_off", "stumble"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1800, 1000)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/world_env.tres")
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -20, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 30)
	floor.mesh = pm
	floor.material_override = Mats.pavement()
	scene.add_child(floor)
	for r in ROWS.size():
		for i in ROWS[r].size():
			var h := Human.make(ROWS[r][i], 1.62 if ROWS[r][i].begins_with("t_") else 1.74)
			h.position = Vector3(-9.0 + i * 2.0, 0, -r * 2.6)
			h.rotation.y = PI
			scene.add_child(h)
			h.play(ANIMS[(i + r * 3) % ANIMS.size()] if r == 1 else "idle2", 0.0)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.2, 9.5)
	cam.fov = 62
	scene.add_child(cam)
	cam.look_at(Vector3(0, 1.0, -2.6))
	for i in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/shots/crowd.png")
	quit()
