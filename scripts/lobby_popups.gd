extends RefCounted
## 로비 팝업 3종: 던전 목록 / 프로필 / 오늘의 할 일. host 는 팝업을 붙일 Control(로비), save 는 /root/Save(없으면 null).

const K = preload("res://scripts/ui_kit.gd")
const C := "res://assets/screens/common/"


## 던전 난이도 표시용 문자열 (엑셀 '던전' 시트의 난이도 배수 열이 있으면 보여 줌)
static func difficulty_text(def: Dictionary) -> String:
	for k in ["difficulty", "hp_mult", "mult"]:
		if def.has(k):
			return "난이도 x%s" % str(def[k])
	return ""


static func dungeon_state(save: Node, n: int) -> String:
	if save == null:
		return "open" if n == 1 else "locked"
	if save.dungeon_cleared(n):
		return "clear"
	return "open" if save.dungeon_unlocked(n) else "locked"


## 던전 10개 목록. 잠기지 않은 줄을 누르면 on_pick(n) 호출 후 닫힘.
static func dungeon_list(host: Control, save: Node, on_pick: Callable) -> void:
	var layer := K.popup(host, Rect2(40, 110, 640, 1020), "던전 선택")
	var count: int = 10 if save == null else int(save.dungeon_count())
	var sel: int = 1 if save == null else int(save.selected_dungeon)
	var row_h := minf(88.0, 870.0 / count)
	for n in range(1, count + 1):
		var y := 205.0 + (n - 1) * (row_h + 4.0)
		var st := dungeon_state(save, n)
		var is_sel := n == sel
		layer.add_child(K.panel(Rect2(70, y, 580, row_h), K.ROW_FILL if st != "locked" else Color(0.1, 0.08, 0.16),
				K.GOLD if is_sel else (K.ROW_LINE if st != "locked" else Color(0.22, 0.2, 0.3)), 14, 4 if is_sel else 2))
		layer.add_child(K.label(str(n), 34, Vector2(80, y), Vector2(70, row_h), K.GOLD if st != "locked" else K.DIM))
		var nm: String = "던전 %d" % n if save == null else str(save.dungeon_name(n))
		var def: Dictionary = {} if save == null else save.dungeon_def(n)
		var ipath := "res://assets/stage/dungeon/%s%s.png" % [str(def.get("icon", "")), "_locked" if st == "locked" else ""]
		var name_x := 155.0
		if str(def.get("icon", "")) != "" and ResourceLoader.exists(ipath):
			layer.add_child(K.icon(ipath, Vector2(150, y + (row_h - 58.0) * 0.5), 0.6))
			name_x = 218.0
		layer.add_child(K.label(nm, 32, Vector2(name_x, y + 4), Vector2(270, row_h * 0.6), K.WHITE if st != "locked" else K.DIM,
				HORIZONTAL_ALIGNMENT_LEFT))
		var sub := ""
		if st == "locked":
			var need: String = "" if save == null else str(save.dungeon_unlock_name(n))
			sub = "%s 던전을 먼저 클리어해요" % need if need != "" else "아직 열리지 않았어요"
		else:
			var bw: int = 0 if save == null else int(save.dungeon_best_wave(n))
			sub = "최고 웨이브 %d" % bw if bw > 0 else "아직 기록이 없어요"
			var rec: int = 0 if save == null else int(save.dungeon_rec_card_lv(n))
			if rec > 0:
				sub += "  ·  권장 Lv %d" % rec
		layer.add_child(K.label(sub, 19, Vector2(name_x + 2, y + row_h * 0.55), Vector2(330, row_h * 0.4), K.DIM,
				HORIZONTAL_ALIGNMENT_LEFT, false))
		var tag := {"clear": "클리어", "open": "도전 가능", "locked": ""}[st] as String
		var tcol := {"clear": K.GREEN, "open": K.GOLD, "locked": K.DIM}[st] as Color
		if st == "locked":
			layer.add_child(K.icon(C + "icon_lock.png", Vector2(590, y + row_h * 0.5 - 24), 1.5))
		else:
			layer.add_child(K.label(tag, 24, Vector2(470, y), Vector2(170, row_h), tcol, HORIZONTAL_ALIGNMENT_RIGHT, false))
		if st != "locked":
			layer.add_child(K.hit_area(Rect2(70, y, 580, row_h), func():
				Sfx.play("button")
				on_pick.call(n)
				(layer.get_meta("close") as Callable).call()))
		else:
			layer.add_child(K.hit_area(Rect2(70, y, 580, row_h), func():
				K.toast(layer, "먼저 앞 던전을 클리어하세요", 560.0, Color(1, 0.7, 0.7))))


