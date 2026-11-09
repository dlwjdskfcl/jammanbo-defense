extends Control
## 모임 이벤트 카드 3택1 (웨이브 사이). 시간 정지 상태에서 뜨고, 제한 시간이 지나면 첫 장 자동 선택.
## 사용: var m = EventsScript.new(); m.setup(game, wave, cards, sec); m.picked.connect(fn(ev, arg)); game.open_modal(m)
## 주사위 도박 카드는 선택 후 판돈(20/50/100/안 걸기)을 한 번 더 고릅니다(arg = 판돈).

signal picked(ev: Dictionary, arg: int)

const U = preload("res://scripts/util.gd")
const INK := Color(0.23, 0.14, 0.19)
const FLAVOR := {
	"ev_start_roulette": "누가 먼저 할까? 룰렛 돌려~",
	"ev_hourglass": "잠깐, 모래시계 뒤집자.",
	"ev_dice_bet": "한 판 걸어볼까? 안 걸어도 돼.",
	"ev_host_call": "벙주 왔다! 자리 하나 내줘.",
	"ev_noshow": "아 또 한 명 안 왔네…",
	"ev_late": "지각자 온대. 조금만 기다려.",
	"ev_snack": "간식 먹고 하자!",
	"ev_rule_explain": "룰 설명 길어진다…",
	"ev_call": "이번엔 크게 간다. 콜!",
	"ev_tourney": "미니 대회 열자!",
	"ev_escape": "문이 세 개야. 골라봐.",
	"ev_raffle": "응모권 뽑기~",
}
const ICONS := {"ev_start_roulette": "icon_roulette", "ev_hourglass": "icon_hourglass", "ev_dice_bet": "icon_dice",
	"ev_host_call": "icon_host", "ev_noshow": "icon_noshow", "ev_late": "icon_late", "ev_snack": "icon_snack",
	"ev_rule_explain": "icon_rules", "ev_call": "icon_call", "ev_tourney": "icon_tournament", "ev_escape": "icon_escape",
	"ev_raffle": "icon_lottery"}
const CARD_ART := {"좋음": "card_good", "도박": "card_neutral", "중립": "card_neutral", "나쁨": "card_bad"}
const KIND_COLOR := {"좋음": Color(0.5, 1, 0.6), "도박": Color(1, 0.8, 0.35), "중립": Color(0.8, 0.85, 1), "나쁨": Color(1, 0.5, 0.5)}

var game
var wave: int = 0
var cards: Array = []
var left: float = 8.0
var _lbl_time: Label
var _done: bool = false
var _stage: int = 0
var _chosen: Dictionary = {}


func setup(game_ref, w: int, card_list: Array, sec: float) -> void:
	game = game_ref
	wave = w
	cards = card_list
	left = sec


func _ready() -> void:
	size = Vector2(720, 1280)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.size = Vector2(720, 1280)
	add_child(dim)
	Sfx.play("event_pop")
	_build_cards()


