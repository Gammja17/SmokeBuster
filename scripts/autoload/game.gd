extends Node
## 진행 상황(날짜, 돈, 무기, 강화)과 무기/상점/날짜 데이터. 저장은 user://save.json.

const SAVE_PATH := "user://save.json"

## 무기 정의. mode: pump(한 번 누를 때마다 칙), stream(누르는 동안 물줄기), throw(양동이 투척)
const WEAPONS := {
	"spray": {
		"name": "분무기", "price": 0, "mode": "pump",
		"desc": "칙칙. 가까이 가서 뿌려야 한다.",
		"tank": 30.0, "cost": 1.0, "interval": 0.2,
		"drops": 12, "speed": 10.0, "spread": 7.0, "soak": 0.035, "gravity": 7.0, "knock": 0.0,
		"model": "", "loop": "",
	},
	"pistol": {
		"name": "물총", "price": 300, "mode": "stream",
		"desc": "쭉 뻗는 물줄기. 중거리 단속의 기본.",
		"tank": 80.0, "cost": 12.0, "interval": 0.035,
		"drops": 1, "speed": 19.0, "spread": 1.2, "soak": 0.03, "gravity": 9.0, "knock": 0.0,
		"model": "res://assets/blaster/blaster-b.glb", "loop": "stream",
	},
	"bucket": {
		"name": "물양동이", "price": 600, "mode": "throw",
		"desc": "던지면 촤악! 모여 피우는 무리에 특효.",
		"tank": 3.0, "cost": 1.0, "interval": 0.9,
		"drops": 1, "speed": 12.0, "spread": 0.0, "soak": 1.6, "gravity": 14.0, "knock": 4.0,
		"radius": 3.2, "model": "", "loop": "",
	},
	"soaker": {
		"name": "슈퍼소커", "price": 1000, "mode": "stream",
		"desc": "고압 펌프. 멀리, 세게. 도망가도 소용없다.",
		"tank": 150.0, "cost": 16.0, "interval": 0.03,
		"drops": 1, "speed": 30.0, "spread": 0.8, "soak": 0.05, "gravity": 8.0, "knock": 0.6,
		"model": "res://assets/blaster/blaster-d.glb", "loop": "stream",
	},
	"hose": {
		"name": "소방호스", "price": 2200, "mode": "stream",
		"desc": "콸콸콸. 사람이 밀려난다. 물 소모도 엄청나다.",
		"tank": 400.0, "cost": 35.0, "interval": 0.022,
		"drops": 2, "speed": 26.0, "spread": 2.5, "soak": 0.06, "gravity": 10.0, "knock": 2.5,
		"model": "", "loop": "hose",
	},
}
const WEAPON_ORDER := ["spray", "pistol", "bucket", "soaker", "hose"]

const UPGRADES := {
	"tank": {"name": "물통 용량", "desc": "모든 무기 물통 +30%", "prices": [200, 450, 900]},
	"pressure": {"name": "수압", "desc": "적시는 힘 +20%, 사거리 +10%", "prices": [250, 550, 1100]},
	"speed": {"name": "운동화", "desc": "이동 속도 +10%", "prices": [150, 350, 700]},
	"mental": {"name": "강철 멘탈", "desc": "멘탈 최대치 +1", "prices": [300, 700]},
}
const TRUCK_PRICE := 3000

var day := 1
var money := 0
var owned: Array = ["spray"]
var upgrades := {"tank": 0, "pressure": 0, "speed": 0, "mental": 0}
var has_truck := false
var total_caught := 0

# 이번 근무 결과 (결과 화면으로 넘겨줌)
var last_result := {}


func _ready() -> void:
	load_game()


func day_config(d: int) -> Dictionary:
	## 날짜별 난이도. 5일차는 보스, 이후는 무한 모드처럼 계속 어려워진다.
	var cfg := {
		"duration": 150.0,
		"quota": 4 + d * 2,
		"max_smokers": 3 + d,
		"spawn_every": max(9.0 - d * 0.8, 3.0),
		"pedestrians": 12 + d * 2,
		"weights": {"normal": 1.0},
		"boss": false,
		"title": "",
	}
	match d:
		1:
			cfg.quota = 5
			cfg.title = "첫 출근"
		2:
			cfg.weights = {"normal": 1.0, "runner": 0.6}
			cfg.title = "도망자들"
		3:
			cfg.weights = {"normal": 1.0, "runner": 0.5, "angry": 0.5}
			cfg.title = "성질 급한 사람들"
		4:
			cfg.weights = {"normal": 1.0, "runner": 0.6, "angry": 0.5, "group": 0.4}
			cfg.title = "흡연 모임"
		5:
			cfg.weights = {"normal": 1.0, "runner": 0.6, "angry": 0.6, "group": 0.4}
			cfg.boss = true
			cfg.quota = 12
			cfg.title = "골초왕 등장"
		_:
			cfg.weights = {"normal": 1.0, "runner": 0.8, "angry": 0.8, "group": 0.6}
			cfg.boss = d % 3 == 0
			cfg.title = "무한 단속 %d일차" % (d - 5)
	return cfg


func weapon_stat(id: String, key: String) -> float:
	var v: float = WEAPONS[id][key]
	match key:
		"tank":
			v *= 1.0 + 0.3 * upgrades.tank
		"soak":
			v *= 1.0 + 0.2 * upgrades.pressure
		"speed":
			v *= 1.0 + 0.1 * upgrades.pressure
	return v


func max_mental() -> int:
	return 5 + upgrades.mental


func move_speed_mult() -> float:
	return 1.0 + 0.1 * upgrades.speed


func reward_for(kind: String) -> int:
	match kind:
		"runner": return 70
		"angry": return 90
		"boss": return 600
	return 50


func new_game() -> void:
	day = 1
	money = 0
	owned = ["spray"]
	upgrades = {"tank": 0, "pressure": 0, "speed": 0, "mental": 0}
	has_truck = false
	total_caught = 0
	save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and (day > 1 or money > 0)


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"day": day, "money": money, "owned": owned, "upgrades": upgrades,
		"has_truck": has_truck, "total_caught": total_caught,
	}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	day = int(data.get("day", 1))
	money = int(data.get("money", 0))
	owned = data.get("owned", ["spray"])
	var up: Dictionary = data.get("upgrades", {})
	for k in upgrades:
		upgrades[k] = int(up.get(k, 0))
	has_truck = bool(data.get("has_truck", false))
	total_caught = int(data.get("total_caught", 0))
