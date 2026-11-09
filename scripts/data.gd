extends Node
## 게임 데이터 (data/*.json) 읽기. 값은 데이터/캐릭터DB.xlsx → 도구/export_data.py 로 만들어집니다.

var d: Dictionary = {}       # game_data.json
var atlas: Dictionary = {}   # td_atlas.json (프레임 목록)
var sound: Dictionary = {}   # sound_atlas.json


func _ready() -> void:
	d = _load_json("res://data/game_data.json")
	atlas = _load_json("res://data/td_atlas.json")
	sound = _load_json("res://data/sound_atlas.json")


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
