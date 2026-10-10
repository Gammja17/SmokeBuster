extends CanvasLayer
## 화면 UI. 배치는 ui/hud.tscn, 여기서는 값만 갱신한다.

@onready var damage: ColorRect = $Damage
@onready var smoke_overlay: ColorRect = $SmokeOverlay
@onready var indicators: Control = $Indicators
@onready var crosshair: Control = $Crosshair
@onready var hitmarker: Label = $Crosshair/Hitmarker
@onready var day_label: Label = $TopCenter/V/Day
@onready var timer_label: Label = $TopCenter/V/Timer
@onready var quota_label: Label = $TopCenter/V/Quota
@onready var quota_bar: ProgressBar = $TopCenter/V/QuotaBar
@onready var money_label: Label = $TopLeft/Money
@onready var combo_label: Label = $TopLeft/Combo
@onready var feed: VBoxContainer = $TopLeft/Feed
@onready var radar: Control = $Radar
@onready var mental_label: Label = $BottomLeft/V/Mental
@onready var complaints_label: Label = $BottomLeft/V/Complaints
@onready var weapon_label: Label = $BottomRight/V/Weapon
@onready var ammo_bar: ProgressBar = $BottomRight/V/AmmoBar
@onready var ammo_label: Label = $BottomRight/V/Ammo
@onready var slots: HBoxContainer = $BottomRight/V/Slots
@onready var truck_box: HBoxContainer = $BottomRight/V/Truck
@onready var truck_bar: ProgressBar = $BottomRight/V/Truck/TruckBar
@onready var prompt: Label = $Prompt
@onready var hint: Label = $Hint
@onready var banner_big: Label = $Banner/Big
@onready var banner_small: Label = $Banner/Small

var _banner_tw: Tween
var _money_shown := 0.0
var _money_target := 0


func bind(world: Node, player: Node3D) -> void:
	radar.world = world
	radar.player = player
	indicators.player = player


func set_day(text: String) -> void:
	day_label.text = text


func set_time(sec: float) -> void:
	var s := int(ceil(max(sec, 0.0)))
	timer_label.text = "%d:%02d" % [s / 60, s % 60]
	timer_label.modulate = Color(1, 0.4, 0.35) if s <= 15 and s % 2 == 0 else Color.WHITE


func set_quota(caught: int, quota: int) -> void:
	quota_label.text = "단속 %d / %d" % [caught, quota]
	quota_bar.max_value = quota
	quota_bar.value = min(caught, quota)
	if caught >= quota:
		quota_label.modulate = Color(0.5, 1, 0.5)


func set_money(m: int) -> void:
	_money_target = m


func _process(delta: float) -> void:
	_money_shown = move_toward(_money_shown, _money_target, max(abs(_money_target - _money_shown) * 8.0, 40.0) * delta)
	money_label.text = "%d원" % int(_money_shown)


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
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 22)
	feed.add_child(l)
	feed.move_child(l, 0)
	while feed.get_child_count() > 5:
		feed.get_child(feed.get_child_count() - 1).queue_free()
		feed.remove_child(feed.get_child(feed.get_child_count() - 1))
	var tw := l.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func set_mental(cur: int, maximum: int) -> void:
	mental_label.text = "멘탈 " + "♥".repeat(cur) + "♡".repeat(maximum - cur)


func set_complaints(cur: int, maximum: int) -> void:
	complaints_label.text = "민원 " + "●".repeat(cur) + "○".repeat(maximum - cur)
	if cur > 0:
		complaints_label.pivot_offset = complaints_label.size / 2
		complaints_label.scale = Vector2.ONE * 1.25
		create_tween().tween_property(complaints_label, "scale", Vector2.ONE, 0.25)


func set_weapon(id: String) -> void:
	weapon_label.text = Game.WEAPONS[id].name
	for i in Game.WEAPON_ORDER.size():
		var wid: String = Game.WEAPON_ORDER[i]
		var slot: Label = slots.get_child(i)
		if wid in Game.owned:
			slot.text = "%d %s" % [i + 1, Game.WEAPONS[wid].name]
			slot.modulate = Color(1, 0.95, 0.5) if wid == id else Color(1, 1, 1, 0.6)
		else:
			slot.text = "%d -" % (i + 1)
			slot.modulate = Color(1, 1, 1, 0.25)


func set_ammo(id: String, cur: float, maximum: float) -> void:
	ammo_bar.max_value = maximum
	ammo_bar.value = cur
	if Game.WEAPONS[id].mode == "throw":
		ammo_label.text = "양동이 %d / %d" % [int(cur), int(maximum)]
	else:
		ammo_label.text = "물 %d / %d" % [int(ceil(cur)), int(maximum)]
	ammo_label.modulate = Color(1, 0.4, 0.4) if cur < maximum * 0.2 else Color.WHITE


func set_truck(charge: float) -> void:
	truck_box.visible = Game.has_truck
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


func damage_flash(strength := 0.45) -> void:
	damage.color.a = strength
	create_tween().tween_property(damage, "color:a", 0.0, 0.5)


func set_smoke(amount: float) -> void:
	smoke_overlay.color.a = lerp(smoke_overlay.color.a, amount * 0.6, 0.1)
