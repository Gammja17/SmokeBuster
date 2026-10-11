extends SceneTree
## 캐릭터 애니메이션을 나란히 세워 찍는다. godot --path . -s tools/anim_shots.gd

const ANIMS := ["idle", "die", "holding-both", "emote-no", "emote-yes", "interact-right", "pick-up", "sit", "attack-melee-right", "sprint"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 500)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var env := WorldEnvironment.new()
	env.environment = load("res://scenes/world_env.tres")
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	scene.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	floor.mesh = pm
	scene.add_child(floor)
	var players: Array[AnimationPlayer] = []
	for i in ANIMS.size():
		var m: Node3D = load("res://assets/chars/character-%s.glb" % ["a", "c", "e", "g", "i", "k", "m", "o", "q", "b"][i]).instantiate()
		m.scale = Vector3.ONE * 0.65
		m.position = Vector3(-9 + i * 2.0, 0, 0)
		m.rotation.y = deg_to_rad(-30)
		scene.add_child(m)
		var ap: AnimationPlayer = m.find_child("AnimationPlayer", true, false)
		players.append(ap)
		var l := Label3D.new()
		l.text = ANIMS[i]
		l.font_size = 48
		l.pixel_size = 0.005
		l.position = m.position + Vector3(0, 2.2, 0)
		scene.add_child(l)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.0, 11)
	cam.fov = 55
	scene.add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	for t in [0.1, 0.3, 0.6]:
		for i in ANIMS.size():
			players[i].play(ANIMS[i])
			players[i].seek(min(t * players[i].current_animation_length / 0.6, players[i].current_animation_length - 0.01), true)
			players[i].pause()
		for k in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/shots/anim_%d.png" % int(t * 10))
	quit()
