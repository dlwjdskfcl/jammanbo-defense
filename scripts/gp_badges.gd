extends Node2D
## 머리 위 상태 표시 (assets/status_fx 프레임). set_on("debuff_slow", true) 처럼 켜고 끕니다.

const GS = preload("res://scripts/gp_skills.gd")

var _icons: Dictionary = {}


func set_on(key: String, on: bool) -> void:
	if not on and not _icons.has(key):
		return
	if not _icons.has(key):
		var sf := GS.fx_frames("status_fx", key, 8.0, true)
		if sf == null:
			return
		var a := AnimatedSprite2D.new()
		a.sprite_frames = sf
		a.scale = Vector2(0.75, 0.75)
		add_child(a)
		a.play("default")
		_icons[key] = a
	var spr: AnimatedSprite2D = _icons[key]
	if spr.visible != on:
		spr.visible = on
		_layout()


func _layout() -> void:
	var shown: Array = []
	for k in _icons.keys():
		if (_icons[k] as AnimatedSprite2D).visible:
			shown.append(_icons[k])
	var n := shown.size()
	for i in n:
		(shown[i] as AnimatedSprite2D).position = Vector2((i - (n - 1) / 2.0) * 22.0, 0.0)
