extends CanvasLayer
## 화면 UI ("112 단말기"). 배치는 ui/hud.tscn, 여기서는 값만 갱신한다.
## 글씨는 최대한 적게: 머리 위 글씨 없이, 꼭 필요한 숫자와 짧은 무전만.

const YEL := Color(1, 0.831, 0)
const RED := Color(1, 0.42, 0.36)

@onready var damage: ColorRect = $Damage
@onready var smoke_overlay: ColorRect = $SmokeOverlay
@onready var indicators: Control = $Indicators
@onready var crosshair: Control = $Crosshair
@onready var hitmarker: Label = $Crosshair/Hitmarker
@onready var clock_label: Label = $TopLeft/Term/V/Head/Clock
@onready var quota_label: Label = $TopLeft/Term/V/Quota
@onready var order_label: Label = $TopLeft/Term/V/Order
@onready var rank_label: Label = $TopLeft/Term/V/RankRow/Rank
@onready var next_label: Label = $TopLeft/Term/V/RankRow/Next
@onready var xp_bar: ProgressBar = $TopLeft/Term/V/XpBar
@onready var mission_box: Control = $TopLeft/Term/V/Mission
@onready var mission_head: Label = $TopLeft/Term/V/Mission/Head
@onready var mission_title: Label = $TopLeft/Term/V/Mission/Title
@onready var mission_info: Label = $TopLeft/Term/V/Mission/Info
@onready var radio_box: Control = $TopLeft/Radio
@onready var radio_who: Label = $TopLeft/Radio/V/Who
@onready var radio_line: Label = $TopLeft/Radio/V/Line
@onready var money_label: Label = $TopRight/Money
@onready var delta_label: Label = $TopRight/Delta
@onready var wanted_label: Label = $TopRight/Wanted
@onready var combo_label: Label = $TopRight/Combo
@onready var truck_box: HBoxContainer = $TopRight/Truck
@onready var truck_bar: ProgressBar = $TopRight/Truck/TruckBar
@onready var feed: VBoxContainer = $Feed
@onready var radar: Control = $BottomLeft/Radar
@onready var mental_bar: ProgressBar = $BottomLeft/Bars/MentalBar
@onready var ammo_bar: ProgressBar = $BottomLeft/Bars/WaterBar
@onready var weapon_label: Label = $BottomRight/Weapon
@onready var ammo_label: Label = $BottomRight/Ammo
@onready var place_label: Label = $BottomRight/Place
@onready var zone_label: Label = $BottomRight/Zone
@onready var district_label: Label = $BottomRight/District
@onready var prompt: Control = $Prompt
@onready var prompt_key: Label = $Prompt/H/Key
@onready var prompt_text: Label = $Prompt/H/Text
@onready var hint: Label = $Hint
@onready var announce_label: Label = $Announce
@onready var banner_box: Control = $Banner
@onready var banner_big: Label = $Banner/H/V/Big
@onready var banner_small: Label = $Banner/H/V/Small
@onready var wheel: Control = $WeaponWheel
@onready var viewfinder: Control = $Viewfinder
@onready var vf_targets: Label = $Viewfinder/Targets
@onready var flash: ColorRect = $Flash
@onready var polaroid: PanelContainer = $Polaroid
@onready var polaroid_photo: TextureRect = $Polaroid/V/Photo
@onready var polaroid_caption: Label = $Polaroid/V/Caption

var _banner_tw: Tween
var _announce_tw: Tween
var _polaroid_tw: Tween
var _delta_tw: Tween
var _radio_tw: Tween
var _radio_queue: Array = []
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
	## 단말기 아래칸 출동 정보 (빈 제목이면 숨김)
	mission_box.visible = title != ""
	if title == "":
		return
	mission_head.text = "출동"
	mission_title.text = title
	var s := int(max(left, 0.0))
	mission_info.text = "%s  %dm  %d:%02d  %d/%d" % [place, int(dist), s / 60, s % 60, done, total]
	mission_info.add_theme_color_override("font_color", RED if s <= 15 else Color(0.62, 0.65, 0.69))


