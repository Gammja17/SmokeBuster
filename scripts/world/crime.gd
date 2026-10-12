class_name Crime
extends Node3D
## 구역 정화도와 범죄 조직.
## - 단속하면 그 구역 정화도가 오르고, 가끔 조직 단서가 나온다.
## - 단서가 다 모이면 아지트 문이 드러나고, 들어가서 일당과 두목을 잡으면 그 구역이 확 깨끗해진다.
## - 정화도가 낮으면 낙서, 꽁초, 문 닫은 가게(임대문의)가 많고, 높으면 주민이 인사한다.

const CLUE_ALWAYS := ["thief", "shop", "fight"]
const TAGS := ["담배파 구역", "ㅋㅋㅋ", "흡연 자유", "NEON", "후드단", "XX 참교육", "여기 우리 땅", "민지 사랑해", "꺼져"]
const THANKS := ["순경님 덕분에 살 만해요!", "요즘 골목이 깨끗해졌어요", "고생 많으십니다!", "우리 동네 지킴이!", "덕분에 장사 잘 돼요"]
const RAID_POOLS := [
	["m_hiker", "m_office", "m_gamer", "m_worker", "f_ajumma"],
	["m_drunk", "m_track", "f_trench", "m_office"],
	["m_thug", "m_track", "m_thief", "m_drunk"],
	["m_delivery", "m_track", "m_college", "m_jogger"],
	["m_thug", "m_office", "f_trench", "s_shady", "m_track"],
]

var world: Node
var hideouts := {}           # 구역 번호 -> 문 dict
var raid := {}               # 진행 중인 급습 {gang, targets}
var _deco: Array[Node] = []
var _thank_t := 6.0


func setup(w: Node) -> void:
	world = w
	for i in Game.GANGS.size():
		if Game.clues[i] >= Game.CLUES_NEEDED and not Game.raided[i] and i <= world.cfg.zone:
			_reveal(i, false)
	refresh_visuals()


# ---------------------------------------------------------------- 단속 결과

func on_catch(task: String, pos: Vector3, npc: Node = null) -> void:
	if world.inside != "":
		return
	var i := Game.district_of(pos)
	Game.add_clean(i, 0.4 if task == "trash" else 1.6)
	if task == "trash" or Game.raided[i] or Game.clues[i] >= Game.CLUES_NEEDED:
		return
	var chance := 1.0 if task in CLUE_ALWAYS or (npc and npc.kind == "boss") else 0.18
	if randf() < chance:
		Game.clues[i] += 1
		var gang: Dictionary = Game.GANGS[i]
		world.hud.announce("단서 획득!  %s %d/%d" % [gang.name, Game.clues[i], Game.CLUES_NEEDED], Color(1, 0.45, 0.35))
		world.hud.add_feed("단서: %s" % _clue_text(i), Color(1, 0.6, 0.5))
		Sfx.play("radio", -4.0)
		if Game.clues[i] >= Game.CLUES_NEEDED:
			_reveal(i, true)


func _clue_text(i: int) -> String:
	var bits := [
		["\"골초왕이 지하에서 판을 벌인대요\"", "담배 상자에 찍힌 같은 도장", "꽁초 봉투에 적힌 주소 일부", "흡연카페 할인 쿠폰", "지하 계단 앞에서 본 연기"],
		["\"사장님한테 상납했어요\"", "보라색 네온 영수증", "노래방 회원 카드", "새벽 3시 영업 전단", "같은 번호로 걸려 온 전화"],
		["검은 후드에 새긴 마크", "도박 칩 하나", "\"행동대장이 시켰어요\"", "지하 주차장 열쇠", "판돈 장부 한 장"],
		["번호판 없는 오토바이", "\"대장이 주차장에서 기다려요\"", "배달통 속 담배 보루", "엔진 오일 묻은 장갑", "주차장 출입 카드"],
		["금박 명함 \"꽁초 대부\"", "옥상 엘리베이터 카드", "카르텔 장부 사본", "\"모든 담배파 위에 대부가 있다\"", "VIP 라운지 초대장"],
	]
	return bits[i][(Game.clues[i] - 1) % 5]


func on_complaint(pos: Vector3) -> void:
	Game.add_clean(Game.district_of(pos), -3.0)


func on_mission(pos: Vector3, ok: bool) -> void:
	if ok:
		Game.add_clean(Game.district_of(pos), 5.0)


