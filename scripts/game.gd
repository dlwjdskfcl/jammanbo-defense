extends Node2D
## 메인 게임: 순환 경로 + 슬롯 18칸 + 랜덤 소환/합성/판매 + 웨이브/보스.
## 규칙 수치는 data/game_data.json (엑셀 '게임규칙' 등)에서 옵니다. 실행 인자 `-- --autoplay` 면 자동 플레이 시뮬레이션.

const U = preload("res://scripts/util.gd")
const UnitScript = preload("res://scripts/unit.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const GS = preload("res://scripts/gp_skills.gd")
const FloatersScript = preload("res://scripts/gp_floaters.gd")
const MergePopup = preload("res://scripts/gp_merge_popup.gd")
const ResultScreen = preload("res://scripts/gp_result.gd")
const Odds = preload("res://scripts/gp_odds.gd")
const EventsScript = preload("res://scripts/gp_events.gd")

const T := 64
const COLS := 8
const ROWS := 5
const SLOT_COLS := 6
const SLOT_ROWS := 3
const SLOT_COUNT := 18
const FIELD_POS := Vector2(40, 200)
const FIELD_SCALE := 1.25
const PATH_TOTAL := 1408.0
const LONG_PRESS_MS := 450
const DRAG_PX := 14.0
const PATH_PTS := [Vector2(32, 32), Vector2(480, 32), Vector2(480, 288), Vector2(32, 288), Vector2(32, 32)]
const PATH_SEGS := [448.0, 256.0, 448.0, 256.0]
const INK := Color(0.23, 0.14, 0.19)

var autoplay: bool = false
var rng := RandomNumberGenerator.new()

var coins: int = 0
var wave: int = 0
var wave_time: float = 0.0
var is_boss_wave: bool = false
var boss_timer: float = 0.0
var spawn_queue: Array = []
var spawn_timer: float = 0.0
var spawn_interval: float = 1.0
var lucky_counter: int = 0
var game_over: bool = false
var selected: int = -1
var slots: Array = []
var enemies: Array = []
var speed_on: bool = false
var kills: int = 0
var elapsed: float = 0.0
var _auto_t: float = 0.0
var shot_path: String = ""
var shot_done: bool = false

var bg: Node2D
var field: Node2D
var overlay: Node2D
var units_node: Node2D
var enemies_node: Node2D
var proj_node: Node2D
var fx_node: Node2D
var ui: CanvasLayer
var lbl_count: Label
var lbl_wave: Label
var lbl_timer: Label
var lbl_coins: Label
var lbl_info: Label
var lbl_pity: Label
var btn_merge: TextureButton
var btn_sell: TextureButton
var btn_speed: TextureButton
var btn_summon: TextureButton
var pause_layer: Control = null
var beams_node: Node2D
var floaters: Node2D
var lbl_merge: Label
var lbl_sell: Label
var btn_info: TextureButton
var bar_bg: ColorRect
var bar_fill: ColorRect
var warn_edges: Array = []
var boss_flash: ColorRect
var _modal: Control = null
var _fx_pool: Array = []
var _fx_active: int = 0
var _hud_t: float = 0.0
var _count_red: bool = false
var _shake_amp: float = 0.0
var _shake_t: float = 0.0
var _press_slot: int = -1
var _press_pos: Vector2 = Vector2.ZERO
var _press_ms: int = 0
var _dragging: bool = false
var _long_done: bool = false
var _drag_unit = null
var run_result: Dictionary = {}
var summon_count: int = 0
var dud_streak: int = 0           # 꽝 연속 횟수(꽝 천장 dud_pity)
var dungeon_n: int = 1
var dungeon_data: Dictionary = {}
var freeze_t: float = 0.0         # 모래시계 이벤트: 적 정지 남은 시간
var freeze_total: float = 0.0
var global_slow_t: float = 0.0
var global_slow_f: float = 0.0
var atk_buff: float = 1.0         # 이벤트 공격력 배율(atk_buff_wave 웨이브에서만)
var atk_buff_wave: int = -1
var absent_units: Array = []      # 노쇼로 불참 중인 유닛
var pending_wave: int = 0
var clear_t: float = -1.0     # 웨이브 조기 클리어 후 다음 웨이브까지 남은 시간(-1=대기 아님)


func _ready() -> void:
	rng.randomize()
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():     # 검증용: --shot=경로.png → 자동 플레이 후 화면 저장
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
			autoplay = true
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = null
	coins = int(Data.rule("start_coins", 100))
	_select_dungeon()
	_build_world()
	_build_ui()
	if autoplay:
		Engine.time_scale = 4.0 if shot_path != "" else 8.0
	Sfx.play_bgm("bgm_battle")
	var sv := get_node_or_null("/root/Save")
	if sv != null and "run_started" in sv and not autoplay:
		sv.run_started.emit({"dungeon": dungeon_n})
	_start_wave(1)
	for ua in OS.get_cmdline_user_args():     # 검증용: --uishot=종류:경로.png (merge|mythic|card|sell|result|pause)
		if ua.begins_with("--uishot="):
			_ui_test(ua.substr(9))


## 던전 선택: 인자 --dungeon=d01 (검증용) > Save.selected_dungeon > 1. 던전 데이터가 없으면 예전 waves/bosses 사용.
func _select_dungeon() -> void:
	dungeon_n = 1
	var sv := get_node_or_null("/root/Save")
	if sv != null and "selected_dungeon" in sv:
		dungeon_n = int(sv.selected_dungeon)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dungeon="):
			var v := a.substr(10)
			dungeon_n = int(v.trim_prefix("d")) if v.begins_with("d") else int(v)
	dungeon_data = Data.dungeon(dungeon_n)
	if dungeon_data.is_empty():
		dungeon_n = 1
		dungeon_data = Data.dungeon(1)


func _total_waves() -> int:
	if not dungeon_data.is_empty():
		return int(dungeon_data.get("waves", Data.rule("total_waves", 40)))
	return _total_waves()


func cur_atk_mult() -> float:
	return atk_buff if wave == atk_buff_wave else 1.0


## 검증 전용: 상황을 만들어 UI 를 연 뒤 화면을 저장하고 종료
func _ui_test(spec: String) -> void:
	var parts := spec.split("|")
	var kind := parts[0]
	var path := parts[1]
	coins = 500
	var setup: Array = []
	match kind:
		"mythic":
			setup = [[0, "arr", 4], [1, "mani", 4], [2, "yeoreum", 4], [6, "arr", 2], [8, "arr", 1]]
		"card":
			setup = [[7, "yeoreum", 3], [8, "arr", 3], [1, "mani", 2], [3, "arr", 1]]
		"pool":
			setup = [[0, "dice", 1], [1, "card", 2], [2, "chess", 3], [3, "meeple", 2], [6, "hourglass", 1], [7, "chip", 3], [8, "roulette", 2], [9, "rulebook", 1], [12, "blank_card", 2], [13, "empty_box", 3], [14, "broken_pawn", 1], [15, "arr", 2]]
		"dud":
			setup = [[0, "blank_card", 2], [1, "broken_pawn", 2], [2, "empty_box", 2]]
		_:
			setup = [[0, "arr", 2], [1, "arr", 2], [2, "mani", 2], [7, "yeoreum", 1]]
	for s in setup:
		_place_unit(int(s[0]), str(s[1]), int(s[2]))
	_recalc_units()
	lucky_counter = 3
	selected = int(setup[0][0])
	if kind == "card":
		selected = 7
	await get_tree().create_timer(2.0).timeout
	match kind:
		"merge", "mythic":
			merge()
			if kind == "mythic" and _modal != null:
				_modal._pick_recipe("mani")
			if parts.size() > 2 and _modal != null:
				_modal._on_ok()
				await get_tree().create_timer(float(parts[2])).timeout
		"card":
			_show_card(slots[7])
		"sell":
			sell()
		"result":
			wave = 23
			kills = 412
			_end(parts.size() > 2 and parts[2] == "win", "필드 적 61 / 한도 60")
		"pause":
			_toggle_pause()
		"event":
			pending_wave = 5
			_open_event(5, _draw_event_cards())
		"pool":
			_show_card(slots[2])
		"boss":
			_start_wave(10)
			await get_tree().create_timer(0.7).timeout
		"wave":
			_start_wave(5)
		"mergefx":
			apply_merge([0, 1, 2], {"cid": "mani", "new_g": 4, "lucky": true})
			await get_tree().create_timer(0.25).timeout
		"drag":      # 끌어서 이동(빈 칸)·교체 로직 점검
			var u0 = slots[0]
			var u7 = slots[7]
			_press_slot = 0
			_dragging = true
			_drag_unit = u0
			_release(slot_center(12))
			print("DRAG move: slot12=", slots[12] == u0, " slot0=", slots[0] == null, " pos ok=", u0.position == slot_center(12))
			_press_slot = 12
			_dragging = true
			_drag_unit = u0
			_release(slot_center(7))
			print("DRAG swap: slot7=", slots[7] == u0, " slot12=", slots[12] == u7, " u7.slot=", u7.slot)
			_press_slot = 7
			_dragging = true
			_drag_unit = u0
			_release(Vector2(-50, -50))
			print("DRAG cancel: back=", slots[7] == u0 and u0.position == slot_center(7))
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false


# ------------------------------------------------------------------ 월드
func _build_world() -> void:
	bg = Node2D.new()
	add_child(bg)
	bg.draw.connect(_draw_bg)
	field = Node2D.new()
	field.position = FIELD_POS
	field.scale = Vector2(FIELD_SCALE, FIELD_SCALE)
	add_child(field)
	field.draw.connect(_draw_field)
	units_node = Node2D.new()
	field.add_child(units_node)
	enemies_node = Node2D.new()
	field.add_child(enemies_node)
	beams_node = Node2D.new()
	beams_node.z_index = 4
	field.add_child(beams_node)
	proj_node = Node2D.new()
	field.add_child(proj_node)
	fx_node = Node2D.new()
	fx_node.z_index = 8
	field.add_child(fx_node)
	floaters = FloatersScript.new()
	field.add_child(floaters)
	overlay = Node2D.new()
	overlay.z_index = 10
	field.add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	ui = CanvasLayer.new()
	add_child(ui)


func _tile(name: String) -> Texture2D:
	return U.tex("res://assets/td/tiles/%s.png" % name)


func _draw_bg() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for y in 20:
		for x in 12:
			bg.draw_texture(_tile("grass_%d" % r.randi_range(0, 2)), Vector2(x * T, y * T))
	for x in range(0, 720, 112):
		bg.draw_texture(_tile("prop_tree"), Vector2(x - 8, 118))
	bg.draw_texture(_tile("prop_bush"), Vector2(20, 610))
	bg.draw_texture(_tile("prop_flower"), Vector2(630, 610))
	bg.draw_rect(Rect2(0, 0, 720, 130), Color(0.14, 0.12, 0.22, 0.92))
	bg.draw_rect(Rect2(0, 640, 720, 640), Color(0.14, 0.12, 0.22, 0.97))
	bg.draw_line(Vector2(0, 640), Vector2(720, 640), INK, 4.0)
	bg.draw_line(Vector2(0, 130), Vector2(720, 130), INK, 4.0)


func _draw_field() -> void:
	for y in ROWS:
		for x in COLS:
			var edge_x: bool = (x == 0 or x == COLS - 1)
			var edge_y: bool = (y == 0 or y == ROWS - 1)
			var p := Vector2(x * T, y * T)
			if not (edge_x or edge_y):
				field.draw_texture(_tile("slot_empty"), p)
				continue
			var n := "path_v"
			if x == 0 and y == 0:
				n = "path_corner_tl"
			elif x == COLS - 1 and y == 0:
				n = "path_corner_tr"
			elif x == 0 and y == ROWS - 1:
				n = "path_corner_bl"
			elif x == COLS - 1 and y == ROWS - 1:
				n = "path_corner_br"
			elif edge_y:
				n = "path_h"
			field.draw_texture(_tile(n), p)


func _draw_overlay() -> void:
	if selected < 0 or slots[selected] == null:
		return
	var u = slots[selected]
	overlay.draw_arc(u.position, u.range_px, 0.0, TAU, 56, Color(1, 1, 1, 0.55), 2.0)
	var c := slot_center(selected)
	overlay.draw_rect(Rect2(c - Vector2(T / 2.0, T / 2.0), Vector2(T, T)), Color(1.0, 0.9, 0.3, 0.95), false, 3.0)
	if u.grade < Data.max_grade():
		for i in SLOT_COUNT:
			if i != selected and slots[i] != null and slots[i].grade == u.grade:
				overlay.draw_arc(slot_center(i) + Vector2(0, 14), 24.0, 0.0, TAU, 24, Color(0.45, 1.0, 0.6, 0.95), 3.0)


func slot_center(i: int) -> Vector2:
	var col: int = i % SLOT_COLS
	var row: int = int(i / SLOT_COLS)
	return Vector2((col + 1) * T + T / 2.0, (row + 1) * T + T / 2.0)


func path_pos(d: float) -> Vector2:
	var m: float = fposmod(d, PATH_TOTAL)
	for i in 4:
		var seg: float = PATH_SEGS[i]
		if m <= seg:
			return (PATH_PTS[i] as Vector2).lerp(PATH_PTS[i + 1], m / seg)
		m -= seg
	return PATH_PTS[0]


func spawn_fx(group: String, id: String, pos: Vector2, scale_value: float = 1.0) -> void:
	var sf = U.atlas_frames(group, id, false)
	if sf != null:
		_play_fx(sf, pos, scale_value)


## 스킬 이펙트 (assets/skill_fx)
func spawn_skill_fx(id: String, pos: Vector2, scale_value: float = 1.0, fps: float = 12.0) -> void:
	var sf := GS.fx_frames("skill_fx", id, fps, false)
	if sf != null:
		_play_fx(sf, pos, scale_value)


func _play_fx(sf: SpriteFrames, pos: Vector2, scale_value: float) -> void:
	if _fx_active >= 90:
		return
	var a: AnimatedSprite2D
	if _fx_pool.is_empty():
		a = AnimatedSprite2D.new()
		fx_node.add_child(a)
		a.animation_finished.connect(_fx_done.bind(a))
	else:
		a = _fx_pool.pop_back()
	_fx_active += 1
	a.sprite_frames = sf
	a.position = pos
	a.scale = Vector2(scale_value, scale_value)
	a.visible = true
	a.play("default")


func _fx_done(a: AnimatedSprite2D) -> void:
	a.stop()
	a.visible = false
	_fx_active -= 1
	_fx_pool.append(a)


func add_floater(pos: Vector2, value: float, color: Color = Color.WHITE, big: bool = false) -> void:
	floaters.add(pos, value, color, big)


func shake(amp: float, time: float) -> void:
	if autoplay:
		return
	_shake_amp = max(_shake_amp, amp)
	_shake_t = max(_shake_t, time)


# ------------------------------------------------------------------ UI
func _label(text: String, size: int, pos: Vector2, box: Vector2, color: Color = Color.WHITE,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", max(2, int(size / 6)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(tex: String, text: String, pos: Vector2, size: Vector2, cb: Callable, fsize: int = 33) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = U.tex(tex)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = size
	b.custom_minimum_size = size
	if not cb.is_null():
		b.pressed.connect(cb)
	b.add_child(_label(text, fsize, Vector2.ZERO, size))
	return b


func _icon(tex: String, pos: Vector2, scale_value: float = 1.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = U.tex(tex)
	r.position = pos
	r.scale = Vector2(scale_value, scale_value)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_ui() -> void:
	# 적 수 경고(한도 임박 시 붉은 테두리 깜빡임) — 가장 뒤에 깔기
	for r in [Rect2(0, 0, 720, 14), Rect2(0, 1266, 720, 14), Rect2(0, 0, 14, 1280), Rect2(706, 0, 14, 1280)]:
		var e := ColorRect.new()
		e.color = Color(1, 0.1, 0.1)
		e.position = r.position
		e.size = r.size
		e.modulate.a = 0.0
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(e)
		warn_edges.append(e)
	boss_flash = ColorRect.new()
	boss_flash.color = Color(1, 0.1, 0.1)
	boss_flash.size = Vector2(720, 1280)
	boss_flash.modulate.a = 0.0
	boss_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(boss_flash)

	ui.add_child(_icon("res://assets/td/ui/icon_skull.png", Vector2(16, 12), 1.5))
	lbl_count = _label("0 / 60", 33, Vector2(70, 12), Vector2(200, 48), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_count)
	lbl_wave = _label("WAVE 1", 38, Vector2(190, 8), Vector2(320, 60), Color(1, 0.85, 0.3))
	ui.add_child(lbl_wave)
	lbl_timer = _label("00", 30, Vector2(210, 62), Vector2(300, 40), Color.WHITE)
	ui.add_child(lbl_timer)
	bar_bg = ColorRect.new()          # 웨이브 진행바
	bar_bg.color = Color(0.05, 0.04, 0.1, 0.9)
	bar_bg.position = Vector2(190, 106)
	bar_bg.size = Vector2(340, 12)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar_bg)
	bar_fill = ColorRect.new()
	bar_fill.color = Color(0.4, 0.85, 0.5)
	bar_fill.position = Vector2(192, 108)
	bar_fill.size = Vector2(0, 8)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar_fill)
	ui.add_child(_icon("res://assets/td/ui/icon_coin.png", Vector2(540, 14), 1.5))
	lbl_coins = _label("0", 33, Vector2(592, 12), Vector2(120, 48), Color(1, 0.9, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_coins)
	ui.add_child(_button("res://assets/td/ui/btn_gray.png", "II", Vector2(580, 66), Vector2(124, 52), _toggle_pause, 33))

	lbl_info = _label("유닛을 눌러 선택하세요", 24, Vector2(30, 652), Vector2(590, 96), Color.WHITE,
			HORIZONTAL_ALIGNMENT_LEFT)
	lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(lbl_info)
	btn_info = TextureButton.new()    # 정보 카드 열기 (길게 눌러도 열림)
	btn_info.texture_normal = U.tex("res://assets/screens/common/icon_info.png")
	btn_info.ignore_texture_size = true
	btn_info.stretch_mode = TextureButton.STRETCH_SCALE
	btn_info.position = Vector2(630, 662)
	btn_info.size = Vector2(70, 70)
	btn_info.pressed.connect(_open_info_selected)
	btn_info.visible = false
	ui.add_child(btn_info)
	btn_merge = _button("res://assets/td/ui/btn_blue_big.png", "합성", Vector2(30, 758), Vector2(210, 92), merge, 34)
	btn_sell = _button("res://assets/td/ui/btn_red_big.png", "판매", Vector2(255, 758), Vector2(210, 92), sell, 34)
	btn_speed = _button("res://assets/td/ui/btn_gray_big.png", "배속 x1", Vector2(480, 758), Vector2(210, 92), _toggle_speed, 30)
	lbl_merge = btn_merge.get_child(0)
	lbl_sell = btn_sell.get_child(0)
	ui.add_child(btn_merge)
	ui.add_child(btn_sell)
	ui.add_child(btn_speed)
	lbl_pity = _label("", 22, Vector2(30, 862), Vector2(660, 40), Color(0.8, 0.9, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_pity)
	var cost := int(Data.rule("summon_cost", 20))
	btn_summon = _button("res://assets/td/ui/btn_green_big.png", "랜덤 소환  %d" % cost, Vector2(110, 940),
			Vector2(500, 150), summon, 44)
	ui.add_child(btn_summon)
	ui.add_child(_label("같은 등급 3개 → 한 단계 위 · 끌어서 이동/교체 · 길게 눌러 정보", 19,
			Vector2(20, 1120), Vector2(680, 40), Color(0.8, 0.8, 0.95)))
	var sv := get_node_or_null("/root/Save")
	if sv != null and int(sv.get("default_speed")) == 2 and not autoplay:
		_toggle_speed()


func _update_hud() -> void:
	var limit := int(Data.rule("field_limit", 60))
	var n := enemies.size()
	var frac: float = float(n) / float(limit)
	lbl_count.text = "%d / %d" % [n, limit]
	var red: bool = frac > 0.8
	if red != _count_red:
		_count_red = red
		lbl_count.add_theme_color_override("font_color", Color(1, 0.45, 0.45) if red else Color.WHITE)
	# 한도 임박 경고: 80% 부터 붉은 테두리 깜빡임(90%↑ 더 빠르고 진하게)
	var a := 0.0
	if frac > 0.8:
		var spd := 6.0 if frac > 0.9 else 3.5
		a = (0.35 + 0.5 * (frac - 0.8) * 5.0) * (0.5 + 0.5 * sin(elapsed * spd))
	for e in warn_edges:
		e.modulate.a = a
	var tw := _total_waves()
	lbl_wave.text = "%s %d / %d" % ["BOSS" if is_boss_wave else "WAVE", wave, tw]
	var wsec := float(Data.rule("wave_seconds", 25))
	if is_boss_wave:
		var lim := float(Data.rule("boss_time_limit", 60))
		lbl_timer.text = "제한시간 %d" % int(ceil(max(boss_timer, 0.0)))
		bar_fill.size.x = 336.0 * clamp(boss_timer / lim, 0.0, 1.0)
		bar_fill.color = Color(1, 0.35, 0.3) if boss_timer < 15.0 else Color(1, 0.65, 0.3)
	else:
		if clear_t >= 0.0:
			lbl_timer.text = "다음 웨이브 %d.." % int(ceil(max(clear_t, 0.0)))
		else:
			lbl_timer.text = "%d초" % int(ceil(max(wsec - wave_time, 0.0)))
		bar_fill.size.x = 336.0 * clamp(wave_time / wsec, 0.0, 1.0)
		bar_fill.color = Color(0.4, 0.85, 0.5)
	lbl_coins.text = str(coins)
	var cost := int(Data.rule("summon_cost", 20))
	btn_summon.modulate = Color.WHITE if (coins >= cost and _free_slot() >= 0) else Color(0.6, 0.6, 0.6)
	btn_merge.modulate = Color.WHITE if _mergeable_grade() >= 0 else Color(0.5, 0.5, 0.5)
	lbl_merge.text = "신화 합성" if _mythic_ready() else "합성"
	btn_sell.modulate = Color.WHITE if (selected >= 0 and slots[selected] != null) else Color(0.5, 0.5, 0.5)
	lbl_pity.text = "대박 합성(2단계 점프) %d%%  ·  천장 %d / %d" % [
		int(round(float(Data.rule("lucky_merge_chance", 0.05)) * 100.0)), lucky_counter,
		int(Data.rule("pity_limit", 10))]
	_update_info()


func _update_info() -> void:
	var has_sel: bool = selected >= 0 and slots[selected] != null
	btn_info.visible = has_sel
	if has_sel:
		var u = slots[selected]
		var info: Dictionary = Data.unit_def(u.char_id)
		var same := _slots_of_grade(u.grade).size()
		var active: Array = []
		for s in GS.skill_list(u.char_id):
			if GS.unlocked(u.char_id, int(s["tier"])):
				active.append(s["name"])
		lbl_info.text = "%s ★%d %s  공격력 %d  사거리 %.1f  [%d/3]\n스킬: %s" % [
			info["name"], u.grade, Data.grade_name(u.grade), int(u.damage), u.range_px / T, same, " · ".join(active)]
	else:
		lbl_info.text = "유닛을 눌러 선택 · 끌어서 이동/교체\n길게 눌러 정보 카드"


func _popup(text: String, color: Color = Color(1, 0.85, 0.3), y: float = 420.0, size: int = 55) -> void:
	var l := _label(text, size, Vector2(0, y), Vector2(720, 70), color)
	ui.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", y - 50.0, 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.5)
	tw.tween_callback(l.queue_free)


func buzz(ms: int = 30) -> void:
	var sv := get_node_or_null("/root/Save")
	if sv != null and sv.has_method("buzz") and not autoplay:
		sv.buzz(ms)


func toast(text: String) -> void:
	Sfx.play("toast")
	_popup(text, Color(1, 0.95, 0.8), 600.0, 30)


func _toggle_speed() -> void:
	speed_on = not speed_on
	Engine.time_scale = 2.0 if speed_on else 1.0
	(btn_speed.get_child(0) as Label).text = "배속 x2" if speed_on else "배속 x1"
	Sfx.play("button")


# ------------------------------------------------------------------ 모달(팝업) 공통
func open_modal(m: Control) -> void:
	close_modal()
	_modal = m
	Sfx.play("popup_open")
	m.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.add_child(m)
	get_tree().paused = true


func close_modal() -> void:
	if _modal != null:
		Sfx.play("popup_close")
		_modal.queue_free()
		_modal = null
		if pause_layer == null:
			get_tree().paused = false


# ------------------------------------------------------------------ 입력 (탭 · 끌어서 이동/교체 · 길게 눌러 정보)
func _slot_at(lp: Vector2) -> int:
	var col := int(floor(lp.x / T))
	var row := int(floor(lp.y / T))
	if col >= 1 and col <= SLOT_COLS and row >= 1 and row <= SLOT_ROWS:
		return (row - 1) * SLOT_COLS + (col - 1)
	return -1


func _unhandled_input(event: InputEvent) -> void:
	if game_over or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var lp := field.get_local_mouse_position()
		if event.pressed:
			var i := _slot_at(lp)
			if i >= 0 and slots[i] != null:
				_press_slot = i
				_press_pos = event.position
				_press_ms = Time.get_ticks_msec()
				_dragging = false
				_long_done = false
			elif i >= 0:
				_tap_slot(i)
			else:
				selected = -1
				overlay.queue_redraw()
		elif _press_slot >= 0:
			_release(lp)
	elif event is InputEventMouseMotion and _press_slot >= 0 and not _long_done:
		if not _dragging and event.position.distance_to(_press_pos) > DRAG_PX:
			_dragging = true
			_drag_unit = slots[_press_slot]
			Sfx.play("drag_pick")
			if _drag_unit != null:
				_drag_unit.z_index = 20
				selected = _press_slot
				overlay.queue_redraw()
		if _dragging and is_instance_valid(_drag_unit):
			_drag_unit.position = field.get_local_mouse_position()


func _release(lp: Vector2) -> void:
	var from := _press_slot
	_press_slot = -1
	if _long_done:
		return
	if _dragging:
		_dragging = false
		var u = _drag_unit
		_drag_unit = null
		if not is_instance_valid(u):
			return
		u.z_index = 0
		Sfx.play("drag_drop")
		var to := _slot_at(lp)
		if to >= 0 and to != from:
			var other = slots[to]
			slots[to] = u
			slots[from] = other
			u.slot = to
			u.position = slot_center(to)
			if other != null:
				other.slot = from
				other.position = slot_center(from)
			selected = to
			_recalc_units()
		else:
			u.position = slot_center(from)
		overlay.queue_redraw()
	else:
		_tap_slot(from)


func _tap_slot(i: int) -> void:
	if selected < 0:
		if slots[i] != null:
			selected = i
	elif i == selected:
		selected = -1
	elif slots[i] == null:      # 빈 칸 → 이동
		var u = slots[selected]
		slots[i] = u
		slots[selected] = null
		u.slot = i
		u.position = slot_center(i)
		selected = i
		_recalc_units()
	else:
		selected = i
	overlay.queue_redraw()


## 인접(8방향) 칸의 유닛 목록
func neighbors(i: int) -> Array:
	var out: Array = []
	var c: int = i % SLOT_COLS
	var r: int = int(i / SLOT_COLS)
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var cc: int = c + dc
			var rr: int = r + dr
			if cc >= 0 and cc < SLOT_COLS and rr >= 0 and rr < SLOT_ROWS:
				var u = slots[rr * SLOT_COLS + cc]
				if u != null:
					out.append(u)
	return out


## 슬롯 구성이 바뀔 때: 인접 보정 다시 계산 + 시너지 빔 다시 그리기
func _recalc_units() -> void:
	for u in slots:
		if u != null:
			u.recalc()
	for c in beams_node.get_children():
		c.queue_free()
	var bf := GS.fx_frames("skill_fx", "synergy_beam", 12.0, true)
	var sp := GS.fx_frames("skill_fx", "synergy_spark", 12.0, true)
	if bf == null:
		return
	for i in SLOT_COUNT:
		var y = slots[i]
		if y == null or y.char_id != "yeoreum":
			continue
		for n in neighbors(i):
			if n.char_id != "arr":
				continue
			var a: Vector2 = y.position
			var b: Vector2 = n.position
			var beam := AnimatedSprite2D.new()
			beam.sprite_frames = bf
			beam.position = (a + b) / 2.0
			beam.rotation = (b - a).angle()
			beam.scale = Vector2(a.distance_to(b) / 64.0, 1.0)
			beams_node.add_child(beam)
			beam.play("default")
			if sp != null:
				var s := AnimatedSprite2D.new()
				s.sprite_frames = sp
				s.position = (a + b) / 2.0
				beams_node.add_child(s)
				s.play("default")


# ------------------------------------------------------------------ 정보 카드
func _open_info_selected() -> void:
	if selected >= 0 and slots[selected] != null:
		_show_card(slots[selected])


func _show_card(u) -> void:
	var cid: String = u.char_id
	var info: Dictionary = Data.unit_def(cid)
	var m := Control.new()
	m.size = Vector2(720, 1280)
	var catcher := ColorRect.new()      # 어디든 누르면 닫힘
	catcher.color = Color(0, 0, 0, 0.55)
	catcher.size = Vector2(720, 1280)
	catcher.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			close_modal())
	m.add_child(catcher)
	var panel := Panel.new()
	panel.position = Vector2(30, 250)
	panel.size = Vector2(660, 700)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(Color(0.16, 0.13, 0.26, 0.98), Data.grade_color(u.grade)))
	m.add_child(panel)
	var ic := TextureRect.new()
	ic.texture = GS.unit_tex(cid, u.grade)
	ic.modulate = GS.unit_mod(cid, u.grade)
	ic.position = Vector2(50, 270)
	ic.scale = Vector2(1.6, 1.6)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(ic)
	m.add_child(_label("%s  ★%d %s" % [info["name"], u.grade, Data.grade_name(u.grade)], 40, Vector2(170, 268),
			Vector2(500, 56), Data.grade_color(u.grade), HORIZONTAL_ALIGNMENT_LEFT))
	m.add_child(_label("카드 Lv%d  ·  %s" % [GS.card_level(cid), str(info.get("title", ""))], 20, Vector2(170, 326),
			Vector2(500, 36), Color(0.85, 0.85, 1.0), HORIZONTAL_ALIGNMENT_LEFT))
	var eff := str(u.stat["effect"])
	var eff_txt := "없음"
	if eff == "slow":
		eff_txt = "둔화 %d%% (%d%% 확률)" % [int(float(u.stat["effect_value"]) * 100.0), int(float(u.stat["effect_chance"]) * 100.0)]
	elif eff == "stun":
		eff_txt = "스턴 %.1f초 (%d%% 확률)" % [float(u.stat["effect_time"]), int(float(u.stat["effect_chance"]) * 100.0)]
	elif eff == "aura_spd":
		eff_txt = "인접 아군 공속 +%d%%" % int(float(u.stat["effect_value"]) * 100.0)
	elif eff == "dice":
		eff_txt = "굴림 눈/3.5배, 6이면 폭발"
	elif eff == "pierce":
		eff_txt = "뒤의 적 %d%% 관통" % int(float(u.stat["effect_value"]) * 100.0)
	elif eff == "roulette":
		eff_txt = "감속/기절/2배/코인 랜덤"
	elif eff == "coin_kill":
		eff_txt = "처치 코인 +%d%%" % int(float(u.stat["effect_value"]) * 100.0)
	elif eff == "mark":
		eff_txt = "표식: 받는 피해 +%d%%" % int(float(u.stat["effect_value"]) * 100.0)
	var aps: float = 1.0 / max(u.base_interval / max(u.spd_mult, 0.1), 0.05)
	var lines: Array = [
		"공격력 %d  (기본 %d)" % [int(u.damage), int(u.base_damage)],
		"공격속도 초당 %.1f회   사거리 %.1f칸" % [aps, u.range_px / T],
		"타겟 %s   범위 %.1f칸   효과 %s" % ["랜덤" if u.stat["target"] == "random" else "선두", float(u.stat["area_tiles"]), eff_txt],
	]
	var y := 400.0
	for t in lines:
		m.add_child(_label(t, 24, Vector2(52, y), Vector2(600, 36), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
		y += 40.0
	y += 10.0
	var all_skills: Array = GS.skill_list(cid).duplicate()
	if cid == "yeoreum" or cid == "arr":
		all_skills.append({"id": GS.SYNERGY["id"], "tier": 0, "name": GS.SYNERGY["name"], "desc": GS.SYNERGY["desc"]})
	for s in all_skills:
		var ok: bool = GS.unlocked(cid, int(s["tier"]))
		var icon := TextureRect.new()
		icon.texture = U.tex("res://assets/skill_icons/%s.png" % s["id"])
		icon.position = Vector2(52, y + 4)
		icon.scale = Vector2(1.5, 1.5)
		icon.modulate = Color.WHITE if ok else Color(0.4, 0.4, 0.4)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(icon)
		var head: String = str(s["name"]) + ("" if ok else "  (Lv%d 해금)" % (6 if int(s["tier"]) == 1 else 12))
		m.add_child(_label(head, 24, Vector2(112, y - 4), Vector2(540, 32),
				Color(1, 0.9, 0.5) if ok else Color(0.6, 0.6, 0.7), HORIZONTAL_ALIGNMENT_LEFT))
		var d := _label(GS.describe(str(s["desc"])), 18, Vector2(112, y + 26), Vector2(540, 44),
				Color(0.85, 0.85, 0.95) if ok else Color(0.5, 0.5, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
		d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		m.add_child(d)
		y += 76.0
	m.add_child(_label("아무 곳이나 눌러 닫기", 20, Vector2(0, 900), Vector2(720, 36), Color(0.7, 0.7, 0.85)))
	open_modal(m)


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	return sb


# ------------------------------------------------------------------ 소환 · 합성 · 판매
func _free_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1


func _random_char() -> String:
	if not Odds.use_pool():
		var keys: Array = Data.d["characters"].keys()
		return str(keys[rng.randi() % keys.size()])
	var protect := summon_count < int(Data.rule("protect_first_summons", 0))
	return Odds.pick(Odds.summon_probs("support" if protect else ""), rng)


func _place_unit(i: int, cid: String, grade: int) -> void:
	var u := UnitScript.new()
	units_node.add_child(u)
	u.setup(self, cid, grade, i)
	u.position = slot_center(i)
	slots[i] = u


func _remove_unit(i: int) -> void:
	if slots[i] != null:
		slots[i].queue_free()
		slots[i] = null


func summon() -> void:
	var cost := int(Data.rule("summon_cost", 20))
	var i := _free_slot()
	if game_over or coins < cost or i < 0:
		Sfx.play("no_coin")
		if not game_over and i < 0:
			toast("빈 칸이 없어요! 합성하거나 판매하세요")
		elif not game_over:
			toast("코인이 부족해요 (%d 필요)" % cost)
		return
	coins -= cost
	_place_unit(i, _random_char(), 1)
	summon_count += 1
	_recalc_units()
	spawn_fx("fx", "summon_poof", slot_center(i))
	Sfx.play("summon")
	overlay.queue_redraw()


func _slots_of_grade(g: int) -> Array:
	var out: Array = []
	for i in SLOT_COUNT:
		if slots[i] != null and slots[i].grade == g:
			out.append(i)
	return out


func _mergeable_grade() -> int:
	var maxg := Data.max_grade()
	if selected >= 0 and slots[selected] != null:
		var g: int = slots[selected].grade
		if g < maxg and _slots_of_grade(g).size() >= 3:
			return g
	for g in range(1, maxg):
		if _slots_of_grade(g).size() >= 3:
			return g
	return -1


## 신화 레시피에 모자란 캐릭터 목록 (g = 최상위 바로 아래 등급). 비어 있으면 레시피 가능.
func recipe_missing(g: int) -> Array:
	var missing: Array = []
	for cid in Data.pet_ids():
		var found := false
		for i in _slots_of_grade(g):
			if slots[i].char_id == cid:
				found = true
				break
		if not found:
			missing.append(str(cid))
	return missing


func is_recipe_grade(g: int) -> bool:
	return g == Data.max_grade() - 1


func _mythic_ready() -> bool:
	var g := _mergeable_grade()
	return g >= 0 and is_recipe_grade(g) and recipe_missing(g).is_empty()


## 합성에 쓸 재료 슬롯 3개. recipe_char 가 있으면 최상위 레시피(캐릭터마다 1마리씩).
func build_plan(g: int, recipe_char: String = "") -> Array:
	var idxs := _slots_of_grade(g)
	var first: int = idxs[0]
	if selected >= 0 and slots[selected] != null and slots[selected].grade == g:
		first = selected
	var picks: Array = []
	if recipe_char != "":
		for cid in Data.pet_ids():
			for i in idxs:
				if slots[i].char_id == cid and not picks.has(i):
					picks.append(i)
					break
		return picks
	picks.append(first)
	var cid0: String = slots[first].char_id
	var rest: Array = []
	for i in idxs:
		if i != first:
			rest.append(i)
	# 선택 유닛 → 같은 id → 꽝 → 서포터 → 딜러 → 반려 순(약한 것부터)
	rest.sort_custom(func(x, y): return _mat_rank(slots[x].char_id, cid0) < _mat_rank(slots[y].char_id, cid0))
	for i in rest:
		if picks.size() < 3:
			picks.append(i)
	return picks


func _mat_rank(cid: String, same_as: String) -> int:
	if cid == same_as:
		return 0
	match str(Data.unit_def(cid).get("kind", "pet")):
		"dud":
			return 1
		"support":
			return 2
		"dealer":
			return 3
	return 4


## 결과를 굴림 (천장 카운터 소모). {cid, new_g, lucky}
func roll_merge(g: int, recipe_char: String = "") -> Dictionary:
	var maxg := Data.max_grade()
	var new_g := g + 1
	var lucky := false
	if g + 2 <= maxg:
		lucky_counter += 1
		var chance := float(Data.rule("lucky_merge_chance", 0.05))
		var pity := int(Data.rule("pity_limit", 10))
		if rng.randf() < chance or lucky_counter >= pity:
			lucky = true
			new_g = g + 2
			lucky_counter = 0
	if recipe_char != "":        # 신화 레시피: 반려 지정, 꽝 없음
		dud_streak = 0
		return {"cid": recipe_char, "new_g": new_g, "lucky": lucky, "dud": false}
	if not Odds.use_pool():
		return {"cid": _random_char(), "new_g": new_g, "lucky": lucky, "dud": false}
	var cid := ""
	if lucky:                    # 대박은 꽝 없음, 소환 분포
		cid = Odds.pick(Odds.merge_probs(new_g, true), rng)
	else:
		var guard := dud_streak >= int(Data.rule("dud_pity", 2))
		cid = Odds.pick(Odds.merge_probs(new_g, false, guard), rng)
	var is_dud := Data.is_dud(cid)
	dud_streak = dud_streak + 1 if is_dud else 0
	return {"cid": cid, "new_g": new_g, "lucky": lucky, "dud": is_dud}


func apply_merge(picks: Array, res: Dictionary) -> void:
	var first: int = picks[0]
	for i in picks:
		_remove_unit(i)
	_place_unit(first, str(res["cid"]), int(res["new_g"]))
	buzz(60 if bool(res["lucky"]) or int(res["new_g"]) >= Data.max_grade() else 30)
	selected = first
	_recalc_units()
	var ng: int = int(res["new_g"])
	var cpos := slot_center(first)
	if ng >= Data.max_grade():
		spawn_fx("fx", "mythic_summon", cpos, 1.3)
		Sfx.play("mythic_summon")
	elif bool(res["lucky"]):
		spawn_fx("fx", "merge_up_jump", cpos, 1.2)
		Sfx.play("level_up")
	else:
		spawn_fx("fx", "merge_up_g%d" % ng, cpos, 1.1)
	Sfx.play("merge_%d" % ng)
	if bool(res["lucky"]):
		_popup("대박! %d성 점프" % int(res["new_g"]), Color(1, 0.6, 0.9), 520.0)
	elif bool(res.get("dud", false)):
		_popup("꽝! %s…" % Data.unit_name(str(res["cid"])), Color(0.75, 0.75, 0.85), 520.0)
	elif int(res["new_g"]) >= Data.max_grade():
		_popup("신화 탄생!", Color(1, 0.5, 0.6), 520.0)
	overlay.queue_redraw()


func merge() -> void:
	if game_over:
		return
	var g := _mergeable_grade()
	if g < 0:
		Sfx.play("no_coin")
		toast("같은 등급 3개가 필요해요")
		return
	if autoplay or GS.quick_merge():
		var rc := ""
		if autoplay and is_recipe_grade(g) and recipe_missing(g).is_empty():
			var keys: Array = Data.pet_ids()
			rc = str(keys[rng.randi() % keys.size()])
		var picks := build_plan(g, rc)
		var res := roll_merge(g, rc)
		if bool(res.get("dud", false)):
			Sfx.play("dud_merge")
		apply_merge(picks, res)
		return
	Sfx.play("button")
	var p := MergePopup.new()
	p.setup(self, g)
	open_modal(p)


func sell() -> void:
	if game_over or selected < 0 or slots[selected] == null:
		return
	if autoplay:
		_do_sell(selected)
		return
	var u = slots[selected]
	var refund := _refund(u)
	var m := Control.new()
	m.size = Vector2(720, 1280)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(720, 1280)
	m.add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(60, 440)
	panel.size = Vector2(600, 340)
	panel.add_theme_stylebox_override("panel", _box(Color(0.16, 0.13, 0.26, 0.98), Color(0.9, 0.35, 0.4)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(panel)
	var info: Dictionary = Data.unit_def(u.char_id)
	m.add_child(_label("정말 판매할까요?", 40, Vector2(60, 460), Vector2(600, 60), Color(1, 0.85, 0.3)))
	m.add_child(_label("%s  ★%d %s" % [info["name"], u.grade, Data.grade_name(u.grade)], 30, Vector2(60, 530),
			Vector2(600, 50), Data.grade_color(u.grade)))
	m.add_child(_label("+%d 코인" % refund, 34, Vector2(60, 585), Vector2(600, 50), Color(1, 0.9, 0.5)))
	var slot_i := selected
	m.add_child(_button("res://assets/td/ui/btn_red_big.png", "판매", Vector2(95, 670), Vector2(230, 90),
			func(): close_modal(); _do_sell(slot_i), 34))
	m.add_child(_button("res://assets/td/ui/btn_gray_big.png", "취소", Vector2(395, 670), Vector2(230, 90),
			close_modal, 34))
	open_modal(m)


func _refund(u) -> int:
	return int(round(float(Data.rule("sell_refund_g%d" % u.grade, 10)) * float(Data.unit_def(u.char_id).get("sell_mult", 1.0))))


func _do_sell(i: int) -> void:
	var u = slots[i]
	if u == null:
		return
	coins += _refund(u)
	_remove_unit(i)
	if selected == i:
		selected = -1
	_recalc_units()
	Sfx.play("coin")
	overlay.queue_redraw()


# ------------------------------------------------------------------ 전투
func find_target(u):
	var r2: float = u.range_px * u.range_px
	var rnd: bool = u.stat["target"] == "random"
	var best = null
	var best_d := -1.0
	var n := 0
	var up: Vector2 = u.position
	for e in enemies:
		if e.dead or e.position.distance_squared_to(up) > r2:
			continue
		if rnd:
			n += 1
			if rng.randi() % n == 0:
				best = e
		elif e.dist > best_d:
			best_d = e.dist
			best = e
	return best


## 지금 필드에서 가장 앞선 적인가 (똑쟁이 '선두' 판정)
func is_leader(t) -> bool:
	for e in enemies:
		if not e.dead and e.dist > t.dist:
			return false
	return true


func apply_hit(target, dmg: float, stat: Dictionary, src = null, extra: Dictionary = {}) -> void:
	if src != null:
		dmg = src.on_hit(target, dmg, extra)
	var eff := str(stat["effect"])
	var area := float(stat["area_tiles"]) * T
	var area_f := 0.6
	var col := Color(1, 0.95, 0.6) if (extra.get("punch", false) or extra.get("free", false)) else Color.WHITE
	var roul := -1
	match eff:
		"dice":        # 눈/3.5 배 피해, 6 이면 반경 1.5칸 폭발(100%)
			var roll := rng.randi_range(1, 6)
			dmg *= float(roll) / 3.5
			if roll == 6:
				area = 1.5 * T
				area_f = 1.0
				col = Color(1, 0.6, 0.3)
				spawn_fx("fx", "death_boom", target.position, 0.9)
		"pierce":      # 뒤의 적에게 효과값 배 피해
			area_f = float(stat["effect_value"])
		"roulette":    # 25% 감속 / 25% 기절 / 25% 2배 / 25% 코인
			roul = rng.randi() % 4
			if roul == 2:
				dmg *= 2.0
				col = Color(1, 0.8, 0.3)
			elif roul == 3:
				coins += 2
	var center: Vector2 = target.position
	target.killer = src
	target.take_hit(dmg, col)
	if area > 0.0:
		if src != null and src.char_id == "yeoreum":
			spawn_skill_fx("yeo_bark", center, 0.9, 14.0)
		for e in enemies.duplicate():
			if e != target and not e.dead and e.position.distance_to(center) <= area:
				e.killer = src
				e.take_hit(dmg * area_f, Color(0.9, 0.9, 0.9))
	if target.dead:
		return
	match eff:
		"mark":        # 룰북: 모든 유닛의 피해 증가 표식
			target.mark_t = float(stat["effect_time"])
			target.mark_v = float(stat["effect_value"])
			return
		"roulette":
			if roul == 0:
				_apply_slow(target, 0.5, float(stat["effect_time"]), src)
			elif roul == 1 and not target.boss:
				target.stun_t = 0.8
			return
	if eff == "none" or eff == "aura_spd" or eff == "dice" or eff == "pierce" or eff == "coin_kill":
		return
	if randf() > float(stat["effect_chance"]):
		return
	var t := float(stat["effect_time"])
	if eff == "slow":
		_apply_slow(target, float(stat["effect_value"]), t, src)
	elif eff == "stun" and not target.boss:
		target.stun_t = t


func _apply_slow(target, f: float, t: float, src) -> void:
	if target.boss:
		f *= float(Data.rule("boss_slow_resist", 0.5))
	target.slow_f = 1.0 - f
	target.slow_t = t
	if src != null and src.char_id == "mani":
		spawn_skill_fx("mani_charm", target.position + Vector2(0, -16), 0.7, 10.0)


func on_enemy_died(e) -> void:
	enemies.erase(e)
	var rew: int = e.reward
	if e.killer != null and is_instance_valid(e.killer) and str(e.killer.stat["effect"]) == "coin_kill":
		rew = int(round(rew * (1.0 + float(e.killer.stat["effect_value"]))))
	coins += rew
	kills += 1
	var dfx := "death_puff"
	var dsc := 1.0
	if e.boss:
		dfx = "boss_explode"
		dsc = 1.5
	elif str(e.id).begins_with("elite_"):
		dfx = "death_boom"
		dsc = 1.3
	else:
		dfx = ["death_puff", "death_star", "death_confetti"][rng.randi() % 3]
	spawn_fx("fx", dfx, e.position, dsc)
	spawn_fx("fx", "coin_pop", e.position + Vector2(0, -22))
	Sfx.play("boss_die" if e.boss else "enemy_die")
	var was_boss: bool = e.boss
	e.queue_free()
	if was_boss and not game_over:
		shake(14.0, 0.6)
		buzz(120)
		var fast_limit := float(Data.rule("boss_time_limit", 60)) - float(Data.rule("boss_fast_sec", 30))
		if boss_timer >= fast_limit:
			coins += int(Data.rule("boss_fast_bonus", 100))
			_popup("빠른 처치 보너스!", Color(1, 0.9, 0.4), 520.0)
		if wave >= _total_waves():
			_end(true)
		else:
			_start_wave(wave + 1)


func _boss_alive() -> bool:
	for e in enemies:
		if e.boss and not e.dead:
			return true
	return false


# ------------------------------------------------------------------ 웨이브
func _pick_enemy(w: int) -> String:
	var pool: Array = []
	var total := 0.0
	if not dungeon_data.is_empty():       # 던전 적풀: 웨이브 1~10, 11~20, 21~30, 31~40
		var pools: Array = dungeon_data["pools"]
		var seg := clampi(int((w - 1) / 10), 0, pools.size() - 1)
		for r in pools[seg]:
			if Data.d["enemies"].has(str(r["enemy"])):
				pool.append({"enemy": r["enemy"], "weight": r["weight"]})
				total += float(r["weight"])
	else:
		for r in Data.d["waves"]:
			if w >= int(r["from"]) and w <= int(r["to"]):
				pool.append(r)
				total += float(r["weight"])
	var x := rng.randf() * total
	for r in pool:
		x -= float(r["weight"])
		if x <= 0.0:
			return str(r["enemy"])
	return str(pool[0]["enemy"]) if not pool.is_empty() else "slime"


## 웨이브 시작. 이벤트 웨이브면 카드 선택(시간 정지)이 끝난 뒤 _begin_wave 로 이어짐
func _start_wave(w: int) -> void:
	if _is_event_wave(w):
		var cards := _draw_event_cards()
		if not cards.is_empty():
			pending_wave = w
			clear_t = -1.0
			_open_event(w, cards)
			return
	_begin_wave(w)


func _is_event_wave(w: int) -> bool:
	if Data.events.is_empty():
		return false
	var list := str(Data.rule("event_waves", "")).split(",", false)
	return list.has(str(w)) and not Data.d["bosses"].has(str(w))


func _boss_hp_mult() -> float:
	var v = dungeon_data.get("boss_hp_mult", null)
	if v is float or v is int:
		return float(v)
	return float(dungeon_data.get("hp_mult", 1.0))     # 엑셀 내보내기 값이 이상하면 일반 HP 배수 사용


func _begin_wave(w: int) -> void:
	wave = w
	wave_time = 0.0
	clear_t = -1.0
	spawn_queue.clear()
	for u in absent_units:      # 노쇼는 한 웨이브만
		if is_instance_valid(u):
			u.set_absent(false)
	absent_units.clear()
	var growth := float(Data.rule("reward_growth", 0.08))
	var d := dungeon_data
	var has_d := not d.is_empty()
	var coin_mult := float(d.get("coin_mult", 1.0)) if has_d else 1.0
	var bosses: Dictionary = Data.d["bosses"]
	is_boss_wave = bosses.has(str(w))
	var bonus := int(round(float(Data.rule("wave_bonus_base", 0)) + float(Data.rule("wave_bonus_per_wave", 0)) * w))
	if bonus > 0:
		coins += bonus
	if is_boss_wave:
		var b: Dictionary = bosses[str(w)]
		var bid := str(b["enemy"])
		if has_d and d.get("bosses", {}).has(str(w)) and Data.d["enemies"].has(str(d["bosses"][str(w)])):
			bid = str(d["bosses"][str(w)])
		var info: Dictionary = Data.d["enemies"][bid]
		var bhp := float(b["hp"]) * (_boss_hp_mult() if has_d else 1.0)
		boss_timer = float(Data.rule("boss_time_limit", 60))
		spawn_queue.append({"id": bid, "hp": bhp,
				"reward": int(round(float(info["reward"]) * (1.0 + growth * w) * coin_mult))})
		spawn_interval = 0.5
		Sfx.play("boss_warning")
		Sfx.play_bgm("bgm_boss")
		_boss_banner()
		_popup("BOSS!", Color(1, 0.4, 0.4), 330.0)
		_popup(str(info.get("name", "")), Color(1, 0.8, 0.8), 590.0, 38)
		_boss_intro()
	else:
		var cmult := float(d.get("count_mult", 1.0)) if has_d else 1.0
		var count := int(round((float(Data.rule("count_base", 14)) + float(Data.rule("count_per_wave", 0.6)) * w) * cmult))
		var mult := pow(float(Data.rule("hp_growth", 1.12)), w - 1)
		if has_d:
			mult *= Data.hp_curve_at(w) * float(d.get("hp_mult", 1.0))
		for i in count:
			var eid := _pick_enemy(w)
			var info: Dictionary = Data.d["enemies"][eid]
			spawn_queue.append({"id": eid, "hp": float(info["hp"]) * mult,
					"reward": max(1, int(round(float(info["reward"]) * (1.0 + growth * w) * coin_mult)))})
		spawn_interval = (float(Data.rule("wave_seconds", 25)) * 0.6) / max(1, count)
		Sfx.play("wave_start")
		Sfx.play_bgm("bgm_battle")
		_wave_banner(w)
	if bonus > 0 and not autoplay:
		_popup("웨이브 보너스 +%d" % bonus, Color(1, 0.9, 0.5), 700.0, 26)
	spawn_timer = 0.0
	if autoplay:
		var gs: Array = []
		for g in range(1, Data.max_grade() + 1):
			gs.append(_slots_of_grade(g).size())
		print("[wave %d] coins=%d units(g1..g5)=%s enemies=%d t=%.0fs" % [w, coins, str(gs), enemies.size(), elapsed])


# ------------------------------------------------------------------ 모임 이벤트 (웨이브 사이 카드 3택1)
func _event_def(id: String) -> Dictionary:
	for e in Data.events:
		if str(e["id"]) == id:
			return e
	return {}


## 좋음 1 + 도박/중립 1 + (가끔) 나쁨 1 — 부족하면 남은 것으로 채움. enabled 만.
func _draw_event_cards() -> Array:
	var avail: Array = []
	for e in Data.events:
		if bool(e.get("enabled", false)):
			avail.append(e)
	var out: Array = []
	var groups: Array = [["좋음"], ["도박", "중립"]]
	if rng.randf() < 0.4:
		groups.append(["나쁨"])
	for g in groups:
		var cand: Array = []
		for e in avail:
			if g.has(str(e["kind"])) and not out.has(e):
				cand.append(e)
		if not cand.is_empty():
			out.append(_weighted_event(cand))
	while out.size() < 3:
		var cand2: Array = []
		for e in avail:
			if not out.has(e) and str(e["kind"]) != "나쁨":
				cand2.append(e)
		if cand2.is_empty():
			break
		out.append(_weighted_event(cand2))
	out.shuffle()
	return out


func _weighted_event(cand: Array) -> Dictionary:
	var total := 0.0
	for e in cand:
		total += float(e.get("weight", 1))
	var x := rng.randf() * total
	for e in cand:
		x -= float(e.get("weight", 1))
		if x <= 0.0:
			return e
	return cand[0]


func _open_event(w: int, cards: Array) -> void:
	if autoplay:      # 봇은 첫 장을 고름(도박 판돈은 걸지 않음)
		_event_chosen(cards[0], 0)
		return
	var m := EventsScript.new()
	m.setup(self, w, cards, float(Data.rule("event_pick_sec", 8)))
	m.picked.connect(_event_chosen)
	open_modal(m)


func _event_chosen(ev: Dictionary, arg: int) -> void:
	close_modal()
	var msg := _apply_event(ev, arg)
	_begin_wave(pending_wave)
	if msg != "" and not autoplay:
		_popup(msg, Color(1, 0.95, 0.7), 640.0, 30)


func _apply_event(ev: Dictionary, arg: int) -> String:
	var w := pending_wave
	var v1 := float(ev.get("v1", 0))
	var v2 := float(ev.get("v2", 0))
	var v3 := float(ev.get("v3", 0))
	match str(ev["id"]):
		"ev_start_roulette":
			Sfx.play("roulette_spin")
			match rng.randi() % 3:
				0:
					atk_buff = 1.0 + v1
					atk_buff_wave = w
					return "룰렛: 공격력 +%d%% (이번 웨이브)" % int(v1 * 100)
				1:
					coins += int(v2)
					return "룰렛: 코인 +%d" % int(v2)
				_:
					var i := _free_slot()
					if i >= 0:
						_place_unit(i, _random_char(), 1)
						_recalc_units()
						spawn_fx("fx", "summon_poof", slot_center(i))
						return "룰렛: 무료 소환!"
					coins += 20
					return "룰렛: 무료 소환인데 자리가 없어서 코인 +20"
		"ev_hourglass":
			Sfx.play("hourglass_flip")
			freeze_t = v1
			freeze_total = v1
			global_slow_t = v1 + v2
			global_slow_f = v3
			return "모래시계 뒤집었다! 적 %d초 정지" % int(v1)
		"ev_dice_bet":
			var bet := arg
			if bet <= 0 or bet > coins:
				return "안 걸었다. 쫄보."
			var roll := rng.randi_range(1, 6)
			if roll <= 2:
				coins -= bet
				return "주사위 %d… -%d 코인" % [roll, bet]
			if roll >= 5:
				coins += bet
				return "주사위 %d! +%d 코인" % [roll, bet]
			return "주사위 %d. 본전." % roll
		"ev_host_call":
			var i2 := _free_slot()
			if i2 >= 0:
				_place_unit(i2, _random_char(), int(v1))
				_recalc_units()
				spawn_fx("fx", "merge_up_g2", slot_center(i2), 1.1)
				return "벙주 등장! %d성 무료" % int(v1)
			coins += 40
			return "벙주 왔는데 자리가 없다. 코인 +40"
		"ev_noshow":
			var live: Array = []
			for u in slots:
				if u != null:
					live.append(u)
			coins += int(v2)
			if live.is_empty():
				return "노쇼… 위약금 +%d" % int(v2)
			var pick = live[rng.randi() % live.size()]
			pick.set_absent(true)
			absent_units.append(pick)
			return "%s 노쇼! 위약금 +%d" % [Data.unit_name(pick.char_id), int(v2)]
	return ""


func _wave_banner(w: int) -> void:
	if autoplay:
		return
	var tr := TextureRect.new()
	tr.texture = U.tex("res://assets/stage/banners/wave_start.png")
	tr.position = Vector2(-720, 380)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(_label("WAVE %d" % w, 64, Vector2.ZERO, Vector2(720, 160), Color(1, 0.95, 0.7)))
	ui.add_child(tr)
	var tw := create_tween()
	tw.tween_property(tr, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(tr, "modulate:a", 0.0, 0.3)
	tw.tween_callback(tr.queue_free)


func _boss_banner() -> void:
	if autoplay:
		return
	var tr := TextureRect.new()
	tr.texture = U.tex("res://assets/stage/banners/boss_warning_0.png")
	tr.position = Vector2(0, 350)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(tr)
	var vg := TextureRect.new()
	vg.texture = U.tex("res://assets/stage/banners/boss_vignette.png")
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(vg)
	var tw := create_tween()
	for i in 6:      # 사이렌처럼 두 프레임 깜빡임
		tw.tween_callback(func(): tr.texture = U.tex("res://assets/stage/banners/boss_warning_%d.png" % (i % 2)))
		tw.tween_interval(0.25)
	tw.tween_property(tr, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(vg, "modulate:a", 0.0, 0.5)
	tw.tween_callback(tr.queue_free)
	tw.tween_callback(vg.queue_free)


func _boss_intro() -> void:
	if autoplay:
		return
	shake(10.0, 0.7)
	buzz(80)
	boss_flash.modulate.a = 0.45
	var tw := create_tween()
	tw.tween_property(boss_flash, "modulate:a", 0.0, 0.9)


func _spawn_tick(delta: float) -> void:
	if spawn_queue.is_empty():
		return
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = spawn_interval
	var s: Dictionary = spawn_queue.pop_front()
	var e := EnemyScript.new()
	enemies_node.add_child(e)
	e.setup(self, str(s["id"]), float(s["hp"]), int(s["reward"]))
	enemies.append(e)


func _process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var k: float = clamp(_shake_t / 0.6, 0.0, 1.0)
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_amp * k
		field.position = FIELD_POS + off
		bg.position = off
		if _shake_t <= 0.0:
			_shake_amp = 0.0
			field.position = FIELD_POS
			bg.position = Vector2.ZERO
	if _press_slot >= 0 and not _dragging and not _long_done and not get_tree().paused 			and Time.get_ticks_msec() - _press_ms >= LONG_PRESS_MS and slots[_press_slot] != null:
		_long_done = true
		selected = _press_slot
		overlay.queue_redraw()
		_show_card(slots[_press_slot])
	if game_over:
		return
	elapsed += delta
	if freeze_t > 0.0:
		freeze_t -= delta
	if global_slow_t > 0.0:
		global_slow_t -= delta
	_spawn_tick(delta)
	wave_time += delta
	if is_boss_wave:
		boss_timer -= delta
		if boss_timer <= 0.0 and _boss_alive():
			_end(false, "보스를 제한시간 안에 잡지 못했어요")
			return
	elif spawn_queue.is_empty() and enemies.is_empty():
		# 적을 다 잡았으면 N초(clear_next_wave_sec) 뒤 다음 웨이브
		if clear_t < 0.0:
			clear_t = float(Data.rule("clear_next_wave_sec", 3))
		clear_t -= delta
		if clear_t <= 0.0:
			if wave >= _total_waves():
				_end(true)
				return
			_start_wave(wave + 1)
	elif wave_time >= float(Data.rule("wave_seconds", 25)):
		if wave >= _total_waves():
			_end(true)
			return
		_start_wave(wave + 1)
	var limit := int(Data.rule("field_limit", 60))
	if enemies.size() > limit:
		_end(false, "필드 적 %d / 한도 %d" % [enemies.size(), limit])
		return
	_hud_t += delta
	if _hud_t >= 0.08:
		_hud_t = 0.0
		_update_hud()
	if autoplay:
		_autoplay_tick(delta)
	if shot_path != "" and wave >= 8 and wave_time > 9.0 and not shot_done:
		shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()


func _autoplay_tick(delta: float) -> void:
	_auto_t += delta
	if _auto_t < 0.25:
		return
	_auto_t = 0.0
	var guard := 0
	while _mergeable_grade() >= 0 and guard < 4:
		merge()
		guard += 1
	guard = 0
	var cost := int(Data.rule("summon_cost", 20))
	while coins >= cost and _free_slot() >= 0 and guard < 6:
		summon()
		guard += 1


# ------------------------------------------------------------------ 끝 · 일시정지
func _end(win: bool, reason: String = "") -> void:
	if game_over:
		return
	game_over = true
	_press_slot = -1
	Sfx.stop_bgm()
	Sfx.play("win" if win else "lose")
	if autoplay:
		var gs: Array = []
		for g in range(1, Data.max_grade() + 1):
			gs.append(_slots_of_grade(g).size())
		var nd := 0
		var np := 0
		var maxen := 0
		for u in slots:
			if u != null:
				nd += 1 if Data.is_dud(u.char_id) else 0
				np += 1 if Data.is_pet(u.char_id) else 0
		print("RESULT win=%s wave=%d kills=%d coins=%d units=%s time=%.0fs dungeon=%d duds=%d pets=%d %s" % [win, wave, kills, coins, str(gs), elapsed, dungeon_n, nd, np, reason])
		get_tree().quit()
		return
	close_modal()
	var gcount: Dictionary = {}
	for g in range(1, Data.max_grade() + 1):
		gcount["g%d" % g] = _slots_of_grade(g).size()
	var sv0 := get_node_or_null("/root/Save")
	if sv0 != null and "run_meta" in sv0:
		sv0.run_meta = {"units": gcount, "play_sec": int(elapsed)}
	run_result = {"shards": 0, "best_wave": wave, "new_best": false}
	var sv := get_node_or_null("/root/Save")
	if sv != null and sv.has_method("record_run"):
		var r = sv.record_run(win, wave, kills, coins)
		if r is Dictionary:
			run_result = r
	get_tree().paused = true
	Engine.time_scale = 1.0
	var layer: Control = ResultScreen.build(self, win, reason, run_result)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.add_child(layer)


func _restart() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _to_lobby() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _toggle_pause() -> void:
	if game_over:
		return
	Sfx.play("button")
	if pause_layer != null:
		pause_layer.queue_free()
		pause_layer = null
		get_tree().paused = _modal != null
		return
	close_modal()
	get_tree().paused = true
	pause_layer = Control.new()
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.size = Vector2(720, 1280)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.size = Vector2(720, 1280)
	pause_layer.add_child(dim)
	pause_layer.add_child(_label("일시정지", 66, Vector2(0, 300), Vector2(720, 90), Color(1, 0.85, 0.3)))
	var y := 420.0
	pause_layer.add_child(_button("res://assets/td/ui/btn_green_big.png", "계속하기", Vector2(210, y), Vector2(300, 100),
			_toggle_pause, 33))
	y += 135.0
	if ResourceLoader.exists("res://scenes/settings_panel.tscn"):
		pause_layer.add_child(_button("res://assets/td/ui/btn_blue_big.png", "설정", Vector2(210, y), Vector2(300, 100),
				_open_settings, 33))
		y += 135.0
	var qb := _button("res://assets/td/ui/btn_gray_big.png", _quick_text(), Vector2(210, y), Vector2(300, 100),
			Callable(), 24)
	qb.pressed.connect(func():
		GS.set_quick_merge(not GS.quick_merge())
		(qb.get_child(0) as Label).text = _quick_text())
	pause_layer.add_child(qb)
	y += 135.0
	pause_layer.add_child(_button("res://assets/td/ui/btn_red_big.png", "포기하기", Vector2(210, y), Vector2(300, 100),
			_to_lobby, 33))
	ui.add_child(pause_layer)


func _quick_text() -> String:
	return "합성 팝업 생략: %s" % ("켜짐" if GS.quick_merge() else "꺼짐")


func _open_settings() -> void:
	var ps = load("res://scenes/settings_panel.tscn")
	if ps == null or pause_layer == null:
		return
	var panel: Node = ps.instantiate()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.add_child(panel)
	if panel.has_signal("closed"):       # 설정 패널의 뒤로가기 → 닫기는 쓰는 쪽(여기)이 함
		panel.connect("closed", panel.queue_free)
