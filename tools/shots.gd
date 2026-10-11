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

	change_scene_to_file("res://scenes/title.tscn")
	await frames(60)
	await shot("01_title")

	game.day = 4
	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	w._start_shift()
	w.cfg.spawns = []
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	await frames(60)
	await shot("03_start_view")

	# 물총 들고 흡연자 맞히기
	var fwd: Vector3 = -p.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var s = w._new_npc("normal")
	s.position = p.global_position + fwd * 5.0
	w.npcs.add_child(s)
	await frames(60)
	p.camera.look_at(s.global_position + Vector3.UP * 1.1)
	p.equip("pistol")
	await frames(20)
	await shot("04_pistol_view")
	for i in 25:
		p._fire_drops(game.WEAPONS.pistol, 1)
		await process_frame
	await shot("05_hit_react")
	for i in 60:
		p._fire_drops(game.WEAPONS.pistol, 1)
		await process_frame
		if s.done:
			break
	await frames(6)
	await shot("06_extinguish")
	await frames(30)
	await shot("06b_knocked")

	# 슈퍼소커
	p.equip("soaker")
	await frames(20)
	await shot("07_soaker_view")

	# 소방호스로 행인 넘어뜨리기
	var ped = w._new_npc("ped")
	ped.position = p.global_position + fwd * 6.0
	w.npcs.add_child(ped)
	ped.set_physics_process(true)
	await frames(30)
	p.camera.look_at(ped.global_position + Vector3.UP * 1.0)
	p.equip("hose")
	await frames(15)
	for i in 30:
		p._fire_drops(game.WEAPONS.hose, 2)
		await process_frame
	await shot("08_hose_knockdown")

	# 골목
	var c: Vector2 = w.city.block_centers[0]
	p.global_position = Vector3(c.x, 0.2, c.y)
	p.camera.rotation = Vector3.ZERO
	p.rotation.y = 0
	await frames(30)
	await shot("09_alley")

	# 사진 한 장 찍고 결과 화면
	p.global_position = Vector3(-8.5, 0.3, -14.0)
	p.rotation.y = 0
	p.camera.rotation = Vector3.ZERO
	var teen = w._new_npc("teen_smoker")
	teen.position = p.global_position - p.global_basis.z * 5.0
	w.npcs.add_child(teen)
	await frames(30)
	p.camera.look_at(teen.incident_pos())
	p.set_camera_mode(true)
	await frames(25)
	p._photo_cd = 0
	p.snap_photo()
	await frames(8)
	await shot("10_polaroid")
	p.set_camera_mode(false)
	for id in w.cfg.tasks:
		w.progress[id] = w.cfg.tasks[id]
	w.time_left = 0.01
	await create_timer(2.5).timeout
	await frames(30)
	await shot("11_result")

	game.new_game()
	quit()
