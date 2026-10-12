extends SceneTree
## 낮/노을/비 오는 밤, 건물 안, 아지트 급습, 성적표를 찍는다.  godot --path . -s tools/day_shots.gd


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
	game.new_game()
	game.flags["intro"] = true   # 첫날 소장님 대화는 건너뛴다
	game.xp = game.RANK_XP[2]
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	w._start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	p.set_third_person(true)
	# 상가 거리를 따라 보는 자리
	p.global_position = Vector3(-34.0, 0.3, -7.5)
	p.rotation.y = -PI / 2
	w.day.running = false
	for h in [[13.0, false, "day_noon"], [18.6, false, "day_dusk"], [22.5, true, "day_night_rain"]]:
		w.day.hour = h[0]
		w.day.raining = h[1]
		w.day.rain = 1.0 if h[1] else 0.0
		await frames(90)
		await shot(h[2])
	# 1인칭 밤 거리
	p.set_third_person(false)
	p.global_position = Vector3(0, 0.3, 30)
	p.rotation.y = 0
	await frames(60)
	await shot("day_night_street")
	# 건물 안
	w.day.raining = false
	for key in ["station", "store", "smoke_den", "karaoke", "casino"]:
		w.enter_interior(key, w.city.doors[0])
		await frames(60)
		await shot("in_" + key)
		w.exit_interior()
	# 아지트 급습
	game.clues[0] = game.CLUES_NEEDED
	w.crime._reveal(0, true)
	w.crime.start_raid(0)
	p.set_third_person(true)
	await frames(120)
	await shot("in_raid")
	w.exit_interior()
	# 성적표
	w.shift.caught = 14
	w.shift.missions_ok = 2
	w.shift.end_shift()
	await create_timer(1.5, true, false, true).timeout
	await shot("report")
	quit()
