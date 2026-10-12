extends SceneTree
## 파출소 앞 동료들과 3인칭 플레이어 몸을 찍는다.  godot --path . -s tools/station_shots.gd


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/shots/" + name + ".png")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game = root.get_node("Game")
	game.new_game()
	game.flags["intro"] = true   # 첫날 소장님 대화는 건너뛴다
	change_scene_to_file("res://scenes/world.tscn")
	await frames(20)
	var w = current_scene
	w._start()
	w.cfg.events = false
	w._mission_t = 999.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	await frames(40)

	# 파출소 앞 동료들 (1인칭, 길가에서 정문 쪽)
	p.global_position = Vector3(-18.5, 0.3, -1.5)
	p.rotation.y = 0
	p.camera.rotation = Vector3(deg_to_rad(-4), 0, 0)
	await frames(90)
	await shot("station_coworkers")

	# 3인칭: 동료 앞에 선 내 캐릭터
	p.global_position = Vector3(-20.0, 0.3, -4.5)
	p.rotation.y = PI * 0.85
	p.set_third_person(true)
	await frames(60)
	await shot("third_person")
	quit()
