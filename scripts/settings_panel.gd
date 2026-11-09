extends Control
## 설정 패널(720×1280 전체 화면, 재사용 가능). 로비와 게임 일시정지에서 둘 다 띄울 수 있습니다.
## 사용:
##   var p = preload("res://scenes/settings_panel.tscn").instantiate()
##   some_layer.add_child(p)            # 일시정지 중에도 동작(process_mode ALWAYS)
##   p.closed.connect(func(): ...)      # 뒤로가기를 누르면 신호만 보내고, 닫는(queue_free) 것은 쓰는 쪽이 합니다
## 값은 Save(효과음/배경음/진동/기본 배속)에 바로 반영·저장됩니다. Save 가 없으면 화면만 뜹니다.

signal closed

const K = preload("res://scripts/ui_kit.gd")
const PixelSlider = preload("res://scripts/pixel_slider.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const C := "res://assets/screens/common/"
const VERSION_TEXT := "아르마니여름 랜덤 디펜스  v0.1"

var save: Node
var speed_btns: Array = []
var vib_toggle: TextureRect
var popup_toggle: TextureRect
var sub: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = Vector2(720, 1280)
	save = get_node_or_null("/root/Save")
	mouse_filter = Control.MOUSE_FILTER_STOP
	K.menu_bg(self)
	K.header(self, "설정", _on_back)
	_build()


func _on_back() -> void:
	Sfx.play("button")
	closed.emit()


func _row(y: float, h: float) -> void:
	add_child(K.panel(Rect2(60, y, 600, h)))


func _section(text: String, y: float) -> void:
	add_child(K.label(text, 30, Vector2(60, y), Vector2(300, 44), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))


func _slider_row(y: float, title: String, icon_name: String, value: float, on_change: Callable) -> void:
	_row(y, 100)
	add_child(K.icon(C + icon_name, Vector2(82, y + 30), 1.9))
	add_child(K.label(title, 28, Vector2(160, y + 6), Vector2(200, 40), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	var pct := K.label("%d%%" % int(round(value * 100)), 26, Vector2(530, y + 6), Vector2(100, 40), K.GOLD,
			HORIZONTAL_ALIGNMENT_RIGHT, false)
	add_child(pct)
	var s := PixelSlider.new()
	s.position = Vector2(150, y + 34)
	s.size = Vector2(420, 64)
	s.value = value
	s.value_changed.connect(func(v: float):
		pct.text = "%d%%" % int(round(v * 100))
		on_change.call(v))
	s.released.connect(func(): Sfx.play("button"))
	add_child(s)


func _set_sfx(v: float) -> void:
	if save:
		save.sfx_volume = v
		save.settings_changed()


func _set_bgm(v: float) -> void:
	if save:
		save.bgm_volume = v
		save.settings_changed()


func _build() -> void:
	var sfx_v := 1.0 if save == null else float(save.sfx_volume)
	var bgm_v := 0.6 if save == null else float(save.bgm_volume)
	_section("소리", 128)
	_slider_row(176, "효과음", "icon_sound_on.png", sfx_v, _set_sfx)
	_slider_row(286, "배경음악", "icon_music.png", bgm_v, _set_bgm)
	# 진동
	_row(396, 90)
	add_child(K.icon(C + "icon_vibrate.png", Vector2(82, 424), 1.9))
	add_child(K.label("진동", 28, Vector2(160, 410), Vector2(200, 60), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	vib_toggle = K.icon(C + "toggle_on.png", Vector2(545, 419), 1.0)
	add_child(vib_toggle)
	add_child(K.hit_area(Rect2(60, 396, 600, 90), _toggle_vibrate))
	_refresh_vibrate()

	_section("게임", 508)
	_row(556, 90)
	add_child(K.label("기본 배속", 28, Vector2(90, 570), Vector2(200, 60), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	for i in 2:
		var sp := i + 1
		var p := K.panel(Rect2(430 + i * 110, 572, 100, 58), Color.WHITE, Color.WHITE, 10, 0)
		add_child(p)
		p.add_child(K.label("x%d" % sp, 28, Vector2.ZERO, Vector2(100, 58)))
		speed_btns.append(p)
		add_child(K.hit_area(Rect2(420 + i * 110, 556, 120, 90), _set_speed.bind(sp)))
	_refresh_speed()
	_row(652, 90)
	add_child(K.icon(C + "icon_card.png", Vector2(86, 680), 1.9))
	add_child(K.label("합성 팝업 보기", 28, Vector2(160, 666), Vector2(340, 60), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	popup_toggle = K.icon(C + "toggle_on.png", Vector2(545, 675), 1.0)
	add_child(popup_toggle)
	add_child(K.hit_area(Rect2(60, 652, 600, 90), _toggle_popup))
	_refresh_popup()
	_link_row(752, "icon_info.png", "소환·합성 확률 보기", _show_odds)
	_link_row(856, "icon_replay.png", "튜토리얼 다시 보기", _replay_tutorial)

	_section("기록", 960)
	_row(1008, 110)
	var best := 0 if save == null else int(save.best_wave())
	var runs := 0 if save == null else int(save.runs)
	var wins := 0 if save == null else int(save.wins)
	var kills := 0 if save == null else int(save.total_kills)
	add_child(K.label("최고 웨이브 %d   ·   %d판 %d승" % [best, runs, wins], 26, Vector2(80, 1014), Vector2(560, 46),
			K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	add_child(K.label("지금까지 처치한 적 %d마리" % kills, 24, Vector2(80, 1060), Vector2(560, 46), K.DIM,
			HORIZONTAL_ALIGNMENT_LEFT, false))
	add_child(K.label("저장은 이 기기의 브라우저에만 돼요 (광고·결제 없음)", 20, Vector2(30, 1146), Vector2(660, 36), K.DIM,
			HORIZONTAL_ALIGNMENT_CENTER, false))
	add_child(K.label(VERSION_TEXT, 22, Vector2(0, 1220), Vector2(720, 36), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))


func _link_row(y: float, icon_name: String, text: String, cb: Callable) -> void:
	_row(y, 96)
	add_child(K.icon(C + icon_name, Vector2(86, y + 26), 1.9))
	add_child(K.label(text, 28, Vector2(160, y + 10), Vector2(380, 76), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	add_child(K.label(">", 34, Vector2(590, y + 10), Vector2(50, 76), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
	add_child(K.hit_area(Rect2(60, y, 600, 96), cb))


func _toggle_vibrate() -> void:
	if save:
		save.vibrate = not save.vibrate
		save.settings_changed()
		if save.vibrate:
			save.buzz(40)
	Sfx.play("button")
	_refresh_vibrate()


func _refresh_vibrate() -> void:
	var on: bool = true if save == null else bool(save.vibrate)
	vib_toggle.texture = load(C + ("toggle_on.png" if on else "toggle_off.png"))


func _toggle_popup() -> void:
	if save:
		save.merge_popup = not save.merge_popup
		save.settings_changed()
	Sfx.play("button")
	_refresh_popup()


func _refresh_popup() -> void:
	var on: bool = true if save == null else bool(save.merge_popup)
	popup_toggle.texture = load(C + ("toggle_on.png" if on else "toggle_off.png"))


func _set_speed(sp: int) -> void:
	if save:
		save.default_speed = sp
		save.settings_changed()
	Sfx.play("button")
	_refresh_speed()


func _refresh_speed() -> void:
	var cur: int = 1 if save == null else int(save.default_speed)
	for i in speed_btns.size():
		var p: Panel = speed_btns[i]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.bg_color = Color(0.96, 0.66, 0.16) if (i + 1) == cur else Color(0.2, 0.17, 0.3)
		p.add_theme_stylebox_override("panel", sb)


func _replay_tutorial() -> void:
	Sfx.play("popup_open")
	add_child(Tutorial.new())


# ------------------------------------------------------------------ 확률 보기
func _close_odds() -> void:
	Sfx.play("popup_close")
	if sub != null:
		sub.queue_free()
		sub = null


func _show_odds() -> void:
	Sfx.play("popup_open")
	if sub != null:
		return
	sub = Control.new()
	sub.size = Vector2(720, 1280)
	add_child(sub)
	K.menu_bg(sub)
	K.header(sub, "소환·합성 확률", _close_odds)
	var chars: Array = Data.d.get("characters", {}).keys()
	var n := maxi(chars.size(), 1)
	var lucky := float(Data.rule("lucky_merge_chance", 0.05)) * 100.0
	var pity := int(Data.rule("pity_limit", 10))
	var max_g := Data.max_grade()
	var y := 132.0
	sub.add_child(K.label("랜덤 소환", 30, Vector2(60, y), Vector2(300, 44), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	y += 50
	sub.add_child(K.panel(Rect2(60, y, 600, 56 + 44 * n)))
	sub.add_child(K.label("소환하면 항상 %s(1성) 등급, 누가 나올지의 확률" % Data.grade_name(1), 21, Vector2(80, y + 6),
			Vector2(560, 40), K.DIM, HORIZONTAL_ALIGNMENT_LEFT, false))
	for i in n:
		var cid: String = chars[i]
		sub.add_child(K.label(str(Data.d["characters"][cid].get("name", cid)), 26, Vector2(100, y + 50 + i * 44),
				Vector2(300, 40), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		sub.add_child(K.label("%.1f%%" % (100.0 / n), 26, Vector2(440, y + 50 + i * 44), Vector2(180, 40), K.GOLD,
				HORIZONTAL_ALIGNMENT_RIGHT, false))
	y += 56 + 44 * n + 28
	sub.add_child(K.label("합성 (같은 등급 3개)", 30, Vector2(60, y), Vector2(400, 44), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	y += 50
	sub.add_child(K.panel(Rect2(60, y, 600, 260)))
	var lines := [
		["한 단계 위로 올라갈 확률", "%.0f%%" % (100.0 - lucky)],
		["대박(두 단계 점프) 확률", "%.0f%%" % lucky],
		["천장: 대박이 연속 안 나오면", "%d번째 합성 확정" % pity],
		["합성 결과 캐릭터", "%d명 중 균등 (%.1f%%씩)" % [n, 100.0 / n]],
		["최고 등급에서는", "더 합성할 수 없어요"],
	]
	for i in lines.size():
		sub.add_child(K.label(lines[i][0], 23, Vector2(80, y + 10 + i * 48), Vector2(340, 44), K.WHITE,
				HORIZONTAL_ALIGNMENT_LEFT, false))
		sub.add_child(K.label(lines[i][1], 23, Vector2(380, y + 10 + i * 48), Vector2(260, 44), K.GOLD,
				HORIZONTAL_ALIGNMENT_RIGHT, false))
	y += 260 + 28
	sub.add_child(K.label("등급별 공격력 배율", 30, Vector2(60, y), Vector2(400, 44), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	y += 50
	sub.add_child(K.panel(Rect2(60, y, 600, 20 + 46 * max_g)))
	for g in range(1, max_g + 1):
		var gy := y + 10 + (g - 1) * 46
		sub.add_child(K.label("★%d  %s" % [g, Data.grade_name(g)], 25, Vector2(90, gy), Vector2(300, 42), Data.grade_color(g),
				HORIZONTAL_ALIGNMENT_LEFT))
		sub.add_child(K.label("x%s" % str(Data.grade_mult(g)), 25, Vector2(420, gy), Vector2(200, 42), K.WHITE,
				HORIZONTAL_ALIGNMENT_RIGHT, false))
	y += 20 + 46 * max_g + 14
	sub.add_child(K.label("확률은 숨기지 않아요. 수치는 게임 데이터(엑셀)에서 그대로 읽어 옵니다.", 20, Vector2(30, y),
			Vector2(660, 36), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
