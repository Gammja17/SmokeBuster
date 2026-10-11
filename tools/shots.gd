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

	game.owned = ["spray", "pistol", "bucket", "soaker", "hose"]
	game.xp = game.RANK_XP[2]
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	await shot("02_intro")
	w._start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	await frames(90)
	await shot("03_patrol")

	# 골목 입구마다 막혔는지 확인 (블록 중심에서 동/남/북 입구를 바라봄)
	var i := 0
	for c in w.city.block_centers:
		if c == w.city.park_center:
			continue
		p.global_position = Vector3(c.x, 0.2, c.y)
		p.camera.rotation = Vector3.ZERO
		for yaw in [0.0, -90.0, 180.0]:
			p.rotation.y = deg_to_rad(yaw)
			await frames(12)
			await shot("04_alley_%d_%d" % [i, int(yaw)])
		i += 1
		if i >= 1:
			break

	# 승진 연출
	w._add_xp(game.RANK_XP[3] - game.xp + 1)
	await frames(20)
	await shot("05_promote")

	# 장비실
	w._open_shop()
	await frames(10)
	await shot("06_shop")
	w._close_shop()

	game.new_game()
	quit()
