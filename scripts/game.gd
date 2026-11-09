extends Node2D
## 메인 게임: 순환 경로 + 슬롯 18칸 + 랜덤 소환/합성/판매 + 웨이브/보스.
## 규칙 수치는 data/game_data.json (엑셀 '게임규칙' 등)에서 옵니다. 실행 인자 `-- --autoplay` 면 자동 플레이 시뮬레이션.

const U = preload("res://scripts/util.gd")
const UnitScript = preload("res://scripts/unit.gd")
const EnemyScript = preload("res://scripts/enemy.gd")

const T := 64
const COLS := 8
const ROWS := 5
const SLOT_COLS := 6
const SLOT_ROWS := 3
const SLOT_COUNT := 18
const FIELD_POS := Vector2(40, 200)
const FIELD_SCALE := 1.25
const PATH_TOTAL := 1408.0
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
	_build_world()
	_build_ui()
	if autoplay:
		Engine.time_scale = 4.0 if shot_path != "" else 8.0
	Sfx.play_bgm("bgm_battle")
	_start_wave(1)


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
	proj_node = Node2D.new()
	field.add_child(proj_node)
	fx_node = Node2D.new()
	fx_node.z_index = 8
	field.add_child(fx_node)
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
	var a := Vector2(T / 2.0, T / 2.0)
	var b := Vector2((COLS - 1) * T + T / 2.0, T / 2.0)
	var c := Vector2((COLS - 1) * T + T / 2.0, (ROWS - 1) * T + T / 2.0)
	var e := Vector2(T / 2.0, (ROWS - 1) * T + T / 2.0)
	var pts: Array = [a, b, c, e, a]
	var m: float = fposmod(d, PATH_TOTAL)
	for i in 4:
		var seg: float = (pts[i] as Vector2).distance_to(pts[i + 1])
		if m <= seg:
			return (pts[i] as Vector2).lerp(pts[i + 1], m / seg)
		m -= seg
	return a


