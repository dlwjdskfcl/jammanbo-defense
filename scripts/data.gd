extends Node
## 게임 데이터 (data/*.json) 읽기. 값은 데이터/캐릭터DB.xlsx → 도구/export_data.py 로 만들어집니다.

var d: Dictionary = {}       # game_data.json
var atlas: Dictionary = {}   # td_atlas.json (프레임 목록)
var sound: Dictionary = {}   # sound_atlas.json
var units: Dictionary = {}   # 소환 풀(반려 3 + 모임 유닛 + 꽝). 시트가 없으면 비어 있음 → characters 만 사용
var dungeons: Array = []     # 던전 10개(없으면 빈 배열 → 예전 waves/bosses 사용)
var hp_curve: Dictionary = {}  # {"1": 1.29, ...} 웨이브별 HP 곡선 배수
var events: Array = []       # 모임 이벤트 카드


func _ready() -> void:
	d = _load_json("res://data/game_data.json")
	atlas = _load_json("res://data/td_atlas.json")
	sound = _load_json("res://data/sound_atlas.json")
	units = d.get("units", {})
	dungeons = d.get("dungeons", [])
	hp_curve = d.get("hp_curve", {})
	events = d.get("events", [])


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("파일을 열 수 없음: " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("JSON 형식 오류: " + path)
	return {}


func rule(key: String, default_value = 0):
	return d.get("rules", {}).get(key, default_value)


func grade_info(n: int) -> Dictionary:
	for g in d.get("grades", []):
		if int(g["grade"]) == n:
			return g
	return {}


func grade_mult(n: int) -> float:
	return float(grade_info(n).get("mult", 1.0))


func grade_name(n: int) -> String:
	return str(grade_info(n).get("name", str(n)))


func grade_color(n: int) -> Color:
	return Color.html(str(grade_info(n).get("color", "#ffffff")))


func max_grade() -> int:
	var m := 1
	for g in d.get("grades", []):
		m = max(m, int(g["grade"]))
	return m


## ---- 소환 풀 / 던전 접근자 (없는 키는 안전한 기본값) ----
func unit_def(id: String) -> Dictionary:
	if units.has(id):
		return units[id]
	if d.get("characters", {}).has(id):
		var c: Dictionary = d["characters"][id]
		return {"name": c.get("name", id), "kind": "pet", "color": c.get("bg", "#ffffff"), "summon_weight": 1,
				"merge_weight": 1, "dud": false, "sell_mult": 1.0, "pet": true, "stat": c.get("stat", {}),
				"title": c.get("title", "")}
	return {}


func is_pet(id: String) -> bool:
	return bool(unit_def(id).get("pet", false)) or d.get("characters", {}).has(id)


func is_dud(id: String) -> bool:
	return bool(unit_def(id).get("dud", false))


## 소환 풀 id 목록(풀이 없으면 반려 3종)
func pool_ids() -> Array:
	return units.keys() if not units.is_empty() else d.get("characters", {}).keys()


func pet_ids() -> Array:
	var out: Array = []
	for k in pool_ids():
		if is_pet(str(k)):
			out.append(str(k))
	return out


func unit_name(id: String) -> String:
	return str(unit_def(id).get("name", id))


func unit_color(id: String) -> Color:
	return Color.html(str(unit_def(id).get("color", "#ffffff")))


func hp_curve_at(w: int) -> float:
	return float(hp_curve.get(str(w), 1.0))


## n 번째(1부터) 던전. 없으면 빈 Dictionary
func dungeon(n: int) -> Dictionary:
	if n >= 1 and n <= dungeons.size():
		return dungeons[n - 1]
	return {}