## 프로필: 닉네임·칭호·계정 레벨·기록·잠만보 연동 상태
static func profile(host: Control, save: Node, link: Node, on_open_link: Callable) -> void:
	var layer := K.popup(host, Rect2(50, 190, 620, 840), "프로필")
	var nick := "게스트"
	var logged := false
	if link != null and link.has_method("logged_in") and link.logged_in():
		logged = true
		var nn := str(link.nickname())
		if nn != "":
			nick = nn
	layer.add_child(K.label(nick, 48, Vector2(50, 280), Vector2(620, 72), K.WHITE))
	var title: String = "보세포" if save == null else str(save.title())
	layer.add_child(K.panel(Rect2(235, 360, 250, 52), Color(0.25, 0.18, 0.08), K.GOLD, 26, 3))
	layer.add_child(K.label("칭호  " + title, 24, Vector2(235, 360), Vector2(250, 52), K.GOLD, HORIZONTAL_ALIGNMENT_CENTER, false))
	var lv: int = 1 if save == null else int(save.account_level())
	layer.add_child(K.label("계정 Lv %d" % lv, 30, Vector2(50, 425), Vector2(620, 50), K.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false))
	var total: int = 10 if save == null else int(save.dungeon_count())
	var rows := [
		["총 판수", "0" if save == null else str(save.runs)],
		["승리", "0" if save == null else str(save.wins)],
		["최고 웨이브", "0" if save == null else str(save.best_wave())],
		["클리어한 던전", "%d / %d" % [0 if save == null else int(save.cleared_count()), total]],
		["처치한 적", "0" if save == null else str(save.total_kills)],
	]
	for i in rows.size():
		var y := 490.0 + i * 62.0
		layer.add_child(K.panel(Rect2(80, y, 560, 54), K.ROW_FILL, K.ROW_LINE, 12, 2))
		layer.add_child(K.label(rows[i][0], 24, Vector2(100, y), Vector2(260, 54), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		layer.add_child(K.label(rows[i][1], 26, Vector2(360, y), Vector2(260, 54), K.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, false))
	var msg := "잠만보 계정으로 연결됨" if logged else "게스트 · 잠만보에서 로그인하면 랭킹에 참여해요"
	layer.add_child(K.label(msg, 21, Vector2(70, 812), Vector2(580, 40), K.GREEN if logged else K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
	layer.add_child(K.button("res://assets/td/ui/btn_blue_big.png", "잠만보 모임 보러가기", Rect2(150, 870, 420, 96), on_open_link, 26))


## 오늘의 할 일: 진행 · 받기. on_changed() 는 받은 뒤(로비 배지 갱신용).
static func quests(host: Control, save: Node, on_changed: Callable) -> void:
	var layer := K.popup(host, Rect2(50, 330, 620, 600), "오늘의 할 일")
	if save == null:
		layer.add_child(K.label("저장 기능을 쓸 수 없어요", 26, Vector2(50, 600), Vector2(620, 60), K.DIM))
		return
	var list: Array = save.daily_quests()
	for i in list.size():
		var q: Dictionary = list[i]
		var y := 430.0 + i * 150.0
		layer.add_child(K.panel(Rect2(80, y, 560, 130), K.ROW_FILL, K.ROW_LINE, 14, 2))
		layer.add_child(K.label(str(q["text"]), 28, Vector2(100, y + 8), Vector2(340, 50), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		layer.add_child(K.label("%d / %d" % [q["progress"], q["need"]], 24, Vector2(100, y + 62), Vector2(160, 50), K.GOLD,
				HORIZONTAL_ALIGNMENT_LEFT, false))
		layer.add_child(K.icon("res://assets/screens/result/icon_card_shard.png", Vector2(250, y + 72), 1.3))
		layer.add_child(K.label("+%d" % q["reward"], 24, Vector2(292, y + 62), Vector2(100, 50), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		var label_text := "완료" if q["claimed"] else "받기"
		var b := K.button("res://assets/td/ui/btn_green_big.png", label_text, Rect2(470, y + 25, 150, 80), func():
			var n: int = save.claim_quest(str(q["id"]))
			if n > 0:
				Sfx.play("coin")
				on_changed.call()
				(layer.get_meta("close") as Callable).call()
				K.toast(host, "카드 재료 +%d" % n, 560.0), 28)
		K.set_enabled(b, bool(q["done"]) and not bool(q["claimed"]))
		layer.add_child(b)
	layer.add_child(K.label("매일 새로 시작해요 (무료 · 광고 없음)", 20, Vector2(50, 880), Vector2(620, 36), K.DIM,
			HORIZONTAL_ALIGNMENT_CENTER, false))
