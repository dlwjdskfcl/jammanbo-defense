extends Control
## 첫 실행 튜토리얼(소환 → 합성 → 보스 3단계). 새 그림 없이 기존 에셋 + 글자로 만듭니다.
## 사용: var t = preload("res://scripts/tutorial.gd").new(); parent.add_child(t); t.finished.connect(...)
## 끝까지 보거나 건너뛰면 finished 를 내보내고 스스로 사라집니다. (Save.tutorial_done 저장은 쓰는 쪽에서)

signal finished(skipped: bool)

const K = preload("res://scripts/ui_kit.gd")
const PANEL := Rect2(50, 170, 620, 940)
const IMAGES := ["tutorial_summon", "tutorial_merge", "tutorial_boss"]
var step := 0
var holder: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = Vector2(720, 1280)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	Sfx.play("popup_open")
	add_child(K.dim_layer(Color(0, 0, 0, 0.78)))
	add_child(K.panel(PANEL, Color(0.13, 0.1, 0.22), Color(0.95, 0.72, 0.2), 20, 4))
	holder = Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_show_step()


func _steps() -> Array:
	var cost := int(Data.rule("summon_cost", 20))
	var lim := int(Data.rule("field_limit", 60))
	var lucky := int(round(float(Data.rule("lucky_merge_chance", 0.05)) * 100.0))
	var pity := int(Data.rule("pity_limit", 10))
	var bt := int(Data.rule("boss_time_limit", 60))
	var bf := int(Data.rule("boss_fast_sec", 30))
	var bb := int(Data.rule("boss_fast_bonus", 100))
	var every := int(Data.rule("boss_every", 10))
	return [
		{"title": "1. 랜덤 소환",
		"body": "코인 %d 으로 아르·마니·여름 중 한 명을 랜덤으로 소환해요.\n누가 나올지는 몰라요!\n\n적이 필드에 %d마리를 넘으면 패배예요." % [cost, lim]},
		{"title": "2. 합성",
		"body": "같은 등급 3마리를 합치면 한 단계 위 랜덤 캐릭터가 돼요.\n\n가끔(%d%%) 두 단계를 뛰는 대박!\n%d번 연속 안 나오면 다음은 확정(천장)이에요." % [lucky, pity]},
		{"title": "3. 보스",
		"body": "%d웨이브마다 보스가 나와요.\n제한시간 %d초 안에 못 잡으면 패배!\n%d초 안에 잡으면 보너스 코인 %d.\n\n지면 카드 재료를 얻어요. 로비의 '카드'에서 캐릭터를 키우세요." % [every, bt, bf, bb]},
	]


func _art(i: int) -> void:
	var path := "res://assets/stage/tutorial/%s.png" % IMAGES[i]
	if not ResourceLoader.exists(path):
		return
	var r := K.icon(path, Vector2(90, 255), 0.9)
	holder.add_child(r)


func _show_step() -> void:
	for c in holder.get_children():
		c.queue_free()
	var st: Dictionary = _steps()[step]
	holder.add_child(K.label(st["title"], 44, Vector2(PANEL.position.x, 185), Vector2(PANEL.size.x, 64), K.GOLD))
	_art(step)
	var body := K.label(st["body"], 27, Vector2(PANEL.position.x + 40, 645), Vector2(PANEL.size.x - 80, 250), K.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, false)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	holder.add_child(body)
	for n in 3:
		holder.add_child(K.icon("res://assets/screens/common/%s.png" % ("pip_on" if n == step else "pip_off"),
				Vector2(335 + (n - 1) * 40, 915), 1.0))
	var last := step == 2
	holder.add_child(K.button("res://assets/td/ui/btn_gray_big.png", "건너뛰기", Rect2(80, 970, 250, 100), _skip, 28))
	holder.add_child(K.button("res://assets/td/ui/btn_green_big.png", "시작!" if last else "다음", Rect2(390, 970, 250, 100), _next, 33))


func _next() -> void:
	Sfx.play("button")
	if step >= 2:
		_close(false)
	else:
		step += 1
		_show_step()


func _skip() -> void:
	Sfx.play("button")
	_close(true)


func _close(skipped: bool) -> void:
	Sfx.play("popup_close")
	finished.emit(skipped)
	queue_free()
