extends SceneTree
## 모든 사건이 켜진 날을 2분 정도 돌려서 실행 중 에러를 잡는다.
func _initialize(): _run.call_deferred()
func _run():
	var game = root.get_node("Game")
	game.new_game()
	game.day = int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 5
	change_scene_to_file("res://scenes/world.tscn")
	for i in 5: await physics_frame
	var w = current_scene
	w._start_shift()
	w.time_left = 999
	for k in w._timers: w._timers[k] = 1.0
	var seen := {}
	for i in 60 * 120:
		await physics_frame
		if i % 600 == 0:
			for n in w.get_tree().get_nodes_in_group("incident"):
				seen[n.task()] = seen.get(n.task(), 0) + 1
	print("day ", game.day, " incident kinds seen: ", seen, " npcs=", w.npcs.get_child_count(), " trash=", w.get_tree().get_nodes_in_group("trash").size())
	game.new_game()
	quit()