func set_raid(text: String) -> void:
	## 급습 중엔 출동 칸을 쓴다
	mission_box.visible = text != ""
	mission_head.text = "급습"
	mission_title.text = text
	mission_info.text = ""


func set_driving(on: bool, kind := "") -> void:
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
	if hi <= lo:
		next_label.text = "%d" % xp
		xp_bar.max_value = 1
		xp_bar.value = 1
		return
	next_label.text = "%d / %d" % [xp, hi]
	xp_bar.max_value = hi - lo
	xp_bar.value = xp - lo


func set_money(m: int) -> void:
	_money_target = m


func money_delta(amount: int) -> void:
	## 돈 밑에 +50 / -20 이 잠깐
	if amount == 0:
		return
	delta_label.text = ("+%d" if amount > 0 else "%d") % amount
	delta_label.add_theme_color_override("font_color", YEL if amount > 0 else RED)
	delta_label.modulate.a = 1.0
	if _delta_tw:
		_delta_tw.kill()
	_delta_tw = create_tween()
	_delta_tw.tween_interval(1.0)
	_delta_tw.tween_property(delta_label, "modulate:a", 0.0, 0.5)


func _process(delta: float) -> void:
	if viewfinder.visible and _player:
		var n: int = _player.photo_targets().size()
		vf_targets.text = ("포착 %d" % n) if n > 0 else ""
	_money_shown = move_toward(_money_shown, _money_target, max(abs(_money_target - _money_shown) * 8.0, 40.0) * delta)
	money_label.text = _won(int(_money_shown))
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


func set_clock(text: String) -> void:
	clock_label.text = text


func set_quota(text: String, done: bool) -> void:
	quota_label.text = text
	quota_label.add_theme_color_override("font_color", YEL if done else Color(0.91, 0.918, 0.929))


func set_order(text: String, done: bool) -> void:
	## 오늘의 지시 (소장님). 다 채우면 초록
	order_label.visible = text != ""
	order_label.text = text
	order_label.add_theme_color_override("font_color", Color(0.5, 1, 0.6) if done else YEL)


func set_district(text: String) -> void:
	district_label.text = text


func flash_fade() -> void:
	## 문 드나들 때 잠깐 까맣게
	flash.color = Color(0, 0, 0, 1)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(flash, "color:a", 0.0, 0.45)
	tw.tween_callback(func(): flash.color = Color(1, 1, 1, 0))


func set_combo(mult: float) -> void:
	if mult <= 1.0:
		combo_label.modulate.a = 0.0
		return
	combo_label.text = "x%.2f" % mult
	combo_label.modulate.a = 1.0


func add_feed(text: String, color := Color.WHITE) -> void:
	## 짧은 알림: 미니맵 위에 한 줄씩 (최대 3개, 3초)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(l)
	while feed.get_child_count() > 3:
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


func radio(line: String, who := "상황실", optional := false) -> void:
	## 무전 한 줄 (단말기 밑에 잠깐). 여러 개면 차례로.
	## optional: 수다 같은 건 무전이 비어 있을 때만 (도배 방지). 쌓인 게 많으면 오래된 것부터 버린다
	if optional and radio_busy():
		return
	if _radio_queue.size() >= 2:
		_radio_queue.pop_front()
	_radio_queue.append([who, line])
	if not radio_box.visible:
		_next_radio()


func radio_busy() -> bool:
	return radio_box.visible or not _radio_queue.is_empty()


func _next_radio() -> void:
	if _radio_queue.is_empty():
		radio_box.visible = false
		return
	var item: Array = _radio_queue.pop_front()
	radio_who.text = "무전 · " + item[0]
	radio_line.text = item[1]
	radio_box.visible = true
	radio_box.modulate.a = 1.0
	Sfx.play("radio", -10.0)
	if _radio_tw:
		_radio_tw.kill()
	_radio_tw = create_tween()
	_radio_tw.tween_interval(clampf(item[1].length() * 0.07, 2.0, 4.5))
	_radio_tw.tween_property(radio_box, "modulate:a", 0.0, 0.3)
	_radio_tw.tween_callback(_next_radio)


