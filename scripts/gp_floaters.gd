extends Node2D
## 떠오르는 데미지 숫자. 노드 1개가 한꺼번에 그려서 라벨을 수없이 만들지 않습니다.

const MAX_N := 40
const LIFE := 0.7

var _items: Array = []
var _font: Font


func _ready() -> void:
	_font = load("res://assets/fonts/Galmuri11-Bold.ttf")
	z_index = 9


func add(pos: Vector2, value: float, color: Color = Color.WHITE, big: bool = false) -> void:
	if _items.size() >= MAX_N:
		_items.pop_front()
	var txt := str(int(value))
	if value >= 10000.0:
		txt = "%.1fK" % (value / 1000.0)
	_items.append({"p": pos + Vector2(randf_range(-8, 8), -26), "t": 0.0, "s": txt, "c": color, "b": big})
	set_process(true)


func _process(delta: float) -> void:
	if _items.is_empty():
		set_process(false)
		queue_redraw()
		return
	var keep: Array = []
	for it in _items:
		it["t"] = float(it["t"]) + delta
		if float(it["t"]) < LIFE:
			keep.append(it)
	_items = keep
	queue_redraw()


func _draw() -> void:
	for it in _items:
		var k: float = float(it["t"]) / LIFE
		var p: Vector2 = it["p"] + Vector2(0, -22.0 * k)
		var fs := 22 if it["b"] else 15
		var c: Color = it["c"]
		c.a = 1.0 - k * k
		draw_string_outline(_font, p, str(it["s"]), HORIZONTAL_ALIGNMENT_CENTER, -1, fs, 4, Color(0.15, 0.1, 0.15, c.a))
		draw_string(_font, p, str(it["s"]), HORIZONTAL_ALIGNMENT_CENTER, -1, fs, c)