func _label(text: String, fs: int, pos: Vector2, box: Vector2, color: Color = Color.WHITE, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = box
	l.custom_minimum_size = box
	l.clip_text = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", max(2, int(fs / 7)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(l)
	l.size = box
	return l


func _clear_content() -> void:
	for c in get_children():
		if c is ColorRect:
			continue
		c.queue_free()


func _build_cards() -> void:
	_clear_content()
	_label("모임 이벤트!", 54, Vector2(0, 190), Vector2(720, 70), Color(1, 0.85, 0.3))
	_label("웨이브 %d 시작 전 — 카드 한 장 고르기" % wave, 24, Vector2(0, 262), Vector2(720, 36), Color(0.9, 0.9, 1))
	_lbl_time = _label("", 30, Vector2(0, 300), Vector2(720, 40), Color(1, 0.9, 0.6))
	var n := cards.size()
	var cw := 210.0
	var gap := 16.0
	var x0 := (720.0 - (n * cw + (n - 1) * gap)) / 2.0
	for i in n:
		var ev: Dictionary = cards[i]
		var kind := str(ev.get("kind", "중립"))
		var col: Color = KIND_COLOR.get(kind, Color.WHITE)
		var p := Panel.new()
		p.position = Vector2(x0 + i * (cw + gap), 360)
		p.size = Vector2(cw, 440)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", game._box(Color(0.16, 0.13, 0.26, 0.98), col))
		add_child(p)
		var art := str(CARD_ART.get(kind, "card_neutral"))
		var bg := TextureRect.new()      # 카드 그림(160x200)을 1.3배로: 위 막대=종류, 동그라미=아이콘, 줄=이름
		bg.texture = U.tex("res://assets/stage/events/%s.png" % art)
		bg.scale = Vector2(1.31, 1.31)
		bg.position = Vector2(0, 0)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(bg)
		var iname := str(ICONS.get(str(ev["id"]), ""))
		if iname != "" and ResourceLoader.exists("res://assets/stage/events/%s.png" % iname):
			var ic := TextureRect.new()
			ic.texture = U.tex("res://assets/stage/events/%s.png" % iname)
			ic.scale = Vector2(1.7, 1.7)
			ic.position = Vector2(105 - 41, 92 - 41)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(ic)
		_label(kind, 20, Vector2(0, 4), Vector2(cw, 30), Color.WHITE, p)
		var nl := _label(str(ev["name"]), 22, Vector2(14, 164), Vector2(cw - 28, 80), Color(0.25, 0.16, 0.2), p)
		nl.add_theme_constant_override("outline_size", 0)
		_label(str(FLAVOR.get(str(ev["id"]), "")), 19, Vector2(10, 272), Vector2(cw - 20, 60), Color(1, 0.9, 0.6), p)
		_label(str(ev.get("desc", "")), 16, Vector2(10, 336), Vector2(cw - 20, 96), Color(0.85, 0.85, 0.95), p)
		var b := Button.new()
		b.flat = true
		b.position = p.position
		b.size = p.size
		b.pressed.connect(_choose.bind(ev))
		add_child(b)


func _choose(ev: Dictionary) -> void:
	if _done:
		return
	Sfx.play("button")
	if str(ev["id"]) == "ev_dice_bet":
		_chosen = ev
		_stage = 1
		_build_bet(ev)
		return
	_done = true
	picked.emit(ev, 0)


func _build_bet(ev: Dictionary) -> void:
	_clear_content()
	_label("주사위 도박", 54, Vector2(0, 260), Vector2(720, 70), Color(1, 0.85, 0.3))
	_label("1~2 잃음 / 3~4 본전 / 5~6 두 배\
코인 %d 보유" % game.coins, 26, Vector2(0, 340), Vector2(720, 90), Color(0.9, 0.9, 1))
	var bets: Array = [int(ev["v1"]), int(ev["v2"]), int(ev["v3"]), 0]
	var y := 470.0
	for bet in bets:
		var txt := "%d 코인 걸기" % bet if bet > 0 else "안 걸기"
		var tex := "res://assets/td/ui/btn_green_big.png" if bet > 0 else "res://assets/td/ui/btn_gray_big.png"
		var ok: bool = bet <= game.coins
		var btn: TextureButton = game._button(tex, txt, Vector2(210, y), Vector2(300, 90), _bet.bind(bet), 30)
		btn.disabled = not ok
		btn.modulate = Color.WHITE if ok else Color(0.5, 0.5, 0.5)
		add_child(btn)
		y += 110.0


func _bet(bet: int) -> void:
	if _done:
		return
	_done = true
	if bet > 0:
		Sfx.play("dice_roll")
	picked.emit(_chosen, bet)


func _process(delta: float) -> void:
	if _done or _stage != 0:
		return
	left -= delta / max(Engine.time_scale, 0.1)
	if _lbl_time != null:
		_lbl_time.text = "남은 시간 %d초 (시간 초과 시 첫 장)" % int(ceil(max(left, 0.0)))
	if left <= 0.0 and not cards.is_empty():
		_done = true
		picked.emit(cards[0], 0)
