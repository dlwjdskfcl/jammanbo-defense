extends Control
## 랭킹 화면 (로비의 랭킹 탭). 데이터는 JmbLink(잠만보 연동, autoload) 에서 옵니다 — 항상 null 안전하게 사용.
## 계약: JmbLink.request_rank(scope) + signal rank_loaded(data)
##   data = {"scope": "week"|"all"|"season", "mine": {rank,nick,wave,score}, "top": [{rank,nick,wave,score}, ...]}
## show_data(data) / show_state("loading"|"fail"|"empty") 로 화면만 따로 검증할 수도 있습니다.

signal back_requested

const K = preload("res://scripts/ui_kit.gd")
const C := "res://assets/screens/common/"
const SCOPES := [["week", "이번 주"], ["all", "전체"], ["season", "시즌"]]
const TIMEOUT := 8.0

var link: Node
var scope: String = "week"
var layer: Control
var body: Control
var state: String = "loading"
var data: Dictionary = {}
var _req_id: int = 0


func _ready() -> void:
	size = Vector2(720, 1280)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	link = get_node_or_null("/root/JmbLink")
	if link != null and link.has_signal("rank_loaded"):
		link.rank_loaded.connect(_on_loaded)
	_build()
	request()


func request() -> void:
	state = "loading"
	_req_id += 1
	_render()
	if link == null or not link.has_method("request_rank"):
		show_state("fail")
		return
	link.request_rank(scope)
	var id := _req_id
	get_tree().create_timer(TIMEOUT).timeout.connect(func():
		if is_instance_valid(self) and id == _req_id and state == "loading":
			show_state("fail"))


func _on_loaded(d: Dictionary) -> void:
	if str(d.get("scope", scope)) != scope:
		return
	show_data(d)


func show_data(d: Dictionary) -> void:
	data = d
	state = "ready" if (d.get("top", []) as Array).size() > 0 or not (d.get("mine", {}) as Dictionary).is_empty() else "empty"
	_render()


func show_state(s: String) -> void:
	state = s
	_render()


func _build() -> void:
	layer = Control.new()
	layer.size = Vector2(720, 1280)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	K.menu_bg(layer)
	K.header(layer, "랭킹", func():
		Sfx.play("button")
		back_requested.emit())
	var w := (660.0 - 24.0) / 3.0
	for i in 3:
		var on: bool = SCOPES[i][0] == scope
		layer.add_child(K.button(C + ("tab_on.png" if on else "tab_off.png"), SCOPES[i][1],
				Rect2(30 + i * (w + 12), 128, w, 80), _set_scope.bind(SCOPES[i][0]), 28))
	body = Control.new()
	body.size = Vector2(720, 1280)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(body)


func _set_scope(s: String) -> void:
	Sfx.play("button")
	if s == scope:
		return
	scope = s
	for c in layer.get_children():
		c.queue_free()
	_build()
	request()


func _render() -> void:
	if body == null:
		return
	for c in body.get_children():
		c.queue_free()
	match state:
		"loading":
			body.add_child(K.label("불러오는 중...", 32, Vector2(0, 560), Vector2(720, 60), K.DIM))
		"fail":
			body.add_child(K.label("랭킹을 불러오지 못했어요", 30, Vector2(0, 500), Vector2(720, 60), Color(1, 0.7, 0.7)))
			body.add_child(K.label("잠시 뒤에 다시 시도해 주세요", 22, Vector2(0, 560), Vector2(720, 40), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
			body.add_child(K.button("res://assets/td/ui/btn_gray_big.png", "다시 시도", Rect2(220, 630, 280, 90), func():
				Sfx.play("button")
				request(), 30))
		"empty":
			body.add_child(K.label("아직 기록이 없어요", 32, Vector2(0, 520), Vector2(720, 60), K.WHITE))
			body.add_child(K.label("한 판 이기고 첫 기록을 남겨 보세요!", 22, Vector2(0, 585), Vector2(720, 40), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
		"ready":
			_render_list()


func _render_list() -> void:
	var top: Array = data.get("top", [])
	var rows := mini(top.size(), 10)
	for i in rows:
		var e: Dictionary = top[i]
		_row(body, 226.0 + i * 70.0, e, false)
	var mine: Dictionary = data.get("mine", {})
	if not mine.is_empty():
		body.add_child(K.label("내 순위", 24, Vector2(60, 936), Vector2(200, 36), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
		_row(body, 978.0, mine, true)
	else:
		body.add_child(K.label("기록을 남기면 내 순위가 여기에 나와요", 22, Vector2(0, 980), Vector2(720, 40), K.DIM,
				HORIZONTAL_ALIGNMENT_CENTER, false))


func _row(parent: Control, y: float, e: Dictionary, mine: bool) -> void:
	var rank := int(e.get("rank", 0))
	var line := K.GOLD if mine else K.ROW_LINE
	parent.add_child(K.panel(Rect2(40, y, 640, 62), Color(0.2, 0.15, 0.1) if mine else K.ROW_FILL, line, 12, 3 if mine else 2))
	var col: Color = [K.GOLD, Color(0.8, 0.84, 0.9), Color(0.9, 0.6, 0.35)][rank - 1] if rank >= 1 and rank <= 3 else K.WHITE
	parent.add_child(K.label(str(rank), 30, Vector2(48, y), Vector2(80, 62), col))
	parent.add_child(K.label(str(e.get("nick", "?")), 26, Vector2(135, y), Vector2(290, 62), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	parent.add_child(K.label("웨이브 %d" % int(e.get("wave", 0)), 23, Vector2(420, y), Vector2(130, 62), K.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, false))
	parent.add_child(K.label(str(int(e.get("score", 0))), 22, Vector2(550, y), Vector2(120, 62), K.DIM, HORIZONTAL_ALIGNMENT_RIGHT, false))
