extends SceneTree
## 메뉴들(타이틀, 일시정지, 장비실), 포크레인, 엔딩을 찍는다.  godot --path . -s tools/ui2_shots.gd


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/shots/" + name + ".png")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game = root.get_node("Game")
	change_scene_to_file("res://scenes/title.tscn")
	await frames(30)
	await shot("m_title")
	game.new_game()
	game.flags["intro"] = true
	game.money = 5000
	game.has_excavator = true
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	w._start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(40)
	w.pause.open()
	await frames(10)
	await shot("m_pause")
	w.pause.close()
	w._open_shop()
	await frames(10)
	await shot("m_shop")
	w._close_shop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 포크레인 타고 팔 들기
	var exc: Array = w.get_tree().get_nodes_in_group("vehicle").filter(func(v): return v.kind == "excavator")
	if exc.size() > 0:
		w.player.global_position = exc[0].global_position + Vector3(2.5, 0, 0)
		await frames(5)
		w._enter(exc[0])
		await frames(30)
		exc[0]._swing()
		await create_timer(0.3).timeout
		await shot("m_excavator")
		await create_timer(1.0).timeout
	# 엔딩 화면 (호외)
	w.ending.play({"rank": "경정", "days": 23, "caught": 412, "best": "S", "clean": 81, "money": 48200})
	await create_timer(3.0, true, false, true).timeout
	await shot("m_ending")
	await create_timer(9.0, true, false, true).timeout
	await shot("m_credits")
	quit()