func spawn_fx(group: String, id: String, pos: Vector2, scale_value: float = 1.0) -> void:
	var sf = U.atlas_frames(group, id, false)
	if sf == null:
		return
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.position = pos
	a.scale = Vector2(scale_value, scale_value)
	fx_node.add_child(a)
	a.animation_finished.connect(a.queue_free)
	a.play("default")


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
	ui.add_child(_icon("res://assets/td/ui/icon_skull.png", Vector2(16, 12), 1.5))
	lbl_count = _label("0 / 60", 33, Vector2(70, 12), Vector2(200, 48), Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_count)
	lbl_wave = _label("WAVE 1", 38, Vector2(190, 8), Vector2(320, 60), Color(1, 0.85, 0.3))
	ui.add_child(lbl_wave)
	lbl_timer = _label("00", 33, Vector2(210, 66), Vector2(300, 48))
	ui.add_child(lbl_timer)
	ui.add_child(_icon("res://assets/td/ui/icon_coin.png", Vector2(540, 14), 1.5))
	lbl_coins = _label("0", 33, Vector2(592, 12), Vector2(120, 48), Color(1, 0.9, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_coins)
	ui.add_child(_button("res://assets/td/ui/btn_gray.png", "II", Vector2(600, 70), Vector2(100, 48), _toggle_pause, 33))

	lbl_info = _label("유닛을 눌러 선택하세요", 22, Vector2(30, 660), Vector2(660, 80), Color.WHITE,
			HORIZONTAL_ALIGNMENT_LEFT)
	lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui.add_child(lbl_info)
	btn_merge = _button("res://assets/td/ui/btn_blue_big.png", "합성", Vector2(30, 760), Vector2(210, 80), merge, 33)
	btn_sell = _button("res://assets/td/ui/btn_red_big.png", "판매", Vector2(255, 760), Vector2(210, 80), sell, 33)
	btn_speed = _button("res://assets/td/ui/btn_gray_big.png", "배속 x1", Vector2(480, 760), Vector2(210, 80), _toggle_speed, 28)
	ui.add_child(btn_merge)
	ui.add_child(btn_sell)
	ui.add_child(btn_speed)
	lbl_pity = _label("", 22, Vector2(30, 860), Vector2(660, 40), Color(0.8, 0.9, 1.0), HORIZONTAL_ALIGNMENT_LEFT)
	ui.add_child(lbl_pity)
	var cost := int(Data.rule("summon_cost", 20))
	btn_summon = _button("res://assets/td/ui/btn_green_big.png", "랜덤 소환  %d" % cost, Vector2(110, 940),
			Vector2(500, 150), summon, 44)
	ui.add_child(btn_summon)
	ui.add_child(_label("같은 등급 3개 → 한 단계 위 랜덤 캐릭터", 22, Vector2(30, 1120), Vector2(660, 40),
			Color(0.8, 0.8, 0.95)))


func _update_hud() -> void:
	var limit := int(Data.rule("field_limit", 60))
	lbl_count.text = "%d / %d" % [enemies.size(), limit]
	lbl_count.add_theme_color_override("font_color",
			Color(1, 0.45, 0.45) if enemies.size() > limit * 0.8 else Color.WHITE)
	lbl_wave.text = "%s %d / %d" % ["BOSS" if is_boss_wave else "WAVE", wave, int(Data.rule("total_waves", 40))]
	if is_boss_wave:
		lbl_timer.text = "제한시간 %d" % int(ceil(max(boss_timer, 0.0)))
	else:
		lbl_timer.text = "%d초" % int(ceil(max(float(Data.rule("wave_seconds", 25)) - wave_time, 0.0)))
	lbl_coins.text = str(coins)
	var cost := int(Data.rule("summon_cost", 20))
	btn_summon.modulate = Color.WHITE if (coins >= cost and _free_slot() >= 0) else Color(0.6, 0.6, 0.6)
	btn_merge.modulate = Color.WHITE if _mergeable_grade() >= 0 else Color(0.5, 0.5, 0.5)
	btn_sell.modulate = Color.WHITE if (selected >= 0 and slots[selected] != null) else Color(0.5, 0.5, 0.5)
	lbl_pity.text = "대박 합성(2단계 점프) %d%%  ·  천장 %d / %d" % [
		int(round(float(Data.rule("lucky_merge_chance", 0.05)) * 100.0)), lucky_counter,
		int(Data.rule("pity_limit", 10))]
	_update_info()


func _update_info() -> void:
	if selected >= 0 and slots[selected] != null:
		var u = slots[selected]
		var info: Dictionary = Data.d["characters"][u.char_id]
		var same := _slots_of_grade(u.grade).size()
		lbl_info.text = "%s  ★%d %s   공격력 %d  사거리 %.1f칸   [같은 등급 %d/3]" % [
			info["name"], u.grade, Data.grade_name(u.grade), int(u.damage), float(u.stat["range_tiles"]), same]
	else:
		lbl_info.text = "빈 칸을 누르면 유닛을 옮길 수 있어요. 유닛을 눌러 선택하세요."


func _popup(text: String, color: Color = Color(1, 0.85, 0.3), y: float = 420.0) -> void:
	var l := _label(text, 55, Vector2(0, y), Vector2(720, 70), color)
	ui.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", y - 50.0, 1.0)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.5)
	tw.tween_callback(l.queue_free)


func _toggle_speed() -> void:
	speed_on = not speed_on
	Engine.time_scale = 2.0 if speed_on else 1.0
	(btn_speed.get_child(0) as Label).text = "배속 x2" if speed_on else "배속 x1"
	Sfx.play("button")


# ------------------------------------------------------------------ 입력
func _unhandled_input(event: InputEvent) -> void:
	if game_over or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var lp := field.get_local_mouse_position()
		var col := int(floor(lp.x / T))
		var row := int(floor(lp.y / T))
		if col >= 1 and col <= SLOT_COLS and row >= 1 and row <= SLOT_ROWS:
			_tap_slot((row - 1) * SLOT_COLS + (col - 1))
		else:
			selected = -1
			overlay.queue_redraw()


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
	else:
		selected = i
	overlay.queue_redraw()


# ------------------------------------------------------------------ 소환 · 합성 · 판매
func _free_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1


func _random_char() -> String:
	var keys: Array = Data.d["characters"].keys()
	return str(keys[rng.randi() % keys.size()])


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
		return
	coins -= cost
	_place_unit(i, _random_char(), 1)
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


func merge() -> void:
	var g := _mergeable_grade()
	if game_over or g < 0:
		Sfx.play("no_coin")
		return
	var idxs := _slots_of_grade(g)
	var first: int = idxs[0]
	if selected >= 0 and slots[selected] != null and slots[selected].grade == g:
		first = selected
	var picks: Array = [first]
	var cid: String = slots[first].char_id
	for i in idxs:      # 같은 캐릭터 먼저
		if i != first and slots[i].char_id == cid and picks.size() < 3:
			picks.append(i)
	for i in idxs:
		if not picks.has(i) and picks.size() < 3:
			picks.append(i)
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
	for i in picks:
		_remove_unit(i)
	_place_unit(first, _random_char(), new_g)
	selected = first
	spawn_fx("fx", "merge_flash", slot_center(first))
	Sfx.play("merge_%d" % new_g)
	if lucky:
		_popup("대박! %d성 점프" % new_g, Color(1, 0.6, 0.9), 520.0)
	overlay.queue_redraw()


func sell() -> void:
	if game_over or selected < 0 or slots[selected] == null:
		return
	var u = slots[selected]
	coins += int(Data.rule("sell_refund_g%d" % u.grade, 10))
	_remove_unit(selected)
	selected = -1
	Sfx.play("coin")
	overlay.queue_redraw()


# ------------------------------------------------------------------ 전투
func find_target(u):
	var cands: Array = []
	for e in enemies:
		if not e.dead and e.position.distance_to(u.position) <= u.range_px:
			cands.append(e)
	if cands.is_empty():
		return null
	if str(u.stat["target"]) == "random":
		return cands[rng.randi() % cands.size()]
	var best = null
	var best_d := -1.0
	for e in cands:
		if e.dist > best_d:
			best_d = e.dist
			best = e
	return best


func apply_hit(target, dmg: float, stat: Dictionary) -> void:
	var area := float(stat["area_tiles"]) * T
	var center: Vector2 = target.position
	target.take_hit(dmg)
	if area > 0.0:
		for e in enemies.duplicate():
			if e != target and not e.dead and e.position.distance_to(center) <= area:
				e.take_hit(dmg * 0.6)
	if target.dead:
		return
	var eff := str(stat["effect"])
	if eff == "none" or randf() > float(stat["effect_chance"]):
		return
	var t := float(stat["effect_time"])
	if eff == "slow":
		var f := float(stat["effect_value"])
		if target.boss:
			f *= float(Data.rule("boss_slow_resist", 0.5))
		target.slow_f = 1.0 - f
		target.slow_t = t
	elif eff == "stun" and not target.boss:
		target.stun_t = t


func on_enemy_died(e) -> void:
	enemies.erase(e)
	coins += e.reward
	kills += 1
	spawn_fx("fx", "death_puff", e.position)
	spawn_fx("fx", "coin_pop", e.position + Vector2(0, -22))
	Sfx.play("boss_die" if e.boss else "enemy_die")
	var was_boss: bool = e.boss
	e.queue_free()
	if was_boss and not game_over:
		var fast_limit := float(Data.rule("boss_time_limit", 60)) - float(Data.rule("boss_fast_sec", 30))
		if boss_timer >= fast_limit:
			coins += int(Data.rule("boss_fast_bonus", 100))
			_popup("빠른 처치 보너스!", Color(1, 0.9, 0.4), 520.0)
		if wave >= int(Data.rule("total_waves", 40)):
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


func _start_wave(w: int) -> void:
	wave = w
	wave_time = 0.0
	spawn_queue.clear()
	var growth := float(Data.rule("reward_growth", 0.08))
	var bosses: Dictionary = Data.d["bosses"]
	is_boss_wave = bosses.has(str(w))
	if is_boss_wave:
		var b: Dictionary = bosses[str(w)]
		var info: Dictionary = Data.d["enemies"][b["enemy"]]
		boss_timer = float(Data.rule("boss_time_limit", 60))
		spawn_queue.append({"id": str(b["enemy"]), "hp": float(b["hp"]),
				"reward": int(float(info["reward"]) * (1.0 + growth * w))})
		spawn_interval = 0.5
		Sfx.play("boss_warning")
		Sfx.play_bgm("bgm_boss")
		_popup("BOSS!", Color(1, 0.4, 0.4))
	else:
		var count := int(round(float(Data.rule("count_base", 14)) + float(Data.rule("count_per_wave", 0.6)) * w))
		var mult := pow(float(Data.rule("hp_growth", 1.12)), w - 1)
		for i in count:
			var eid := _pick_enemy(w)
			var info: Dictionary = Data.d["enemies"][eid]
			spawn_queue.append({"id": eid, "hp": float(info["hp"]) * mult,
					"reward": max(1, int(round(float(info["reward"]) * (1.0 + growth * w))))})
		spawn_interval = (float(Data.rule("wave_seconds", 25)) * 0.6) / max(1, count)
		Sfx.play("wave_start")
		Sfx.play_bgm("bgm_battle")
		_popup("WAVE %d" % w)
	spawn_timer = 0.0
	if autoplay:
		var gs: Array = []
		for g in range(1, Data.max_grade() + 1):
			gs.append(_slots_of_grade(g).size())
		print("[wave %d] coins=%d units(g1..g5)=%s enemies=%d t=%.0fs" % [w, coins, str(gs), enemies.size(), elapsed])


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
	if game_over:
		return
	elapsed += delta
	_spawn_tick(delta)
	wave_time += delta
	if is_boss_wave:
		boss_timer -= delta
		if boss_timer <= 0.0 and _boss_alive():
			_end(false, "보스를 제한시간 안에 잡지 못했어요")
			return
	elif wave_time >= float(Data.rule("wave_seconds", 25)):
		if wave >= int(Data.rule("total_waves", 40)):
			_end(true)
			return
		_start_wave(wave + 1)
	var limit := int(Data.rule("field_limit", 60))
	if enemies.size() > limit:
		_end(false, "필드 적 %d / 한도 %d" % [enemies.size(), limit])
		return
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
	Sfx.stop_bgm()
	Sfx.play("win" if win else "lose")
	if autoplay:
		var gs: Array = []
		for g in range(1, Data.max_grade() + 1):
			gs.append(_slots_of_grade(g).size())
		print("RESULT win=%s wave=%d kills=%d coins=%d units=%s time=%.0fs %s" % [win, wave, kills, coins, str(gs), elapsed, reason])
		get_tree().quit()
		return
	get_tree().paused = true
	Engine.time_scale = 1.0
	var layer := Control.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.size = Vector2(720, 1280)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(720, 1280)
	layer.add_child(dim)
	var banner := TextureRect.new()
	banner.texture = U.tex("res://assets/screens/result/banner_%s.png" % ("victory" if win else "defeat"))
	banner.position = Vector2(40, 250)
	layer.add_child(banner)
	var star_n := 0
	if win:
		star_n = 3 if enemies.size() < int(Data.rule("field_limit", 60)) * 0.3 else 2
	var stars := TextureRect.new()
	stars.texture = U.tex("res://assets/screens/result/stars_%d.png" % star_n)
	stars.position = Vector2(252, 470)
	layer.add_child(stars)
	layer.add_child(_label("웨이브 %d  ·  처치 %d" % [wave, kills], 33, Vector2(0, 580), Vector2(720, 60)))
	if reason != "":
		layer.add_child(_label(reason, 22, Vector2(0, 640), Vector2(720, 40), Color(1, 0.7, 0.7)))
	layer.add_child(_button("res://assets/td/ui/btn_green_big.png", "다시 하기", Vector2(100, 760), Vector2(240, 90),
			_restart, 33))
	layer.add_child(_button("res://assets/td/ui/btn_blue_big.png", "로비로", Vector2(380, 760), Vector2(240, 90),
			_to_lobby, 33))
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
		get_tree().paused = false
		return
	get_tree().paused = true
	pause_layer = Control.new()
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_layer.size = Vector2(720, 1280)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.size = Vector2(720, 1280)
	pause_layer.add_child(dim)
	pause_layer.add_child(_label("일시정지", 66, Vector2(0, 340), Vector2(720, 90), Color(1, 0.85, 0.3)))
	pause_layer.add_child(_button("res://assets/td/ui/btn_green_big.png", "계속하기", Vector2(210, 500), Vector2(300, 100),
			_toggle_pause, 33))
	pause_layer.add_child(_button("res://assets/td/ui/btn_red_big.png", "포기하기", Vector2(210, 640), Vector2(300, 100),
			_to_lobby, 33))
	ui.add_child(pause_layer)
