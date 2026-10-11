extends SceneTree
## 창을 띄워 여러 장면을 찍어 tools/shots/*.png 로 저장한다. (헤드리스 X)
## godot --path . -s tools/shots.gd

var out := "res://tools/shots/"


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out + name + ".png")
	print("saved ", name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size = Vector2i(1280, 720)
	var game = root.get_node("Game")
	game.new_game()
	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	game.has_truck = true
	game.xp = game.RANK_XP[2]
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	w._start()
	w.cfg.events = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	await frames(60)

	# 3인칭
	p.set_third_person(true)
	p.rotation.y = deg_to_rad(160)
	await frames(30)
	await shot("01_third_person")

	# 싸움과 낙서범을 바로 앞에
	p.global_position = Vector3(-8.5, 0.3, -14.0)
	p.rotation.y = 0
	w._spawn_fight()
	await frames(5)
	for n in w.npcs.get_children():
		if n.kind == "fighter":
			p.global_position = n.global_position + Vector3(0, 0.3, 5)
			p.look_at(Vector3(n.global_position.x, p.global_position.y, n.global_position.z))
			break
	await frames(60)
	await shot("02_fight")

	w._spawn_wall_npc("tagger")
	await frames(5)
	for n in w.npcs.get_children():
		if n.kind == "tagger":
			var back: Vector3 = n.global_basis.z * 4.0
			p.global_position = n.global_position + back + Vector3(0, 0.3, 0)
			p.look_at(Vector3(n.global_position.x, p.global_position.y, n.global_position.z))
			break
	await frames(90)
	await shot("03_tagger")

	# 도둑
	p.set_third_person(false)
	var victim = w._new_npc("ped")
	victim.position = Vector3(-8.5, 0.1, -30)
	w.npcs.add_child(victim)
	victim.start_walking(w.city.nearest_nav(victim.position))
	var thief = w._new_npc("thief")
	thief.position = victim.position + Vector3(0.8, 0, 0)
	w.npcs.add_child(thief)
	thief.start_walking(w.city.nearest_nav(thief.position))
	thief._snatch_t = 0.0
	p.global_position = Vector3(-8.5, 0.3, -22)
	p.rotation.y = 0
	await frames(25)
	await shot("04_thief")

	# 불법주차
	w._spawn_parking()
	await frames(5)
	for c in w.get_children():
		if c.has_method("task") and c.task() == "parking":
			p.global_position = c.global_position + Vector3(6, 0.3, 6)
			p.look_at(Vector3(c.global_position.x, p.global_position.y, c.global_position.z))
			break
	await frames(30)
	await shot("05_parking")

	# 순찰차 운전
	var cars: Array = w.get_tree().get_nodes_in_group("vehicle")
	for car in cars:
		if car.kind == "police":
			p.global_position = car.global_position + Vector3(2, 0, 0)
			await frames(3)
			w._toggle_vehicle()
			car._siren_on = true
			car._siren.play()
			for i in 90:
				car.speed = 14.0
				await process_frame
			await shot("06_driving")
			w._toggle_vehicle()
			break
	# 소방차 물대포
	for car in w.get_tree().get_nodes_in_group("vehicle"):
		if car.kind == "firetruck":
			p.global_position = car.global_position + Vector3(2.5, 0, 0)
			await frames(3)
			w._toggle_vehicle()
			await frames(30)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Input.action_press("ui_accept")
			for i in 40:
				var muzzle: Vector3 = car._cannon.global_position - car._cannon.global_basis.z * 1.1
				w.water.spawn(muzzle, -car.global_basis.z * 26.0 + Vector3.UP * 2.0, 0.09, 3.0, 9.0, 0.0, 0.2)
				await process_frame
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			await shot("07_firetruck")
			break

	game.new_game()
	quit()
