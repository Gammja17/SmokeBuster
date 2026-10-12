extends SceneTree
## 메인 메뉴, 게임 HUD, 무기 휠, 거리 사람들을 찍는다.  godot --path . -s tools/ui_shots.gd


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
	await shot("ui_menu")

	game.new_game()
	game.owned = ["spray", "pistol", "bucket", "soaker"]
	game.money = 12450
	game.xp = 700
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	w._start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	# 첫날 소장님 대화 (컷씬)
	await create_timer(2.5).timeout
	await shot("ui_dialogue")
	for k in 3:
		w.dialogue._line.visible_ratio = 1.0
		w.dialogue._next()
		await frames(30)
	await shot("ui_dialogue_choice")
	while w.dialogue.active:
		if w.dialogue._choosing:
			w.dialogue._pick(["", []])
		else:
			w.dialogue._line.visible_ratio = 1.0
			w.dialogue._next()
		await frames(3)
	await create_timer(0.6).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(30)
	w.hud.add_feed("단서 2/5 · 흡연카페 할인 쿠폰", Color(1, 0.6, 0.5))
	w.hud.radio("흡연 민원 다수 · 편의점 근처. 파란 빛기둥 보이죠? 거기로 가요.")
	w.hud.money_delta(50)
	w.hud.set_prompt("E  쓰레기 줍기")
	w.hud.set_complaints(2, 5)
	w.hud.set_mission("흡연 민원 다수", "편의점 근처", 85.0, 120.0, 1, 3)
	# 거리 쪽을 본다
	p.global_position = Vector3(-30.0, 0.3, -4.0)
	p.rotation.y = -PI / 2
	await frames(90)
	await shot("ui_hud")
	# 무기 휠
	p.equip("pistol")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	Input.parse_input_event(tab)
	await frames(3)
	w.hud.wheel.feed(Vector2(200, 60))
	await frames(10)
	await shot("ui_wheel")
	tab.pressed = false
	Input.parse_input_event(tab)
	await frames(5)
	# 3인칭으로 거리 사람들 (파출소 앞 인도에서 길을 따라)
	p.set_third_person(true)
	p.global_position = Vector3(-34.0, 0.3, -7.5)
	p.rotation.y = -PI / 2
	await frames(80)
	await shot("ui_street")
	quit()
