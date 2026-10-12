class_name Mats
extends RefCounted
## 실사 소재 (Poly Haven CC0). 월드 좌표 기준 트라이플래너라 크기가 달라도 무늬가 늘어나지 않는다.

static var _cache := {}


static func pbr(name: String, tile: float, tint := Color.WHITE, rough_mul := 1.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%s_%.2f" % [name, tile, tint.to_html(), rough_mul]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/pbr/%s_col.jpg" % name)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/pbr/%s_nor.jpg" % name)
	m.normal_scale = 1.0
	m.roughness_texture = load("res://assets/pbr/%s_rough.jpg" % name)
	m.roughness = rough_mul
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


static func asphalt() -> StandardMaterial3D:
	return pbr("asphalt", 6.0, Color(0.85, 0.85, 0.88))


static func pavement() -> StandardMaterial3D:
	return pbr("pavement", 2.5)


static func grass() -> StandardMaterial3D:
	return pbr("grass", 5.0, Color(0.85, 1.0, 0.8))


static func brick() -> StandardMaterial3D:
	return pbr("brick", 3.0)


static func facade(i: int) -> StandardMaterial3D:
	## 건물 외벽 몇 종류 (회반죽, 베이지, 콘크리트, 벽돌, 타일, 색 바꾼 회반죽)
	match i % 7:
		0: return pbr("plaster", 3.0, Color(0.95, 0.93, 0.9))
		1: return pbr("beige", 3.0)
		2: return pbr("concrete", 4.0, Color(0.9, 0.9, 0.92))
		3: return pbr("brick", 3.0)
		4: return pbr("tiles", 1.2, Color(0.95, 0.97, 1.0))
		5: return pbr("plaster", 3.0, Color(0.75, 0.82, 0.9))
		_: return pbr("beige", 3.0, Color(1.0, 0.85, 0.75))


static func flat(color: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%.2f" % [color.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[key] = m
	return m


static func glass() -> StandardMaterial3D:
	## 하늘을 비추는 유리창
	return flat(Color(0.18, 0.24, 0.3), 0.04, 0.85)


static func shop_glass() -> StandardMaterial3D:
	## 가게 쇼윈도: 안쪽이 밝게 보인다
	var key := "shop_glass"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.55, 0.6)
	m.roughness = 0.05
	m.metallic = 0.5
	m.emission_enabled = true
	m.emission = Color(1.0, 0.92, 0.75)
	m.emission_energy_multiplier = 0.35
	_cache[key] = m
	return m


static func glass_lit(cool := false) -> StandardMaterial3D:
	## 밤에 불 켜지는 창 (낮에는 보통 유리와 거의 같다). 따뜻한 집 불빛과 푸른 형광등 두 가지
	var key := "glass_lit_cool" if cool else "glass_lit"
	if _cache.has(key):
		return _cache[key]
	var m := glass().duplicate() as StandardMaterial3D
	m.emission_enabled = true
	m.emission = Color(0.75, 0.88, 1.0) if cool else Color(1.0, 0.72, 0.42)
	m.emission_energy_multiplier = 0.0
	_cache[key] = m
	return m


static func set_night(n: float) -> void:
	## n: 0 = 한낮, 1 = 한밤. 간판/쇼윈도/불 켜진 창의 밝기를 올린다
	for key in _cache:
		var m: StandardMaterial3D = _cache[key]
		if key.begins_with("sign_"):
			m.emission_energy_multiplier = lerp(0.4, 2.6, n)
		elif key == "shop_glass":
			m.emission_energy_multiplier = lerp(0.35, 1.6, n)
		elif key == "glass_lit":
			m.emission_energy_multiplier = lerp(0.0, 0.75, n)
		elif key == "glass_lit_cool":
			m.emission_energy_multiplier = lerp(0.0, 0.5, n)


static func set_wet(w: float) -> void:
	## 비: 바닥이 젖어 어둡고 반질반질해진다 (SSR 이 네온을 비춤)
	for key in ["asphalt", "pavement"]:
		for k in _cache:
			if k.begins_with(key + "_"):
				var m: StandardMaterial3D = _cache[k]
				m.roughness = lerp(1.0, 0.25, w)
				m.albedo_color = Color.WHITE.lerp(Color(0.62, 0.62, 0.66), w) * (Color(0.85, 0.85, 0.88) if key == "asphalt" else Color.WHITE)


static func sign_board(color: Color) -> StandardMaterial3D:
	var key := "sign_" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.4
	_cache[key] = m
	return m
