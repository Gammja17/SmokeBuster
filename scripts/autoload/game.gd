extends Node
## 진행 상황(돈, 실적, 무기, 강화)과 무기/상점/사건/계급 데이터. 저장은 user://save.json.

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
	"cctv": {"name": "파출소 CCTV 관제실", "desc": "레이더 범위가 넓어진다 (45m -> 75m)", "prices": [600]},
	"ops": {"name": "파출소 상황실", "desc": "무전 출동 보상 +30%", "prices": [900]},
	"garage": {"name": "파출소 정비고", "desc": "차 최고 속도 +15%", "prices": [700]},
}
const TRUCK_PRICE := 3000

var money := 0
var xp := 0                  # 실적. 쌓이면 승진하고 관할 구역이 넓어진다
var owned: Array = ["spray"]
var upgrades := {"tank": 0, "pressure": 0, "speed": 0, "mental": 0, "cctv": 0, "ops": 0, "garage": 0}
var has_truck := false
var total_caught := 0


func _ready() -> void:
	load_game()
	_load_settings()


# ---------------------------------------------------------------- 그래픽 품질 (저장 파일과 따로 user://settings.cfg)

const QUALITY_NAMES := ["낮음", "보통", "높음"]
var quality := 2


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		quality = clampi(cfg.get_value("gfx", "quality", 2), 0, 2)


func set_quality(q: int, world: Node) -> void:
	quality = q
	var cfg := ConfigFile.new()
	cfg.set_value("gfx", "quality", q)
	cfg.save("user://settings.cfg")
	apply_quality(world)


func apply_quality(world: Node) -> void:
	## 낮음: 반사/AO/안개 끄고 그림자 짧게, 3D 를 77% 해상도로 그려 FSR 로 키움
	## 보통: 반사만 끄고 그림자 조금 짧게.  높음: 다 켬 (그래도 무거운 SSIL 과 PCSS 는 뺌)
	var q := quality
	var vp := get_viewport()
	var env: Environment = world.get_node("Env").environment
	var sun: DirectionalLight3D = world.get_node("Sun")
	env.ssr_enabled = q >= 2
	env.ssr_max_steps = 24
	env.ssil_enabled = false
	env.ssao_enabled = q >= 1
	env.volumetric_fog_enabled = q >= 1
	sun.directional_shadow_max_distance = [50.0, 80.0, 100.0][q]
	sun.light_angular_distance = 0.0
	RenderingServer.directional_shadow_atlas_set_size(2048 if q == 0 else 4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][q])
	vp.msaa_3d = Viewport.MSAA_2X if q == 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.77 if q == 0 else 1.0


