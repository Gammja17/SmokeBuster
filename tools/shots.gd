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
	game.upgrades.cctv = 1
	game.upgrades.ops = 1
	game.upgrades.garage = 1
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	w._start()
	w.cfg.events = false
	w._mission_t = 999.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	await frames(40)

	# 파출소 정면 (길 건너편에서)
	p.global_position = Vector3(-17.0, 0.3, 4.0)
	p.rotation.y = 0
	p.camera.rotation = Vector3(deg_to_rad(8), 0, 0)
	await frames(40)
	await shot("01_station")

	# 시작 시점 그대로
	p.global_position = w.SPAWN
	p.rotation.y = PI
	p.camera.rotation = Vector3.ZERO
	await frames(30)
	await shot("02_spawn_view")

	# 거리 (나무, 가로등, 상가)
	p.global_position = Vector3(-8.0, 0.3, -40.0)
	p.rotation.y = deg_to_rad(10)
	await frames(30)
	await shot("03_street")

	# 무전 출동: 멀리서 빛기둥
	w.force_mission_type = "smoke"
	w._start_mission()
	await frames(10)
	var mp: Vector3 = w.mission.pos
	p.global_position = Vector3(-17.0, 0.3, -7.2)
	p.look_at(Vector3(mp.x, p.global_position.y, mp.z))
	p.camera.rotation = Vector3(deg_to_rad(6), 0, 0)
	await frames(40)
	await shot("04_dispatch")

	# 공원
	var pc: Vector2 = w.city.park_center
	p.global_position = Vector3(pc.x - 12, 0.3, pc.y + 12)
	p.look_at(Vector3(pc.x, p.global_position.y, pc.y))
	await frames(30)
	await shot("05_park")

	game.new_game()
	quit()