# ---------------------------------------------------------------- 아지트

func _reveal(i: int, announce: bool) -> void:
	if hideouts.has(i):
		return
	var slot := _hideout_slot(i)
	if slot.is_empty():
		return
	slot.used = true
	var gang: Dictionary = Game.GANGS[i]
	var door := {"role": "hideout", "gang": i, "pos": slot.pos + slot.normal * 1.0, "normal": slot.normal,
		"label": "E  %s 급습! (%s)" % [gang.place, gang.name]}
	hideouts[i] = door
	# 문: 검은 철문, 붉은 등, 수상한 간판
	var root := Node3D.new()
	world.add_child(root)
	root.global_position = slot.pos + slot.normal * 0.05
	root.look_at(root.global_position - slot.normal, Vector3.UP)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 2.4, 0.12)
	m.mesh = bm
	m.material_override = Mats.flat(Color(0.08, 0.08, 0.09), 0.4, 0.7)
	m.position = Vector3(0, 1.2, 0.06)
	root.add_child(m)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.15, 0.1)
	light.light_energy = 3.0
	light.omni_range = 5.0
	light.position = Vector3(0, 2.7, 0.6)
	root.add_child(light)
	var l := Label3D.new()
	l.text = "%s\n▼" % gang.place
	l.font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	l.font_size = 72
	l.pixel_size = 0.006
	l.outline_size = 10
	l.modulate = Color(1, 0.3, 0.25)
	l.position = Vector3(0, 3.2, 0.3)
	root.add_child(l)
	door.node = root
	var tw := root.create_tween().set_loops()
	tw.tween_property(light, "light_energy", 0.8, 0.6)
	tw.tween_property(light, "light_energy", 3.0, 0.6)
	world.refresh_doors()
	if announce:
		world.hud.banner("아지트 발견!", "%s의 %s 위치가 드러났어요\n미니맵의 빨간 문으로 가서 E" % [gang.name, gang.place], 3.5)
		Sfx.play("fanfare", -2.0)


func _hideout_slot(i: int) -> Dictionary:
	## 그 구역(안쪽 구역 바깥)의 비어 있는 건물 앞. 매번 같은 자리가 나오게 정렬해서 고른다.
	var inner: Rect2 = Game.ZONES[i - 1].rect if i > 0 else Rect2()
	var cands: Array = []
	for s in world.city.shop_slots:
		var p2 := Vector2(s.pos.x, s.pos.z)
		if s.used or not Game.ZONES[i].rect.has_point(p2) or (i > 0 and inner.has_point(p2)):
			continue
		cands.append(s)
	if cands.is_empty():
		return {}
	cands.sort_custom(func(a, b): return a.pos.x + a.pos.z * 0.37 < b.pos.x + b.pos.z * 0.37)
	return cands[(i * 7 + 3) % cands.size()]


func start_raid(i: int) -> void:
	var gang: Dictionary = Game.GANGS[i]
	var room: Dictionary = world.interiors.rooms[gang.hideout]
	world.enter_interior(gang.hideout, hideouts[i])
	if not raid.is_empty():
		return
	raid = {"gang": i, "targets": []}
	var spots: Array = room.spots.duplicate()
	spots.shuffle()
	var count := mini(5 + i * 2, spots.size())
	for k in count:
		var n: Npc = world._new_npc("angry" if randf() < 0.35 + i * 0.15 else "normal")
		n.force_model = RAID_POOLS[i].pick_random()
		n.interior = true
		n.position = spots[k]
		n.rotation.y = randf() * TAU
		world.npcs.add_child(n)
		raid.targets.append(n)
	var boss: Npc = world._new_npc("boss")
	boss.force_model = gang.model
	boss.title = gang.boss
	boss.interior = true
	boss.position = room.boss
	world.npcs.add_child(boss)
	raid.targets.append(boss)
	world.hud.banner("급습!", "%s 일당 %d명과 두목 %s\n전부 물로 제압하세요" % [gang.name, count, gang.boss], 2.5)
	Sfx.play("bong")


func _process(delta: float) -> void:
	if world == null or not world.playing:
		return
	if not raid.is_empty():
		var left := 0
		for n in raid.targets:
			if is_instance_valid(n) and not n.done:
				left += 1
		world.hud.set_hint("남은 일당 %d명" % left if left > 0 else "")
		if left == 0:
			_raid_done()
	_thank_t -= delta
	if _thank_t <= 0.0:
		_thank_t = randf_range(7.0, 12.0)
		_thank()


