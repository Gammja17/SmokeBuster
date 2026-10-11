extends CanvasLayer
## 화면 UI. 배치는 ui/hud.tscn, 여기서는 값만 갱신한다.

@onready var damage: ColorRect = $Damage
@onready var smoke_overlay: ColorRect = $SmokeOverlay
@onready var indicators: Control = $Indicators
@onready var crosshair: Control = $Crosshair
@onready var hitmarker: Label = $Crosshair/Hitmarker
@onready var zone_label: Label = $BottomRight/Zone
@onready var place_label: Label = $BottomRight/Place
@onready var rank_label: Label = $TopCenter/V/Rank
@onready var next_label: Label = $TopCenter/V/Next
@onready var xp_bar: ProgressBar = $TopCenter/V/Bar/XpBar
@onready var cur_rank: Label = $TopCenter/V/Bar/Cur
@onready var next_rank: Label = $TopCenter/V/Bar/NextRank
@onready var money_label: Label = $TopRight/Money
@onready var wanted_label: Label = $TopRight/Wanted
@onready var combo_label: Label = $TopRight/Combo
@onready var feed: VBoxContainer = $Feed
@onready var radar: Control = $BottomLeft/Radar
@onready var mental_bar: ProgressBar = $BottomLeft/Bars/MentalBar
@onready var weapon_label: Label = $TopRight/Weapon
@onready var ammo_bar: ProgressBar = $BottomLeft/Bars/WaterBar
@onready var ammo_label: Label = $TopRight/Ammo
@onready var truck_box: HBoxContainer = $TopRight/Truck
@onready var truck_bar: ProgressBar = $TopRight/Truck/TruckBar
@onready var wheel: Control = $WeaponWheel
@onready var prompt: Label = $Prompt
@onready var hint: Label = $Hint
@onready var viewfinder: Control = $Viewfinder
@onready var vf_targets: Label = $Viewfinder/Targets
@onready var flash: ColorRect = $Flash
@onready var polaroid: PanelContainer = $Polaroid
@onready var polaroid_photo: TextureRect = $Polaroid/V/Photo
@onready var polaroid_caption: Label = $Polaroid/V/Caption
@onready var announce_label: Label = $Announce
@onready var mission_box: PanelContainer = $TopLeft/Mission
@onready var mission_title: Label = $TopLeft/Mission/V/Title
@onready var mission_info: Label = $TopLeft/Mission/V/Info
@onready var banner_big: Label = $Banner/Big
@onready var banner_small: Label = $Banner/Small

var _banner_tw: Tween
var _announce_tw: Tween
var _polaroid_tw: Tween
var _player: Node3D
var _money_shown := 0.0
var _money_target := 0
var _world: Node
var _place_t := 0.0


func bind(world: Node, player: Node3D) -> void:
	radar.world = world
	radar.player = player
	indicators.player = player
	wheel.player = player
	_player = player
	_world = world


func set_mission(title: String, place: String, left: float, dist: float, done: int, total: int) -> void:
	## 왼쪽 위 출동 정보 (빈 제목이면 숨김)
	mission_box.visible = title != ""
	if title == "":
		return
	mission_title.text = title
	var s := int(max(left, 0.0))
	mission_info.text = "%s · %dm · %d:%02d · %d/%d" % [place, int(dist), s / 60, s % 60, done, total]
	mission_info.modulate = Color(1, 0.45, 0.4) if s <= 15 and s % 2 == 0 else Color.WHITE


func set_driving(on: bool, kind := "") -> void:
	## 운전 중엔 무기 표시를 숨기고, 소방차일 때만 조준점
	weapon_label.visible = not on
	ammo_label.visible = not on
	crosshair.visible = not on or kind == "firetruck"


func set_camera_mode(on: bool) -> void:
	viewfinder.visible = on
	crosshair.visible = not on


func camera_flash() -> void:
	flash.color.a = 0.85
	create_tween().set_ignore_time_scale(true).tween_property(flash, "color:a", 0.0, 0.35)


