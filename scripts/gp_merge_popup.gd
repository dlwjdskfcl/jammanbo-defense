extends Control
## 합성 팝업: 재료 3개 → 카드 뒤집기 → 결과. 천장 게이지·확률 표시.
## 최상위(신화) 직전 등급이면 '신화 레시피'(캐릭터를 골라 5성 지정)를 고를 수 있습니다.
## 사용: var p = MergePopup.new(); p.setup(game, grade); game.open_modal(p)

const U = preload("res://scripts/util.gd")
const GS = preload("res://scripts/gp_skills.gd")
const Odds = preload("res://scripts/gp_odds.gd")
const M := "res://assets/screens/merge/"
const PANEL_POS := Vector2(80, 250)
const INK := Color(0.23, 0.14, 0.19)

var game
var g: int = 1
var recipe_char: String = ""
var _busy: bool = false
var _applied: bool = false
var _picks: Array = []
var _res: Dictionary = {}
var _mat: Array = []              # 재료 슬롯 TextureRect 3개
var _lbl_grade: Label
var _result_card: TextureRect
var _result_icon: TextureRect
var _count_img: TextureRect
var _btn_ok: TextureButton
var _btn_cancel: TextureButton
var _recipe_btns: Dictionary = {}
var _recipe_note: Label
var _pct_lbls: Dictionary = {}
var _fx_layer: Control


func setup(game_ref, grade: int) -> void:
	game = game_ref
	g = grade


func _ready() -> void:
	size = Vector2(720, 1280)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(720, 1280)
	add_child(dim)
	var panel := TextureRect.new()
	panel.texture = U.tex(M + "popup_panel.png")
	panel.position = PANEL_POS
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_text("합성하기", 40, Vector2(0, 8), Vector2(560, 56), Color.WHITE, panel)
	var t := _text("같은 등급 3개를 합쳐 한 단계 위의 랜덤 캐릭터를 얻어요", 18, Vector2(20, 84), Vector2(520, 50),
			Color(0.9, 0.9, 1.0), panel)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_grade = _text("", 34, Vector2(0, 142), Vector2(560, 48), Color(1, 0.85, 0.3), panel)

	# 재료 3 → 화살표 → 결과
	for i in 3:
		var slot := TextureRect.new()
		slot.texture = U.tex(M + "slot_empty.png")
		slot.position = Vector2(34 + i * 100, 214)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(slot)
		var ic := TextureRect.new()
		ic.position = Vector2(16, 16)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.pivot_offset = Vector2(32, 32)
		slot.add_child(ic)
		_mat.append(ic)
	var arrow := TextureRect.new()
	arrow.texture = U.tex(M + "arrow.png")
	arrow.position = Vector2(342, 238)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(arrow)
	_result_card = TextureRect.new()
	_result_card.texture = U.tex(M + "card_back.png")
	_result_card.position = Vector2(424, 214)
	_result_card.pivot_offset = Vector2(48, 48)
	_result_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_result_card)
	_result_icon = TextureRect.new()
	_result_icon.position = Vector2(424 + 16, 214 + 16)
	_result_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_icon.visible = false
	panel.add_child(_result_icon)
	_count_img = TextureRect.new()
	_count_img.position = Vector2(100, 322)
	_count_img.scale = Vector2(2, 2)
	_count_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_count_img)

	# 확률
	_text("결과 확률 (예시)", 20, Vector2(34, 352), Vector2(300, 28), Color.WHITE, panel, HORIZONTAL_ALIGNMENT_LEFT)
	var x := 26.0
	for k in Odds.KINDS:     # 반려 / 딜러 / 서포터 / 꽝 합계 확률
		_text(Odds.KIND_NAMES[k], 19, Vector2(x, 384), Vector2(60, 40), Color.WHITE if k != "dud" else Color(0.8, 0.8, 0.9),
				panel, HORIZONTAL_ALIGNMENT_LEFT)
		_pct_lbls[k] = _text("", 22, Vector2(x + 68, 384), Vector2(60, 40), Color(1, 0.85, 0.3) if k != "dud" else Color(1, 0.6, 0.6),
				panel, HORIZONTAL_ALIGNMENT_LEFT)
		x += 132.0
	# 천장 게이지
	var clover := TextureRect.new()
	clover.texture = U.tex(M + "icon_clover.png")
	clover.position = Vector2(30, 452)
	panel.add_child(clover)
	var pity := int(Data.rule("pity_limit", 10))
	var bg := TextureRect.new()
	bg.texture = U.tex(M + "pity_bg.png")
	bg.position = Vector2(80, 456)
	bg.scale = Vector2(1.2, 1.0)
	panel.add_child(bg)
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(80 + 3.6, 459)
	var ratio: float = clamp(float(game.lucky_counter) / float(pity), 0.0, 1.0)
	clip.size = Vector2(214.0 * 1.2 * ratio, 16)
	panel.add_child(clip)
	var fill := TextureRect.new()
	fill.texture = U.tex(M + "pity_fill.png")
	fill.scale = Vector2(1.2, 1.0)
	clip.add_child(fill)
	var can_lucky: bool = g + 2 <= Data.max_grade()
	_text("천장 %d / %d" % [game.lucky_counter, pity] if can_lucky else "천장 없음", 22, Vector2(350, 446),
			Vector2(190, 34), Color(1, 0.9, 0.5), panel, HORIZONTAL_ALIGNMENT_LEFT)
	var note := "대박(2단계 점프) %d%%, %d번 연속 안 나오면 다음은 확정" % [
			int(round(float(Data.rule("lucky_merge_chance", 0.05)) * 100.0)), pity]
	if not can_lucky:
		note = "최상위 등급이라 대박 점프는 없어요"
	_text(note, 17, Vector2(20, 482), Vector2(520, 24), Color(0.8, 0.8, 0.95), panel)

	_btn_ok = _btn("res://assets/td/ui/btn_green.png", "합성", Vector2(110, 510), Vector2(150, 56), _on_ok, 28, panel)
	_btn_cancel = _btn("res://assets/td/ui/btn_gray.png", "취소", Vector2(300, 510), Vector2(150, 56), _cancel, 28, panel)

	var y := PANEL_POS.y + 560.0 + 14.0
	if game.is_recipe_grade(g):
		y = _build_recipe_panel(y)
	_build_quick_check(y)
	_refresh()


