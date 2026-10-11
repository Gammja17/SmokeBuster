extends Control
## 장비실. 순찰 중 Tab 으로 열어 무기 구매, 강화, 소방차 호출권을 산다.

const ITEM := preload("res://ui/shop_item.tscn")

@onready var _money: Label = $M/V/Header/Money
@onready var _brief: Label = $M/V/Brief
@onready var _weapons: VBoxContainer = $M/V/Cols/Weapons/Scroll/List
@onready var _upgrades: VBoxContainer = $M/V/Cols/Upgrades/Scroll/List

signal closed


func _ready() -> void:
	$M/V/Footer/Start.pressed.connect(func():
		Sfx.play("click")
		closed.emit())
	$M/V/Footer/ToTitle.pressed.connect(func():
		Sfx.play("click")
		Game.save_game()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/title.tscn"))
	refresh()


func _input(event: InputEvent) -> void:
	# Tab/Esc 로 닫기 (Tab 은 GUI 포커스 이동보다 먼저 잡는다)
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_TAB, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		closed.emit()


func refresh() -> void:
	var span: Array = Game.rank_span()
	var next := "최고 계급" if span[1] <= span[0] else "다음 승진까지 실적 %d" % (span[1] - Game.xp)
	_brief.text = "%s · %s · %s" % [Game.rank_name(), Game.ZONES[Game.zone_for_rank(Game.rank())].name, next]
	_refresh()


func _refresh() -> void:
	_money.text = "%d원" % Game.money
	for c in _weapons.get_children():
		c.queue_free()
	for c in _upgrades.get_children():
		c.queue_free()

	for id in Game.WEAPON_ORDER:
		var w: Dictionary = Game.WEAPONS[id]
		var item := ITEM.instantiate()
		_weapons.add_child(item)
		var owned: bool = id in Game.owned
		var label := "보유중" if owned else "%d원" % w.price
		item.setup(w.name, w.desc, label, not owned and Game.money >= w.price)
		item.buy.connect(_buy_weapon.bind(id))

	var truck := ITEM.instantiate()
	_weapons.add_child(truck)
	truck.setup("소방차 키", "파출소 앞에 소방차가 생긴다. F로 타서 운전하며 지붕 물대포를 쏜다!",
		"보유중" if Game.has_truck else "%d원" % Game.TRUCK_PRICE, not Game.has_truck and Game.money >= Game.TRUCK_PRICE)
	truck.buy.connect(_buy_truck)

	for key in Game.UPGRADES:
		var u: Dictionary = Game.UPGRADES[key]
		var lvl: int = Game.upgrades[key]
		var prices: Array = u.prices
		var item := ITEM.instantiate()
		_upgrades.add_child(item)
		var title := "%s  Lv.%d/%d" % [u.name, lvl, prices.size()]
		if lvl >= prices.size():
			item.setup(title, u.desc, "최대", false)
		else:
			item.setup(title, u.desc, "%d원" % prices[lvl], Game.money >= prices[lvl])
		item.buy.connect(_buy_upgrade.bind(key))


func _buy_weapon(id: String) -> void:
	var price: int = Game.WEAPONS[id].price
	if Game.money < price or id in Game.owned:
		return
	Game.money -= price
	Game.owned.append(id)
	_bought()


func _buy_truck() -> void:
	if Game.money < Game.TRUCK_PRICE or Game.has_truck:
		return
	Game.money -= Game.TRUCK_PRICE
	Game.has_truck = true
	_bought()


func _buy_upgrade(key: String) -> void:
	var lvl: int = Game.upgrades[key]
	var prices: Array = Game.UPGRADES[key].prices
	if lvl >= prices.size() or Game.money < prices[lvl]:
		return
	Game.money -= prices[lvl]
	Game.upgrades[key] = lvl + 1
	_bought()


func _bought() -> void:
	Sfx.play("buy")
	Game.save_game()
	_refresh()
