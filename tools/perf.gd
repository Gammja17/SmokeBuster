extends SceneTree
## 실제 창으로 게임을 띄워 프레임을 잰다 (vsync 끔). 하나씩 꺼 보며 뭐가 무거운지 본다.
## godot --path . -s tools/perf.gd


func _initialize() -> void:
	_run.call_deferred()


func measure(label: String, frames := 240) -> void:
	for i in 30:
		await process_frame
	var t0 := Time.get_ticks_usec()
	var proc := 0.0
	var phys := 0.0
	var draws := 0.0
	var prims := 0.0
	for i in frames:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	print("%-26s %6.2f ms (%5.0f fps)  cpu proc %.2f  phys %.2f  draws %5.0f  tris %7.0fk" % [
		label, ms, 1000.0 / ms, proc / frames * 1000, phys / frames * 1000, draws / frames, prims / frames / 1000])


func stutter(w: Node, p: Node3D) -> void:
	## 20초 동안 동네 여기저기로 순간이동하며 (행인이 계속 새로 생김) 가장 느린 프레임을 잰다
	var times: Array[float] = []
	var spots := [Vector3(-40, 0.3, -40), Vector3(40, 0.3, 30), Vector3(0, 0.3, -50), Vector3(-50, 0.3, 20), Vector3(30, 0.3, -20)]
	var last := Time.get_ticks_usec()
	var t := 0
	while times.size() < 2400:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		t += 1
		if t % 240 == 0:
			p.global_position = spots[(t / 240) % spots.size()]
	var sorted := times.duplicate()
	sorted.sort()
	var hitches := times.filter(func(x): return x > 33.0).size()
	print("STUTTER avg %.2f  p99 %.2f  max %.1f ms  hitches(>33ms) %d" % [
		times.reduce(func(a, b): return a + b) / times.size(), sorted[int(sorted.size() * 0.99)], sorted[-1], hitches])


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var game = root.get_node("Game")
	game.new_game()
	game.xp = game.RANK_XP[3]
	var args := OS.get_cmdline_user_args()
	game.quality = int(args[0]) if args.size() > 0 else 2
	change_scene_to_file("res://scenes/world.tscn")
	for i in 10:
		await process_frame
	var w = current_scene
	w._start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p = w.player
	# 큰길 가운데에서 길 따라 멀리 보는, 가장 많이 그려지는 장면
	p.global_position = Vector3(0, 0.3, 40)
	p.rotation.y = 0
	p.input_enabled = false
	await measure("warmup", 120)
	print("npc %d" % w.get_tree().get_nodes_in_group("npc").size())
	await stutter(w, p)
	await measure("baseline")
	var env: Environment = w.get_node("Env").environment
	for n in w.get_tree().get_nodes_in_group("npc"):
		n._anim.active = false
	await measure("- npc anim")
	for n in w.get_tree().get_nodes_in_group("npc"):
		n.visible = false
	await measure("- npc draw")
	for n in w.get_tree().get_nodes_in_group("npc"):
		n.set_physics_process(false)
	await measure("- npc physics")
	env.volumetric_fog_enabled = false
	await measure("- volumetric fog")
	env.ssil_enabled = false
	await measure("- ssil")
	env.ssao_enabled = false
	await measure("- ssao")
	env.ssr_enabled = false
	await measure("- ssr")
	env.glow_enabled = false
	await measure("- glow")
	for l in w.find_children("*", "DirectionalLight3D", true, false):
		l.shadow_enabled = false
	await measure("- sun shadow")
	for l in w.find_children("*", "OmniLight3D", true, false) + w.find_children("*", "SpotLight3D", true, false):
		l.visible = false
	await measure("- omni/spot lights")
	quit()
