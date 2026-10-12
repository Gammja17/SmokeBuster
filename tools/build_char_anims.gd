extends SceneTree
## 공용 anim_lib 를 캐릭터마다 자기 뼈대에 맞춰 다시 구워 assets/people/baked/<이름>.res 로 저장한다.
## godot --headless --path . -s tools/build_char_anims.gd [-- 이름 ...]
##
## anim_lib 는 원본 경찰 리그 하나에서 뽑은 로컬 회전이라, 뼈 휴식자세가 다른 몸에 그대로 쓰면
## 쇄골/목/발이 틀어진다. VARCO 가 캐릭터마다 직접 만든 애니와 비교해서 맞춘 규칙:
##   - 상완/전완/손: 원본의 전역 회전 그대로
##   - 나머지: 전역 회전 변화량을 옮김  G = A_src * R_src^-1 * R_tgt
## 손가락은 VARCO 애니에 없어서 살짝 말린 고정 자세를 넣는다 (로컬 +X 가 손바닥 쪽, 엄지 제외).

const SRC_REST := "res://assets/people/anim_src_rest.res"
const SRC_GLB := "res://assets/rt_raw/r_idle.glb"
const OUT := "res://assets/people/baked/%s.res"
const AS_IS := ["LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"]
const CURL_BASE := 0.35   # 손가락 첫 마디
const CURL_TIP := 0.55    # 나머지 마디


func _initialize() -> void:
	var src := _src_rest()
	var lib: AnimationLibrary = load("res://assets/people/anim_lib.res")
	var names := Array(OS.get_cmdline_user_args())
	if names.is_empty():
		for f in DirAccess.get_files_at("res://assets/people"):
			if f.ends_with(".glb") and f != "player_f.glb":
				names.append(f.get_basename())
	DirAccess.make_dir_recursive_absolute("res://assets/people/baked")
	for n in names:
		var t0 := Time.get_ticks_msec()
		var m: Node = load("res://assets/people/%s.glb" % n).instantiate()
		var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
		var out := AnimationLibrary.new()
		for an in lib.get_animation_list():
			out.add_animation(an, _bake(lib.get_animation(an), src, sk))
		var err := ResourceSaver.save(out, OUT % n, ResourceSaver.FLAG_COMPRESS)
		print(n, " bones=", sk.get_bone_count(), " err=", err, " %dms" % (Time.get_ticks_msec() - t0))
		m.free()
	quit()


## 원본 리그의 뼈 이름/부모/휴식 회전. 처음 한 번 r_idle.glb 에서 뽑아 저장해 둔다.
func _src_rest() -> Dictionary:
	if ResourceLoader.exists(SRC_REST):
		return load(SRC_REST).get_meta("rest")
	var m: Node = load(SRC_GLB).instantiate()
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var d := {"names": [], "parents": [], "rest": []}
	for i in sk.get_bone_count():
		d.names.append(sk.get_bone_name(i))
		d.parents.append(sk.get_bone_parent(i))
		d.rest.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
	m.free()
	var r := Resource.new()
	r.set_meta("rest", d)
	ResourceSaver.save(r, SRC_REST)
	return d


func _globals(local: Array, parents: Array) -> Array:
	var g := []
	g.resize(local.size())
	for i in local.size():
		g[i] = local[i] if parents[i] < 0 else g[parents[i]] * local[i]
	return g


func _bake(a: Animation, src: Dictionary, sk: Skeleton3D) -> Animation:
	var ns: int = src.names.size()
	var nt := sk.get_bone_count()
	var s_rest_g := _globals(src.rest, src.parents)
	var t_par := []
	var t_rest := []
	var map := []   # 타깃 뼈 -> 원본 뼈 (없으면 -1)
	for j in nt:
		t_par.append(sk.get_bone_parent(j))
		t_rest.append(sk.get_bone_rest(j).basis.get_rotation_quaternion())
		map.append(src.names.find(sk.get_bone_name(j)))
	var t_rest_g := _globals(t_rest, t_par)
	# 원본 트랙
	var s_track := []
	s_track.resize(ns)
	s_track.fill(-1)
	var times := PackedFloat64Array()
	for k in a.get_track_count():
		if a.track_get_type(k) != Animation.TYPE_ROTATION_3D:
			continue
		var i: int = src.names.find(str(a.track_get_path(k)).get_slice(":", 1))
		if i >= 0:
			s_track[i] = k
			if times.is_empty():
				for key in a.track_get_key_count(k):
					times.append(a.track_get_key_time(k, key))
	var b := Animation.new()
	b.length = a.length
	b.loop_mode = a.loop_mode
	# 위치 트랙 (엉덩이) 은 그대로
	for k in a.get_track_count():
		if a.track_get_type(k) == Animation.TYPE_POSITION_3D:
			a.copy_track(k, b)
	var out_track := []
	for j in nt:
		var k := b.add_track(Animation.TYPE_ROTATION_3D)
		b.track_set_path(k, NodePath("Skeleton3D:" + sk.get_bone_name(j)))
		out_track.append(k)
	for t in times:
		var s_local := []
		for i in ns:
			s_local.append(a.rotation_track_interpolate(s_track[i], t) if s_track[i] >= 0 else src.rest[i])
		var s_g := _globals(s_local, src.parents)
		var t_g := []
		t_g.resize(nt)
		for j in nt:
			var i: int = map[j]
			var p: int = t_par[j]
			var q: Quaternion
			if i < 0:
				q = t_rest[j]
				var bn := sk.get_bone_name(j)
				if bn.contains("_Finger") and not bn.contains("_Finger0"):   # 엄지는 그대로
					var tip := bn.length() > bn.find("_Finger") + 8   # Finger1 은 첫 마디, Finger11/12 는 그 다음
					q = q * Quaternion(Vector3.RIGHT, CURL_TIP if tip else CURL_BASE)
				t_g[j] = q if p < 0 else t_g[p] * q
			else:
				t_g[j] = s_g[i] if sk.get_bone_name(j) in AS_IS else s_g[i] * s_rest_g[i].inverse() * t_rest_g[j]
				q = t_g[j] if p < 0 else t_g[p].inverse() * t_g[j]
			b.rotation_track_insert_key(out_track[j], t, q.normalized())
	# 변하지 않는 트랙 (손가락 등) 은 키 하나로
	for j in nt:
		var k: int = out_track[j]
		var c := b.track_get_key_count(k)
		if c > 1 and map[j] < 0:
			for key in range(c - 1, 0, -1):
				b.track_remove_key(k, key)
	b.compress()
	return b