## 사건 종류. how: water(물로 해결), photo(카메라 신고), pickup(E로 줍기), break(물로 간판 합선)
const TASKS := {
	"smoke": {"name": "흡연자 단속", "short": "흡연", "reward": 50, "how": "water", "color": Color(1, 0.3, 0.2)},
	"litter": {"name": "무단투기 단속", "short": "무단투기", "reward": 60, "how": "water", "color": Color(0.95, 0.6, 0.2)},
	"trash": {"name": "쓰레기 줍기", "short": "쓰레기", "reward": 10, "how": "pickup", "color": Color(0.6, 0.85, 0.4)},
	"jaywalk": {"name": "무단횡단 신고", "short": "무단횡단", "reward": 70, "how": "photo", "color": Color(1, 0.9, 0.2)},
	"teen_smoke": {"name": "미성년 흡연 신고", "short": "미자 흡연", "reward": 80, "how": "photo", "color": Color(1, 0.45, 0.75)},
	"teen_drink": {"name": "미성년 음주 신고", "short": "미자 음주", "reward": 80, "how": "photo", "color": Color(0.7, 0.45, 1)},
	"bully": {"name": "학교폭력 신고", "short": "학폭", "reward": 200, "how": "photo", "color": Color(1, 0.2, 0.55)},
	"drunk": {"name": "음주운전 신고", "short": "음주운전", "reward": 250, "how": "photo", "color": Color(0.3, 0.9, 1)},
	"shop": {"name": "불법업소 철거", "short": "불법업소", "reward": 300, "how": "break", "color": Color(1, 0.35, 0.95)},
	"thief": {"name": "소매치기 검거", "short": "도둑", "reward": 250, "how": "chase", "color": Color(1, 0.12, 0.12)},
	"fight": {"name": "싸움 말리기", "short": "싸움", "reward": 90, "how": "water", "color": Color(1, 0.55, 0.35)},
	"graffiti": {"name": "낙서범 단속", "short": "낙서", "reward": 80, "how": "water", "color": Color(0.4, 1, 0.6)},
	"pee": {"name": "노상방뇨 단속", "short": "노상방뇨", "reward": 60, "how": "water", "color": Color(0.95, 0.85, 0.3)},
	"parking": {"name": "불법주차 신고", "short": "불법주차", "reward": 100, "how": "photo", "color": Color(0.5, 0.7, 1)},
}
## 관할 구역 (x, z 사각형). 승진하면 넓어진다.
const ZONES := [
	{"name": "1구역 · 첫 번째 블록", "rect": Rect2(-63, -63, 72, 72)},
	{"name": "2구역 · 공원까지", "rect": Rect2(-63, -63, 126, 72)},
	{"name": "3구역 · 동네 전체", "rect": Rect2(-63, -63, 126, 126)},
]
const RANKS := ["순경", "경장", "경사", "경위", "경감", "경정", "총경"]
const RANK_XP := [0, 400, 1100, 2400, 4500, 7500, 12000]   # 이 실적부터 그 계급
const HOW_TEXT := {"water": "물", "photo": "촬영", "pickup": "E 줍기", "break": "간판에 물", "chase": "추격"}
const SPAWN_NAMES := {
	"smoke": "흡연자", "trash": "쓰레기", "litter": "무단투기범", "jaywalk": "무단횡단", "teen_smoke": "담배 피는 학생",
	"shop": "불법업소", "teen_drink": "술 마시는 학생", "bully": "학교폭력", "drunk": "음주운전",
	"thief": "소매치기", "fight": "길거리 싸움", "graffiti": "낙서범", "pee": "노상방뇨", "parking": "불법주차",
}


func rank() -> int:
	var r := 0
	for i in RANK_XP.size():
		if xp >= RANK_XP[i]:
			r = i
	return r


func rank_name() -> String:
	return RANKS[rank()]


## 다음 승진까지 [현재 계급 시작 실적, 다음 계급 실적] (최고 계급이면 같은 값)
func rank_span() -> Array:
	var r := rank()
	var nxt: int = RANK_XP[min(r + 1, RANK_XP.size() - 1)]
	return [RANK_XP[r], nxt]


func zone_for_rank(r: int) -> int:
	return 0 if r == 0 else (1 if r == 1 else 2)


## 계급별로 동네에 나오는 사건과 밀도
func patrol_config(r: int) -> Dictionary:
	var spawns := ["smoke", "trash", "litter", "thief", "pee"]
	var weights := {"normal": 1.0}
	if r >= 1:
		spawns.append_array(["jaywalk", "teen_smoke", "shop", "fight", "graffiti", "parking"])
		weights = {"normal": 1.0, "runner": 0.5}
	if r >= 2:
		spawns.append_array(["teen_drink", "bully", "drunk"])
		weights = {"normal": 1.0, "runner": 0.6, "angry": 0.5, "group": 0.35}
	var zone := zone_for_rank(r)
	return {
		"spawns": spawns,
		"weights": weights,
		"zone": zone,
		"incidents": min(6 + r * 2, 14),        # 동시에 진행 중인 사건 수 목표
		"pedestrians": [9, 14, 20][zone],
		"shops": [0, 1, 2][zone],
		"events": r >= 1,
		"boss": r >= 3,
	}


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
	money = 0
	xp = 0
	owned = ["spray"]
	upgrades = {"tank": 0, "pressure": 0, "speed": 0, "mental": 0, "cctv": 0, "ops": 0, "garage": 0}
	has_truck = false
	total_caught = 0
	save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and (xp > 0 or money > 0)


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"money": money, "xp": xp, "owned": owned, "upgrades": upgrades,
		"has_truck": has_truck, "total_caught": total_caught,
	}))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = int(data.get("money", 0))
	xp = int(data.get("xp", 0))
	owned = data.get("owned", ["spray"])
	var up: Dictionary = data.get("upgrades", {})
	for k in upgrades:
		upgrades[k] = int(up.get(k, 0))
	has_truck = bool(data.get("has_truck", false))
	total_caught = int(data.get("total_caught", 0))
