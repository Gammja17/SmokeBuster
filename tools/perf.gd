extends SceneTree
func _initialize(): _run.call_deferred()
func measure(label: String, frames := 120) -> void:
	var proc := 0.0; var phys := 0.0
	for i in frames:
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	print("%-28s process %.2f ms  physics %.2f ms" % [label, proc / frames * 1000, phys / frames * 1000])
func _run():
	var game = root.get_node("Game")
	game.day = 5
	change_scene_to_file("res://scenes/world.tscn")
	for i in 10: await physics_frame
	var w = current_scene
	w._start_shift()
	await measure("warmup", 200)
	await measure("baseline")
	await measure("baseline2")
	w.hud.radar.set_process(false); w.hud.indicators.set_process(false)
	await measure("- radar/indicators")
	w.hud.set_process(false)
	await measure("- hud")
	for n in w.npcs.get_children():
		if n.has_method("soak"):
			n.set_physics_process(false)
	await measure("- npc physics")
	for n in w.npcs.get_children():
		var ap = n.find_child("AnimationPlayer", true, false)
		if ap: ap.active = false
	await measure("- npc anim")
	for c in w.get_children():
		if c is AnimatableBody3D: c.set_physics_process(false)
	await measure("- traffic")
	w.water.set_physics_process(false)
	for c in w.water.get_children(): c.set_process(false)
	await measure("- water")
	w.set_process(false)
	await measure("- world")
	w.player.set_physics_process(false)
	await measure("- player")
	game.new_game()
	quit()
