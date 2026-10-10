extends Control
## 근무 사이 상점. 무기 구매, 강화, 소방차 호출권.

const ITEM := preload("res://ui/shop_item.tscn")

@onready var _money: Label = $M/V/Header/Money
@onready var _brief: Label = $M/V/Brief
@onready var _weapons: VBoxContainer = $M/V/Cols/Weapons/Scroll/List
@onready var _upgrades: VBoxContainer = $M/V/Cols/Upgrades/Scroll/List


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.music(true)
	$M/V/Footer/Start.pressed.connect(func():
		Sfx.play("click")
		get_tree().change_scene_to_file("res://scenes/world.tscn"))
	$M/V/Footer/ToTitle.pressed.connect(func():
		Sfx.play("click")
		get_tree().change_scene_to_file("res://scenes/title.tscn"))
	var cfg := Game.day_config(Game.day)
	var tasks := []
	for id in cfg.tasks:
		tasks.append("%s %d" % [Game.TASKS[id].short, cfg.tasks[id]])
	if cfg.boss:
		tasks.append("골초왕(보스)")
	_brief.text = "다음 근무: %d일차 「%s」 · %s\n업무: %s" % [Game.day, cfg.title, Game.ZONES[cfg.zone].name, " · ".join(tasks)]
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
	truck.setup("소방차 호출", "흡연자 6명 단속마다 충전. F를 누르면 소방차가 길을 쓸고 지나간다!",
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
