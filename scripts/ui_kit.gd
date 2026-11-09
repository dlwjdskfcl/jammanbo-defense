extends RefCounted
## 로비·카드·설정·튜토리얼이 같이 쓰는 UI 도우미 (preload 해서 사용: const K = preload("res://scripts/ui_kit.gd"))
## 화면 크기 720×1280 기준. 터치 영역은 높이 80 이상으로 만듭니다.

const U = preload("res://scripts/util.gd")
const INK := Color(0.23, 0.14, 0.19)
const GOLD := Color(1.0, 0.82, 0.25)
const WHITE := Color(1, 1, 1)
const DIM := Color(0.62, 0.58, 0.75)
const ROW_FILL := Color(0.133, 0.11, 0.21)
const ROW_LINE := Color(0.35, 0.31, 0.47)
const GREEN := Color(0.4, 0.9, 0.5)
const COMMON := "res://assets/screens/common/"


static func label(text: String, size: int, pos: Vector2, box: Vector2, color: Color = WHITE,
		align: int = HORIZONTAL_ALIGNMENT_CENTER, outline: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_color_override("font_outline_color", INK)
		l.add_theme_constant_override("outline_size", max(2, int(size / 6)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(rect: Rect2, fill: Color = ROW_FILL, line: Color = ROW_LINE, radius: int = 14, border: int = 2) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = line
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func icon(tex_path: String, pos: Vector2, scale_value: float = 1.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = U.tex(tex_path)
	r.position = pos
	r.scale = Vector2(scale_value, scale_value)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 큰 그림 버튼(텍스처 + 글자). 눌리는 동안 살짝 어두워짐. 비활성은 set_enabled() 로.
static func button(tex: String, text: String, rect: Rect2, cb: Callable, fsize: int = 33) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = U.tex(tex)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = rect.position
	b.size = rect.size
	b.custom_minimum_size = rect.size
	b.pressed.connect(cb)
	b.button_down.connect(func(): b.self_modulate = Color(0.8, 0.8, 0.8))
	b.button_up.connect(func(): b.self_modulate = Color.WHITE)
	if text != "":
		b.add_child(label(text, fsize, Vector2.ZERO, rect.size))
	return b


## 투명 터치 영역 (이미 그려진 그림 위에 얹어서 누르게 만들 때)
static func hit_area(rect: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	b.pressed.connect(cb)
	return b


static func set_enabled(b: BaseButton, on: bool) -> void:
	b.disabled = not on
	b.modulate = Color.WHITE if on else Color(0.5, 0.5, 0.55)


## 위에서 잠깐 떴다 사라지는 안내 글 (parent 는 화면 크기 Control)
static func toast(parent: Node, text: String, y: float = 560.0, color: Color = GOLD) -> void:
	var box := panel(Rect2(60, y, 600, 84), Color(0.08, 0.06, 0.16, 0.93), color, 16, 3)
	box.add_child(label(text, 28, Vector2.ZERO, Vector2(600, 84), color))
	box.z_index = 100
	parent.add_child(box)
	Sfx.play("toast")
	var tw := box.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)


## 어두운 바탕 + 클릭 막기 (팝업용)
static func dim_layer(color: Color = Color(0, 0, 0, 0.7)) -> Control:
	var c := Control.new()
	c.size = Vector2(720, 1280)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var d := ColorRect.new()
	d.color = color
	d.size = Vector2(720, 1280)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(d)
	return c


## 화면 위쪽 어두운 띠 + 제목 (+ 뒤로가기 버튼). 뒤로가기를 누르면 back_cb 호출.
static func header(parent: Control, title: String, back_cb: Callable = Callable()) -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.1, 0.08, 0.17)
	bar.size = Vector2(720, 110)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	var line := ColorRect.new()
	line.color = Color(0.05, 0.04, 0.1)
	line.position = Vector2(0, 108)
	line.size = Vector2(720, 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	parent.add_child(label(title, 46, Vector2(110, 22), Vector2(500, 70), WHITE))
	if back_cb.is_valid():
		parent.add_child(icon(COMMON + "icon_back.png", Vector2(24, 26), 2.0))
		parent.add_child(hit_area(Rect2(0, 0, 120, 110), back_cb))


## 세로 그라데이션 바탕 (설정/카드 화면 배경)
static func menu_bg(parent: Control) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.17, 0.15, 0.31))
	g.set_color(1, Color(0.07, 0.05, 0.13))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	var r := TextureRect.new()
	r.texture = gt
	r.size = Vector2(720, 1280)
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤 화면 클릭 막기
	parent.add_child(r)


## 가운데 팝업: 어두운 바탕 + 테두리 패널 + 제목 + 닫기(X). 닫으면 스스로 사라지고 on_close 를 부릅니다.
## 반환한 layer 에 내용을 절대 좌표(720×1280 기준)로 add_child 하세요.
static func popup(parent: Node, rect: Rect2, title: String, on_close: Callable = Callable()) -> Control:
	var layer := dim_layer()
	layer.z_index = 150
	parent.add_child(layer)
	Sfx.play("popup_open")
	layer.add_child(panel(rect, Color(0.13, 0.1, 0.22), Color(0.95, 0.72, 0.2), 20, 4))
	layer.add_child(label(title, 36, Vector2(rect.position.x + 70, rect.position.y + 14), Vector2(rect.size.x - 140, 64), GOLD))
	layer.add_child(icon(COMMON + "icon_close.png", Vector2(rect.end.x - 70, rect.position.y + 18), 1.8))
	var close := func():
		Sfx.play("popup_close")
		layer.queue_free()
		if on_close.is_valid():
			on_close.call()
	layer.add_child(hit_area(Rect2(rect.end.x - 100, rect.position.y, 100, 90), close))
	layer.set_meta("close", close)
	return layer
