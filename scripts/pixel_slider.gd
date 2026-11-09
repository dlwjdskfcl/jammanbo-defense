extends Control
## 픽셀 슬라이더(트랙·채움·손잡이 그림 사용). 드래그하면 value_changed, 손을 떼면 released.
## 가로 400(트랙 그림 크기)을 늘려 쓰려면 size.x 를 지정하세요. 높이는 터치하기 쉽게 64.

signal value_changed(v: float)
signal released

const C := "res://assets/screens/common/"
var value: float = 0.5 : set = set_value
var _drag := false


func _init() -> void:
	custom_minimum_size = Vector2(400, 64)
	size = Vector2(400, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var kn: Texture2D = load(C + "slider_knob.png")
	var w := size.x
	var cy := size.y * 0.5
	draw_rect(Rect2(0, cy - 11, w, 22), Color(0.07, 0.055, 0.12))
	draw_rect(Rect2(0, cy - 11, w, 22), Color(0.3, 0.26, 0.4), false, 2.0)
	var fw := (w - 8.0) * value
	if fw > 0.0:
		draw_rect(Rect2(4, cy - 7, fw, 14), Color(1.0, 0.72, 0.27))
		draw_rect(Rect2(4, cy - 7, fw, 6), Color(1.0, 0.82, 0.3))
	draw_texture_rect(kn, Rect2(clampf(4 + fw, 20, w - 20) - 20, cy - 20, 40, 40), false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		if event.pressed:
			_set_from_x(event.position.x)
		else:
			released.emit()
	elif event is InputEventMouseMotion and _drag:
		_set_from_x(event.position.x)


func _set_from_x(x: float) -> void:
	var v := clampf((x - 20.0) / maxf(size.x - 40.0, 1.0), 0.0, 1.0)
	v = snappedf(v, 0.05)
	if not is_equal_approx(v, value):
		value = v
		value_changed.emit(v)
