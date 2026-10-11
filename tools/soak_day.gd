extends SceneTree
## 계급별로 자유 순찰을 90초 돌려 실행 중 에러와 사건 밀도를 본다.
## godot --headless --path . -s tools/soak_day.gd -- <계급 0~6>
func _initialize(): _run.call_deferred()
func _run():
	var game = root.get_node("Game")
	game.new_game()
	var r := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 3
	game.xp = game.RANK_XP[r]
	change_scene_to_file("res://scenes/world.tscn")
	for i in 5: await physics_frame
	var w = current_scene
	w._start()
	w._event_t = 5.0
	var seen := {}
	var active_sum := 0
	var samples := 0
	for i in 60 * 90:
		await physics_frame
		if i % 300 == 0:
			for n in w.get_tree().get_nodes_in_group("incident"):
				seen[n.task()] = seen.get(n.task(), 0) + 1
			active_sum += w._active_total()
			samples += 1
	print("rank ", game.rank_name(), " kinds: ", seen, " avg active=%.1f npcs=%d trash=%d" % [float(active_sum) / samples, w.npcs.get_child_count(), w.get_tree().get_nodes_in_group("trash").size()])
	game.new_game()
	quit()
