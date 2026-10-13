class_name VarcoCar
## VARCO 실사 차 모델 (assets/cars/varco). 길이 1 로 정규화되어 나오고 앞 방향도 제각각이라
## 실제 길이로 키우고, 예전 장난감 차(assets/cars/*.glb, 1.6배)와 같은 규칙(앞이 +Z, 바닥 y=0)으로 맞춰 준다.
## 차 종류 이름은 예전 이름 그대로 쓴다 (Vehicle 이 그 이름으로 다시 읽으므로).

# 예전 이름 -> [VARCO 모델, 실제 길이 m, 원본 앞이 +Z 인가]
const MAP := {
	"sedan": ["sedan", 4.8, false],
	"sedan-sports": ["sedan", 4.8, false],
	"hatchback-sports": ["sedan", 4.8, false],
	"taxi": ["taxi", 4.8, false],
	"police": ["police_car", 4.9, false],
	"suv": ["suv", 4.6, true],
	"suv-luxury": ["suv", 4.6, true],
	"van": ["van", 5.0, true],
	"delivery": ["truck_1t", 5.1, true],
	"truck": ["truck_1t", 5.1, true],
	"firetruck": ["fire_truck", 7.5, true],
}

static var _aabbs := {}


## 예전 이름으로 차 모델을 만든다. VARCO 판이 있으면 그걸, 없으면 장난감 차를 1.6배로.
static func make(kind: String) -> Node3D:
	if not MAP.has(kind):
		var old: Node3D = load("res://assets/cars/%s.glb" % kind).instantiate()
		old.scale = Vector3.ONE * 1.6
		return old
	var spec: Array = MAP[kind]
	var m: Node3D = load("res://assets/cars/varco/%s.glb" % spec[0]).instantiate()
	var ab := _aabb(spec[0], m)
	var s: float = spec[1] / ab.size.z
	var yaw := 0.0 if spec[2] else PI
	var c := ab.get_center()
	var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
	m.transform = Transform3D(b, -(b * Vector3(c.x, ab.position.y, c.z)))
	var root := Node3D.new()
	root.name = kind
	root.add_child(m)
	return root


static func _aabb(name: String, m: Node3D) -> AABB:
	if not _aabbs.has(name):
		var acc := AABB()
		var first := true
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var a := _xf(mi, m) * mi.get_aabb()
			acc = a if first else acc.merge(a)
			first = false
		_aabbs[name] = acc
	return _aabbs[name]


static func _xf(n: Node3D, top: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != top:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
