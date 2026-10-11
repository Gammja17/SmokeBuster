extends SceneTree
## VARCO 애니메이션 GLB 들에서 애니메이션만 뽑아 하나의 AnimationLibrary 로 저장한다.
## godot --headless --path . -s tools/build_anims.gd
## 입력: res://assets/people/anims/<이름>.glb   출력: res://assets/people/anim_lib.res

const LOOPING := ["idle", "walk", "jog", "run", "sprint", "salute", "talk", "drink", "angry", "wave", "breathe"]


func _initialize() -> void:
	var lib := AnimationLibrary.new()
	var dir := DirAccess.open("res://assets/people/anims")
	for f in dir.get_files():
		if not f.ends_with(".glb"):
			continue
		var name := f.get_basename()
		var scene: Node = load("res://assets/people/anims/" + f).instantiate()
		var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		if ap == null or ap.get_animation_list().is_empty():
			print("no anim in ", f)
			scene.free()
			continue
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR if name in LOOPING else Animation.LOOP_NONE
		lib.add_animation(name, anim)
		print(name, " len=%.2f tracks=%d" % [anim.length, anim.get_track_count()])
		scene.free()
	var err := ResourceSaver.save(lib, "res://assets/people/anim_lib.res")
	print("saved ", err, " count=", lib.get_animation_list().size())
	quit()