func set_mental(cur: int, maximum: int) -> void:
	mental_bar.max_value = maximum
	mental_bar.value = cur
	mental_bar.modulate = Color(1, 0.4, 0.4) if cur <= 1 else Color.WHITE


func set_complaints(cur: int, maximum: int) -> void:
	wanted_label.text = "" if cur <= 0 else "민원 " + "■".repeat(min(cur, 5)) + "□".repeat(max(5 - cur, 0))


func set_weapon(id: String) -> void:
	weapon_label.text = Game.WEAPONS[id].name


func set_ammo(id: String, cur: float, maximum: float) -> void:
	ammo_bar.max_value = maximum
	ammo_bar.value = cur
	ammo_label.text = "%d / %d" % [int(ceil(cur)), int(maximum)]
	ammo_label.add_theme_color_override("font_color", RED if cur < maximum * 0.2 else Color(0.91, 0.918, 0.929))


func set_truck(charge: float) -> void:
	truck_box.visible = false
	truck_bar.value = charge


func set_prompt(text: String) -> void:
	## "E  쓰레기 줍기" -> [E] 쓰레기 줍기
	prompt.visible = text != ""
	if text == "":
		return
	var parts := text.split("  ", false, 1)
	if parts.size() == 2:
		prompt_key.text = parts[0]
		prompt_text.text = parts[1]
		prompt_key.visible = true
	else:
		prompt_key.visible = false
		prompt_text.text = text
	prompt.reset_size()
	prompt.position.x = (get_viewport().get_visible_rect().size.x - prompt.size.x) / 2


func set_hint(_text: String) -> void:
	## 화면 아래 안내 줄은 쓰지 않는다 (가르치는 건 동료와의 대화로)
	hint.visible = false


func banner(big: String, small := "", duration := 2.5) -> void:
	## 큰 순간에만: 화면을 가로지르는 띠가 미끄러져 들어온다
	banner_big.text = big
	banner_small.text = small
	banner_small.visible = small != ""
	banner_box.visible = true
	banner_box.modulate.a = 1.0
	var h: Control = banner_box.get_node("H")
	h.position.x = -60.0
	if _banner_tw:
		_banner_tw.kill()
	_banner_tw = create_tween().set_ignore_time_scale(true)
	_banner_tw.tween_property(h, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if duration > 0.0:
		_banner_tw.tween_interval(duration)
		_banner_tw.tween_property(banner_box, "modulate:a", 0.0, 0.35)
		_banner_tw.tween_callback(func(): banner_box.visible = false)


func hit(strong: bool) -> void:
	hitmarker.modulate = Color(1, 0.9, 0.3, 1) if strong else Color(0.6, 0.9, 1, 0.9)
	hitmarker.scale = Vector2.ONE * (1.6 if strong else 0.8)
	var tw := create_tween()
	tw.tween_property(hitmarker, "scale", Vector2.ONE * (1.0 if strong else 0.6), 0.1)
	tw.parallel().tween_property(hitmarker, "modulate:a", 0.0, 0.35 if strong else 0.15)


func announce(text: String, color := YEL) -> void:
	## 조준점 밑 짧은 한 마디 (드물게)
	announce_label.text = text
	announce_label.add_theme_color_override("font_color", color)
	announce_label.modulate.a = 1.0
	if _announce_tw:
		_announce_tw.kill()
	_announce_tw = create_tween().set_ignore_time_scale(true)
	_announce_tw.tween_interval(1.0)
	_announce_tw.tween_property(announce_label, "modulate:a", 0.0, 0.3)


func damage_flash(strength := 0.45) -> void:
	damage.color.a = strength
	create_tween().tween_property(damage, "color:a", 0.0, 0.5)


func set_smoke(amount: float) -> void:
	smoke_overlay.color.a = lerp(smoke_overlay.color.a, amount * 0.6, 0.1)