func _text(text: String, size: int, pos: Vector2, box: Vector2, color: Color, parent: Node,
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
	l.add_theme_constant_override("outline_size", max(2, int(size / 7)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _btn(tex: String, text: String, pos: Vector2, sz: Vector2, cb: Callable, fsize: int, parent: Node) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = U.tex(tex)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.position = pos
	b.size = sz
	b.pressed.connect(cb)
	parent.add_child(b)
	_text(text, fsize, Vector2.ZERO, sz, Color.WHITE, b)
	return b


## 신화 레시피: 서로 다른 캐릭터 최상위-1 등급을 한 마리씩 모으면 원하는 5성 지정
func _build_recipe_panel(y: float) -> float:
	var p := Panel.new()
	p.position = Vector2(PANEL_POS.x, y)
	p.size = Vector2(560, 178)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", game._box(Color(0.16, 0.13, 0.26, 0.98), Color(0.95, 0.4, 0.5)))
	add_child(p)
	_text("신화 레시피 — %d성 서로 다른 캐릭터 한 마리씩" % g, 22, Vector2(0, 8), Vector2(560, 34), Color(1, 0.6, 0.65), p)
	var keys: Array = Data.pet_ids()
	var missing: Array = game.recipe_missing(g)
	var bw := 168.0
	var x := 14.0
	for cid in keys:
		var ok: bool = not missing.has(cid)
		var b := TextureButton.new()
		b.texture_normal = U.tex("res://assets/td/ui/btn_gold.png" if ok else "res://assets/td/ui/btn_gray.png")
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.position = Vector2(x, 50)
		b.size = Vector2(bw, 64)
		b.disabled = not ok
		b.modulate = Color.WHITE if ok else Color(0.55, 0.55, 0.6)
		b.pressed.connect(_pick_recipe.bind(str(cid)))
		p.add_child(b)
		var ic := TextureRect.new()
		ic.texture = U.tex("res://assets/td/units/%s/g%d_idle_0.png" % [cid, Data.max_grade()])
		ic.position = Vector2(4, 0)
		ic.scale = Vector2(1.0, 1.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		_text("5성 " + str(Data.unit_name(str(cid))), 20, Vector2(54, 0), Vector2(112, 64), Color.WHITE, b)
		_recipe_btns[cid] = b
		x += bw + 9.0
	var names: Array = []
	for cid in missing:
		names.append(str(Data.unit_name(str(cid))))
	var msg := "눌러서 5성을 지정하세요 (다시 누르면 랜덤)"
	if not missing.is_empty():
		msg = "지금은 사용 불가 — %d성 %s 필요" % [g, ", ".join(names)]
	_recipe_note = _text(msg, 18, Vector2(10, 122), Vector2(540, 44), Color(0.85, 0.85, 0.95), p)
	_recipe_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return y + 190.0


func _build_quick_check(y: float) -> void:
	var cb := TextureButton.new()
	var on: bool = GS.quick_merge()
	cb.texture_normal = U.tex("res://assets/screens/common/checkbox_%s.png" % ("on" if on else "off"))
	cb.position = Vector2(PANEL_POS.x + 30, y + 4)
	cb.pressed.connect(func():
		on = not on
		GS.set_quick_merge(on)
		cb.texture_normal = U.tex("res://assets/screens/common/checkbox_%s.png" % ("on" if on else "off")))
	add_child(cb)
	_text("다음부터 팝업 없이 바로 합성 (일시정지 메뉴에서 변경)", 17, Vector2(PANEL_POS.x + 70, y), Vector2(480, 40),
			Color(0.85, 0.85, 0.95), self, HORIZONTAL_ALIGNMENT_LEFT)


func _pick_recipe(cid: String) -> void:
	if _busy:
		return
	recipe_char = "" if recipe_char == cid else cid
	Sfx.play("button")
	_refresh()


func _refresh() -> void:
	_picks = game.build_plan(g, recipe_char)
	for i in 3:
		var ic: TextureRect = _mat[i]
		if i < _picks.size():
			var u = game.slots[_picks[i]]
			ic.texture = GS.unit_tex(u.char_id, u.grade)
			ic.modulate = GS.unit_mod(u.char_id, u.grade)
		else:
			ic.texture = null
	_count_img.texture = U.tex(M + "count_%dof3.png" % min(_picks.size(), 3))
	var to_g := g + 1
	if recipe_char != "":
		_lbl_grade.text = "%s ×3 → %s %s (지정)" % [Data.grade_name(g), Data.grade_name(to_g),
				Data.unit_name(recipe_char)]
	else:
		_lbl_grade.text = "%s ×3 → %s ???" % [Data.grade_name(g), Data.grade_name(to_g)]
	var kinds: Dictionary = Odds.by_kind(Odds.merge_probs(g + 1))
	for k in _pct_lbls.keys():
		var pc := int(round(float(kinds.get(k, 0.0)) * 100.0))
		if recipe_char != "":
			pc = 100 if k == "pet" else 0
		(_pct_lbls[k] as Label).text = "%d%%" % pc
	for cid in _recipe_btns.keys():
		var b: TextureButton = _recipe_btns[cid]
		if not b.disabled:
			b.modulate = Color.WHITE if (recipe_char == "" or recipe_char == cid) else Color(0.6, 0.6, 0.6)
	if _recipe_note != null and recipe_char != "":
		_recipe_note.text = "5성 %s 확정!  (대박 점프 없이 한 단계)" % Data.unit_name(recipe_char)


func _cancel() -> void:
	if _busy:
		return
	Sfx.play("button")
	game.close_modal()


func _on_ok() -> void:
	if _busy:
		return
	_busy = true
	_btn_ok.visible = false
	_btn_cancel.visible = false
	for b in _recipe_btns.values():
		b.disabled = true
	_res = game.roll_merge(g, recipe_char)
	Sfx.play("merge_%d" % int(_res["new_g"]))
	# 재료가 카드 쪽으로 모이고 → 카드가 뒤집힘 → 결과
	var tw := create_tween()
	for i in 3:
		var ic: TextureRect = _mat[i]
		tw.parallel().tween_property(ic, "position", Vector2(16 + 390 - i * 100, 16), 0.4)
		tw.parallel().tween_property(ic, "modulate:a", 0.0, 0.4)
	tw.tween_callback(_flip.bind(0))
	tw.tween_interval(0.09)
	tw.tween_callback(_flip.bind(1))
	tw.tween_interval(0.09)
	tw.tween_callback(_flip.bind(2))
	tw.tween_interval(0.09)
	tw.tween_callback(_reveal)
	tw.tween_interval(1.4)
	tw.tween_callback(_finish)


func _flip(n: int) -> void:
	if n == 0:
		Sfx.play("card_flip")
	_result_card.texture = U.tex(M + "card_flip_%d.png" % n)


func _reveal() -> void:
	_result_card.texture = U.tex(M + "card_flip_3.png")
	if bool(_res.get("dud", false)):
		Sfx.play("dud_merge")
	var cid: String = str(_res["cid"])
	var ng: int = int(_res["new_g"])
	_result_icon.texture = GS.unit_tex(cid, ng)
	_result_icon.modulate = GS.unit_mod(cid, ng)
	_result_icon.visible = true
	_result_icon.scale = Vector2(0.2, 0.2)
	_result_icon.position = Vector2(424 + 48 - 6.4, 214 + 48 - 6.4)
	var tw := create_tween()
	tw.tween_property(_result_icon, "scale", Vector2(1, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_result_icon, "position", Vector2(424 + 16, 214 + 16), 0.25)
	var nm := "%s ★%d %s" % [Data.unit_name(str(cid)), ng, Data.grade_name(ng)]
	_lbl_grade.text = ("대박! " if bool(_res["lucky"]) else ("꽝… " if bool(_res.get("dud", false)) else "")) + nm
	_lbl_grade.add_theme_color_override("font_color", Data.grade_color(ng))
	_btn_ok.visible = true
	for c in _btn_ok.get_children():
		if c is Label:
			c.text = "확인"
	_btn_ok.pressed.disconnect(_on_ok)
	_btn_ok.pressed.connect(_finish)


func _finish() -> void:
	if _applied:
		return
	_applied = true
	game.apply_merge(_picks, _res)
	game.close_modal()