func show_polaroid(tex: Texture2D, caption: String, good: bool) -> void:
	polaroid_photo.texture = tex
	polaroid_caption.text = caption
	polaroid_caption.add_theme_color_override("font_color", Color(0.1, 0.45, 0.15) if good else Color(0.45, 0.2, 0.2))
	polaroid.visible = true
	polaroid.pivot_offset = polaroid.size / 2
	polaroid.rotation = deg_to_rad(randf_range(-6, 6))
	polaroid.modulate.a = 1.0
	polaroid.position.x = get_viewport().get_visible_rect().size.x
	if _polaroid_tw:
		_polaroid_tw.kill()
	_polaroid_tw = create_tween().set_ignore_time_scale(true)
	_polaroid_tw.tween_property(polaroid, "position:x", get_viewport().get_visible_rect().size.x - 330.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_polaroid_tw.tween_interval(2.6)
	_polaroid_tw.tween_property(polaroid, "modulate:a", 0.0, 0.4)
	_polaroid_tw.tween_callback(func(): polaroid.visible = false)


func set_rank(rank_name: String, zone_name: String, xp: int, lo: int, hi: int) -> void:
	rank_label.text = rank_name
	zone_label.text = zone_name
	cur_rank.text = str(Game.rank() + 1)
	next_rank.text = str(Game.rank() + 2)
	if hi <= lo:
		next_label.text = "최고 계급 · 실적 %d" % xp
		next_rank.text = "★"
		xp_bar.max_value = 1
		xp_bar.value = 1
		return
	next_label.text = "%d / %d" % [xp, hi]
	xp_bar.max_value = hi - lo
	xp_bar.value = xp - lo


func set_money(m: int) -> void:
	_money_target = m


func _process(delta: float) -> void:
	if viewfinder.visible and _player:
		var n: int = _player.photo_targets().size()
		vf_targets.text = ("신고 대상 %d 포착!" % n) if n > 0 else ""
	_money_shown = move_toward(_money_shown, _money_target, max(abs(_money_target - _money_shown) * 8.0, 40.0) * delta)
	money_label.text = _won(int(_money_shown))
	# 오른쪽 아래 현재 위치 (GTA 의 동네/거리 이름 자리)
	_place_t -= delta
	if _place_t <= 0.0 and _world and _player:
		_place_t = 0.5
		place_label.text = _world._place_name(_player.global_position)


func _won(m: int) -> String:
	var s := str(m)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return "₩" + out


func set_combo(mult: float) -> void:
	if mult <= 1.0:
		combo_label.modulate.a = 0.0
		return
	combo_label.text = "콤보 x%.1f" % mult
	combo_label.modulate.a = 1.0
	combo_label.pivot_offset = combo_label.size / 2
	combo_label.scale = Vector2.ONE * 1.4
	create_tween().tween_property(combo_label, "scale", Vector2.ONE, 0.2)


func add_feed(text: String, color := Color.WHITE) -> void:
	## GTA 식 알림: 미니맵 위에 검은 상자로 쌓인다 (새 것이 아래)
	var l := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.62)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 6
	sb.border_width_left = 4
	sb.border_color = color
	l.add_theme_stylebox_override("panel", sb)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", 19)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_child(t)
	feed.add_child(l)
	while feed.get_child_count() > 5:
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func set_mental(cur: int, maximum: int) -> void:
	mental_bar.max_value = maximum
	mental_bar.value = cur
	mental_bar.modulate = Color(1, 0.4, 0.4) if cur <= 1 else Color.WHITE


func set_complaints(cur: int, maximum: int) -> void:
	## 민원은 GTA 의 수배 별처럼
	wanted_label.text = "" if cur <= 0 else "★".repeat(min(cur, 5)) + "☆".repeat(max(5 - cur, 0))
	if cur > 0:
		wanted_label.pivot_offset = Vector2(wanted_label.size.x, wanted_label.size.y / 2)
		wanted_label.scale = Vector2.ONE * 1.3
		create_tween().tween_property(wanted_label, "scale", Vector2.ONE, 0.25)


func set_weapon(id: String) -> void:
	weapon_label.text = Game.WEAPONS[id].name


func set_ammo(id: String, cur: float, maximum: float) -> void:
	ammo_bar.max_value = maximum
	ammo_bar.value = cur
	if Game.WEAPONS[id].mode == "throw":
		ammo_label.text = "%d  /  %d" % [int(cur), int(maximum)]
	else:
		ammo_label.text = "%d  /  %d" % [int(ceil(cur)), int(maximum)]
	ammo_label.modulate = Color(1, 0.4, 0.4) if cur < maximum * 0.2 else Color.WHITE


func set_truck(charge: float) -> void:
	truck_box.visible = false
	truck_bar.value = charge
	truck_box.modulate = Color(1, 1, 1) if charge >= 1.0 else Color(1, 1, 1, 0.6)


func set_prompt(text: String) -> void:
	prompt.text = text


func set_hint(text: String) -> void:
	hint.text = text


func banner(big: String, small := "", duration := 2.5) -> void:
	banner_big.text = big
	banner_small.text = small
	var b: Control = banner_big.get_parent()
	b.modulate.a = 1.0
	b.pivot_offset = b.size / 2
	b.scale = Vector2.ONE * 0.6
	if _banner_tw:
		_banner_tw.kill()
	_banner_tw = create_tween()
	_banner_tw.tween_property(b, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if duration > 0.0:
		_banner_tw.tween_interval(duration)
		_banner_tw.tween_property(b, "modulate:a", 0.0, 0.4)


func hit(strong: bool) -> void:
	hitmarker.modulate = Color(1, 0.9, 0.3, 1) if strong else Color(0.6, 0.9, 1, 0.9)
	hitmarker.scale = Vector2.ONE * (1.6 if strong else 0.8)
	var tw := create_tween()
	tw.tween_property(hitmarker, "scale", Vector2.ONE * (1.0 if strong else 0.6), 0.1)
	tw.parallel().tween_property(hitmarker, "modulate:a", 0.0, 0.35 if strong else 0.15)


func announce(text: String, color := Color(1, 0.85, 0.25)) -> void:
	## 콤보 외침 (더블! 트리플! 물벼락!)
	announce_label.text = text
	announce_label.add_theme_color_override("font_color", color)
	announce_label.modulate.a = 1.0
	announce_label.scale = Vector2.ONE * 2.2
	announce_label.rotation = deg_to_rad(randf_range(-6, 6))
	if _announce_tw:
		_announce_tw.kill()
	_announce_tw = create_tween().set_ignore_time_scale(true)
	_announce_tw.tween_property(announce_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tw.tween_interval(0.7)
	_announce_tw.tween_property(announce_label, "modulate:a", 0.0, 0.3)


func damage_flash(strength := 0.45) -> void:
	damage.color.a = strength
	create_tween().tween_property(damage, "color:a", 0.0, 0.5)


func set_smoke(amount: float) -> void:
	smoke_overlay.color.a = lerp(smoke_overlay.color.a, amount * 0.6, 0.1)