func _raid_done() -> void:
	var i: int = raid.gang
	raid = {}
	var gang: Dictionary = Game.GANGS[i]
	Game.raided[i] = true
	Game.add_clean(i, 30.0)
	var reward := 1500 * (i + 1)
	world._complete("shop", "%s 일망타진!" % gang.name, world.player.global_position, reward)
	world.shift.raid_today = i
	world.hud.banner("급습 성공!", "%s 두목 %s 검거!\n%s 정화도 +30" % [gang.name, gang.boss, Game.ZONES[i].name.get_slice(" ", 0)], 3.5)
	Sfx.play("fanfare", 0.0)
	var door: Dictionary = hideouts[i]
	door.label = "E  밖으로 (아지트 정리 완료)"
	hideouts.erase(i)
	if door.has("node") and is_instance_valid(door.node):
		door.node.queue_free()
	world.refresh_doors()
	Game.save_game()
	refresh_visuals()


func _thank() -> void:
	## 깨끗한 구역에서는 지나가던 주민이 손 흔들며 고마워한다
	if world.inside != "":
		return
	var p: Vector3 = world.player.global_position
	if Game.clean[Game.district_of(p)] < 50.0:
		return
	for n in world.get_tree().get_nodes_in_group("npc"):
		if n.kind == "ped" and not n.done and n.global_position.distance_to(p) < 7.0:
			n._play("wave")
			n.say(THANKS.pick_random(), Color(0.7, 1, 0.75))
			return


# ---------------------------------------------------------------- 동네 모습

func refresh_visuals() -> void:
	## 정화도에 따라 낙서, 꽁초, 문 닫은 가게 수를 바꾼다
	for d in _deco:
		if is_instance_valid(d):
			d.queue_free()
	_deco.clear()
	var city: CityBuilder = world.city
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	# 문 닫은 가게: 정화도 40 미만이면 그만큼 "임대문의"
	for s in city.shop_signs:
		var c: float = Game.clean[Game.district_of(s.pos)]
		var closed := rng.randf() < clampf((45.0 - c) / 45.0, 0.0, 1.0) * 0.6
		s.label.text = "임대문의" if closed else s.name
		s.label.modulate = Color(0.75, 0.75, 0.75) if closed else Color.WHITE
	# 벽 낙서
	var font: Font = load("res://assets/fonts/Pretendard-ExtraBold.otf")
	for s in city.shop_slots:
		var c: float = Game.clean[Game.district_of(s.pos)]
		var n := int((100.0 - c) / 30.0)
		for k in n:
			var l := Label3D.new()
			l.text = TAGS[rng.randi() % TAGS.size()]
			l.font = font
			l.font_size = rng.randi_range(60, 110)
			l.pixel_size = 0.006
			l.outline_size = 0
			l.modulate = Color.from_hsv(rng.randf(), 0.75, 0.95, 0.9)
			l.double_sided = false
			world.add_child(l)
			var side: Vector3 = s.normal.cross(Vector3.UP).normalized()
			l.global_position = s.pos + s.normal * 0.06 + side * rng.randf_range(2.0, 4.5) * (1 if rng.randf() < 0.5 else -1) + Vector3.UP * rng.randf_range(0.9, 2.2)
			l.look_at(l.global_position - s.normal, Vector3.UP)
			l.rotate_object_local(Vector3.FORWARD, rng.randf_range(-0.25, 0.25))
			l.visibility_range_end = 45.0
			_deco.append(l)
	# 꽁초 (작은 흰 막대 여러 개를 한 번에 그린다)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var stick := BoxMesh.new()
	stick.size = Vector3(0.02, 0.02, 0.07)
	stick.material = Mats.flat(Color(0.9, 0.85, 0.75), 0.9)
	mm.mesh = stick
	var xfs: Array[Transform3D] = []
	for k in 900:
		var p: Vector3 = city.random_sidewalk_point()
		var c: float = Game.clean[Game.district_of(p)]
		if rng.randf() * 100.0 < c + 15.0:
			continue
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		xfs.append(Transform3D(b, p + Vector3(rng.randf_range(-1, 1), 0.07, rng.randf_range(-1, 1))))
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mmi)
	_deco.append(mmi)
