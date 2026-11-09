extends Control
## 로비: 던전 선택 + 게임 시작(가장 크게) · 프로필 · 모임 한마디 · 캐릭터 연출 · 오늘의 할 일 · 하단 탭.
## 검증용 인자(-- 뒤): --autoplay 또는 --shot=경로 → 바로 게임 시작(봇),
##   --lobby-shot=경로.png [--page=home|cards|settings|odds|tutorial|daily|dungeons|profile|quests|ranking|ranking_empty|ranking_fail] [--seed]
##   → 해당 화면을 그려서 저장하고 종료.
## 잠만보 연동(JmbLink autoload)은 있으면 쓰고 없으면 게스트로 동작합니다.

const K = preload("res://scripts/ui_kit.gd")
const U = preload("res://scripts/util.gd")
const LD = preload("res://scripts/lobby_data.gd")
const Popups = preload("res://scripts/lobby_popups.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const CardsScene = preload("res://scenes/cards.tscn")
const SettingsScene = preload("res://scenes/settings_panel.tscn")
const RankingScript = preload("res://scripts/ranking.gd")
const C := "res://assets/screens/common/"
const NAV_Y := 1160.0
const NAV_ITEMS := [["상점", "icon_shop.png", "shop"], ["카드", "icon_card.png", "cards"], ["전투", "icon_play.png", "home"],
		["랭킹", "icon_rank.png", "ranking"], ["설정", "icon_gear.png", "settings"]]

var save: Node
var link: Node
var page: String = "home"
var home: Control
var cards: Control
var ranking: Control
var settings: Control = null
var nav_layer: Control
var lbl_nick: Label
var lbl_title: Label
var lbl_level: Label
var lbl_shards: Label
var lbl_motto: Label
var dungeon_box: Control
var btn_start: TextureButton
var quest_btn_label: Label
var quest_badge: TextureRect
var char_sprites: Dictionary = {}
var char_bubbles: Dictionary = {}
var char_labels: Dictionary = {}
var char_ids: Array = []
var lobby_shot: String = ""
var start_page: String = "home"
var motto_i: int = 0
var _view: int = 0   # 화면에 보이는 던전(0 이면 선택된 던전)
var _bubble_t: float = 2.0
var _motto_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	size = Vector2(720, 1280)
	_rng.randomize()
	save = get_node_or_null("/root/Save")
	link = get_node_or_null("/root/JmbLink")
	var args := OS.get_cmdline_user_args()
	var seed_state := false
	var bot := "--autoplay" in args
	for a in args:
		if a.begins_with("--lobby-shot="):
			lobby_shot = a.substr(13)
		elif a.begins_with("--page="):
			start_page = a.substr(7)
		elif a == "--seed":
			seed_state = true
		elif a.begins_with("--shot="):
			bot = true
	if bot:   # 봇/스크린샷: 바로 게임
		get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")
		return
	if lobby_shot != "" and save:
		save.persist = false
		if seed_state:
			save.shards = 60
			save._levels = {"arr": 6, "mani": 3}
			save._best_wave = 23
			save.runs = 9
			save.wins = 2
			save.total_kills = 412
			save._dungeons = {"d01": {"best_wave": 40, "cleared": true}, "d02": {"best_wave": 31, "cleared": true},
					"d03": {"best_wave": 23, "cleared": false}}
			save.selected_dungeon = 3
			save._quest = {"date": save.today(), "runs": 1, "wave": 23, "claimed": []}
	mouse_filter = Control.MOUSE_FILTER_STOP
	char_ids = Data.d.get("characters", {}).keys()
	_build_home()
	_build_nav()
	if save:
		save.changed.connect(_refresh)
	if link != null and link.has_signal("state_changed"):
		link.state_changed.connect(_refresh)
	_refresh()
	Sfx.play_bgm("bgm_menu")
	_show_page("home")
	if lobby_shot != "":
		_shot_setup()
	else:
		_first_run_flow()


func _process(delta: float) -> void:
	if home == null or not home.visible:
		return
	_bubble_t -= delta
	if _bubble_t <= 0.0:
		_bubble_t = _rng.randf_range(2.5, 5.0)
		if not char_ids.is_empty():
			var cid: String = char_ids[_rng.randi() % char_ids.size()]
			_say(cid, _pick(LD.BUBBLES.get(cid, LD.GENERIC_BUBBLES)), 1.8)
	_motto_t += delta
	if _motto_t >= 7.0:
		_next_motto()


func _pick(list: Array) -> String:
	return str(list[_rng.randi() % list.size()])


# ------------------------------------------------------------------ 홈 화면
func _build_home() -> void:
	home = Control.new()
	home.size = Vector2(720, NAV_Y)
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(home)
	var bgd := Control.new()
	bgd.size = Vector2(720, 1280)
	bgd.mouse_filter = Control.MOUSE_FILTER_STOP
	bgd.draw.connect(_draw_bg.bind(bgd))
	home.add_child(bgd)

	# 상단 바: 프로필 / 카드 재료 / 설정
	home.add_child(K.panel(Rect2(16, 14, 330, 72), Color(0.13, 0.1, 0.22), Color(0.35, 0.3, 0.5), 14, 3))
	lbl_nick = K.label("", 25, Vector2(30, 16), Vector2(210, 38), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	home.add_child(lbl_nick)
	lbl_title = K.label("", 20, Vector2(30, 50), Vector2(210, 32), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT, false)
	home.add_child(lbl_title)
	lbl_level = K.label("", 24, Vector2(236, 14), Vector2(100, 72), K.GOLD, HORIZONTAL_ALIGNMENT_CENTER, false)
	home.add_child(lbl_level)
	home.add_child(K.hit_area(Rect2(16, 14, 330, 72), _open_profile))
	home.add_child(K.panel(Rect2(360, 14, 230, 72), Color(0.13, 0.1, 0.22), Color(0.35, 0.3, 0.5), 14, 3))
	home.add_child(K.icon("res://assets/screens/result/icon_card_shard.png", Vector2(372, 32), 1.5))
	lbl_shards = K.label("", 28, Vector2(424, 14), Vector2(156, 72), K.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	home.add_child(lbl_shards)
	home.add_child(K.icon(C + "icon_gear.png", Vector2(630, 28), 2.0))
	home.add_child(K.hit_area(Rect2(600, 10, 116, 80), _open_settings))

	# 로고
	var logo := TextureRect.new()
	logo.texture = U.tex("res://assets/title/logo_text.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.size = Vector2(560, 168)
	logo.position = Vector2(80, 100)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(logo)

	# 오늘의 모임 한마디
	home.add_child(K.panel(Rect2(40, 282, 640, 62), Color(0.12, 0.09, 0.2, 0.9), Color(0.55, 0.45, 0.75), 31, 3))
	lbl_motto = K.label(LD.MOTTOS[0], 22, Vector2(70, 282), Vector2(580, 62), K.WHITE, HORIZONTAL_ALIGNMENT_CENTER, false)
	home.add_child(lbl_motto)
	home.add_child(K.hit_area(Rect2(40, 282, 640, 62), _next_motto))

	# 캐릭터 연출
	var n := maxi(char_ids.size(), 1)
	for i in char_ids.size():
		var cid: String = char_ids[i]
		var cx := 720.0 * (i + 0.5) / n
		var sp := AnimatedSprite2D.new()
		sp.sprite_frames = U.unit_frames(cid, 3)
		sp.scale = Vector2(2.4, 2.4)
		sp.position = Vector2(cx, 500)
		sp.play("idle")
		sp.frame = i % 4
		home.add_child(sp)
		char_sprites[cid] = sp
		var bub := K.panel(Rect2(cx - 100, 372, 200, 50), Color(1, 1, 1, 0.96), Color(0.23, 0.14, 0.19), 16, 3)
		bub.modulate.a = 0.0
		bub.add_child(K.label("", 22, Vector2.ZERO, Vector2(200, 50), Color(0.2, 0.14, 0.19), HORIZONTAL_ALIGNMENT_CENTER, false))
		home.add_child(bub)
		char_bubbles[cid] = bub
		var lv := K.label("", 22, Vector2(cx - 90, 584), Vector2(180, 34), K.GOLD)
		home.add_child(lv)
		char_labels[cid] = lv
		home.add_child(K.hit_area(Rect2(cx - 100, 410, 200, 200), _tap_char.bind(cid)))

	# 던전 카드 (가장 중요)
	dungeon_box = Control.new()
	dungeon_box.size = Vector2(720, 290)
	dungeon_box.position = Vector2(0, 618)
	dungeon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(dungeon_box)
	btn_start = K.button("res://assets/td/ui/btn_green_big.png", "게임 시작", Rect2(130, 912, 460, 130), _start_game, 52)
	home.add_child(btn_start)

	# 아래 줄: 오늘의 할 일 / 잠만보 모임
	home.add_child(K.panel(Rect2(30, 1058, 330, 88), Color(0.13, 0.1, 0.22), K.ROW_LINE, 16, 3))
	home.add_child(K.icon(C + "icon_mission.png", Vector2(46, 1082), 1.9))
	quest_btn_label = K.label("", 22, Vector2(112, 1060), Vector2(240, 84), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
	home.add_child(quest_btn_label)
	quest_badge = K.icon(C + "icon_dot.png", Vector2(318, 1064), 1.0)
	quest_badge.modulate = Color(1, 0.3, 0.35)
	home.add_child(quest_badge)
	home.add_child(K.hit_area(Rect2(30, 1060, 330, 84), _open_quests))
	home.add_child(K.panel(Rect2(375, 1060, 315, 84), Color(0.13, 0.1, 0.22), K.ROW_LINE, 16, 3))
	home.add_child(K.icon(C + "icon_home.png", Vector2(391, 1082), 1.9))
	home.add_child(K.label("잠만보 모임\n보러가기", 22, Vector2(455, 1060), Vector2(230, 84), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
	home.add_child(K.hit_area(Rect2(375, 1060, 315, 84), _open_jmb))


func _draw_bg(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, 720, 460), Color(0.56, 0.82, 1.0))
	c.draw_rect(Rect2(0, 250, 720, 210), Color(0.7, 0.88, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var g: Array = [U.tex("res://assets/td/tiles/grass_0.png"), U.tex("res://assets/td/tiles/grass_1.png"),
			U.tex("res://assets/td/tiles/grass_2.png")]
	var y := 448.0
	while y < NAV_Y + 64.0:
		var x := 0.0
		while x < 720.0:
			c.draw_texture(g[rng.randi() % 3], Vector2(x, y))
			x += 64.0
		y += 64.0
	var path: Texture2D = U.tex("res://assets/td/tiles/path_h.png")
	var px := 0.0
	while px < 720.0:
		c.draw_texture(path, Vector2(px, 560))
		px += 64.0
	c.draw_texture(U.tex("res://assets/td/tiles/prop_tree.png"), Vector2(14, 372))
	c.draw_texture(U.tex("res://assets/td/tiles/prop_bush.png"), Vector2(640, 396))
	c.draw_texture(U.tex("res://assets/td/tiles/prop_flower.png"), Vector2(678, 440))


# ------------------------------------------------------------------ 던전 카드
func _shown() -> int:
	if _view > 0:
		return _view
	return 1 if save == null else int(save.selected_dungeon)


func _count() -> int:
	return 10 if save == null else int(save.dungeon_count())


func _icon_path(def: Dictionary, locked: bool) -> String:
	var base := str(def.get("icon", ""))
	if base == "":
		return ""
	var path := "res://assets/stage/dungeon/%s%s.png" % [base, "_locked" if locked else ""]
	return path if ResourceLoader.exists(path) else ""


func _draw_dungeon() -> void:
	for c in dungeon_box.get_children():
		c.queue_free()
	var n := _shown()
	var count := _count()
	var st := Popups.dungeon_state(save, n)
	var locked := st == "locked"
	var col := K.GOLD if st == "open" else (K.GREEN if st == "clear" else K.ROW_LINE)
	dungeon_box.add_child(K.panel(Rect2(30, 0, 660, 282), Color(0.11, 0.085, 0.19, 0.95), col, 20, 4))
	var def: Dictionary = {} if save == null else save.dungeon_def(n)
	var nm: String = "던전 %d" % n if save == null else str(save.dungeon_name(n))
	dungeon_box.add_child(K.label("던전 %d / %d" % [n, count], 21, Vector2(130, 8), Vector2(460, 30), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
	var icon_path := _icon_path(def, locked)
	var name_x := 130.0
	var name_w := 460.0
	if icon_path != "":
		dungeon_box.add_child(K.icon(icon_path, Vector2(134, 38), 0.8))
		name_x = 224.0
		name_w = 370.0
	dungeon_box.add_child(K.label(nm, 54, Vector2(name_x, 36), Vector2(name_w, 76), K.DIM if locked else K.GOLD))
	if locked and icon_path == "":
		dungeon_box.add_child(K.icon(C + "icon_lock.png", Vector2(560, 56), 2.0))
	var concept := str(def.get("concept", ""))
	if concept != "":
		var cl := K.label(concept, 18, Vector2(128, 112), Vector2(464, 54), Color(0.85, 0.82, 0.95), HORIZONTAL_ALIGNMENT_CENTER, false)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.max_lines_visible = 2
		cl.size = Vector2(464, 54)
		dungeon_box.add_child(cl)
	var line := ""
	var line_col := K.WHITE
	if locked:
		var need: String = "" if save == null else str(save.dungeon_unlock_name(n))
		line = "%s 던전을 먼저 클리어해요" % need if need != "" else "아직 열리지 않았어요"
		line_col = Color(1, 0.75, 0.75)
	else:
		var bw: int = 0 if save == null else int(save.dungeon_best_wave(n))
		var total := int(def.get("waves", Data.rule("total_waves", 40)))
		line = ("최고 웨이브 %d / %d" % [bw, total]) if bw > 0 else "아직 기록이 없어요"
		line += "  ·  " + ("클리어 (재도전)" if st == "clear" else "도전 가능")
		line_col = K.GREEN if st == "clear" else K.WHITE
	dungeon_box.add_child(K.label(line, 22, Vector2(60, 168), Vector2(600, 32), line_col, HORIZONTAL_ALIGNMENT_CENTER, false))
	# 권장 카드 Lv vs 내 평균
	var rec: int = 0 if save == null else int(save.dungeon_rec_card_lv(n))
	if rec > 0 and save != null:
		var avg: float = save.avg_card_level()
		var verdict := "충분해요"
		var vcol := K.GREEN
		if avg < rec - 2.0:
			verdict = "조금 어려울 수 있어요"
			vcol = Color(1, 0.65, 0.4)
		elif avg < rec:
			verdict = "도전해 볼 만해요"
			vcol = K.GOLD
		dungeon_box.add_child(K.label("권장 카드 Lv %d  ·  내 평균 Lv %s  —  %s" % [rec, str(snappedf(avg, 0.1)), verdict], 19,
				Vector2(40, 200), Vector2(640, 28), vcol, HORIZONTAL_ALIGNMENT_CENTER, false))
	var rm: float = 1.0 if save == null else float(save.dungeon_reward_mult(n))
	var fc: int = 0 if save == null else int(save.dungeon_first_clear_shards(n))
	var reward := "재료 x%s" % str(snappedf(rm, 0.01))
	if fc > 0 and st != "clear":
		reward += "  ·  첫 클리어 +%d" % fc
	dungeon_box.add_child(K.label(reward, 19, Vector2(40, 226), Vector2(640, 26), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
	# 단계 점
	var step := 40.0
	var x0 := 360.0 - step * (count - 1) * 0.5
	for i in range(1, count + 1):
		var sti := Popups.dungeon_state(save, i)
		var tex := "pip_star_on.png" if sti == "clear" else ("pip_on.png" if sti == "open" else "pip_off.png")
		var ic := K.icon(C + tex, Vector2(x0 + (i - 1) * step - 13, 252), 1.0)
		if i == n:
			ic.scale = Vector2(1.3, 1.3)
			ic.position -= Vector2(4, 4)
		dungeon_box.add_child(ic)
	# 좌우 화살표 + 가운데 누르면 목록
	for d in [-1, 1]:
		var ok: bool = (n + d >= 1) and (n + d <= count)
		var lab := K.label("<" if d < 0 else ">", 64, Vector2(30 if d < 0 else 600, 60), Vector2(90, 100), K.GOLD if ok else Color(0.4, 0.37, 0.5))
		dungeon_box.add_child(lab)
		dungeon_box.add_child(K.hit_area(Rect2(24 if d < 0 else 594, 0, 102, 282), _step_dungeon.bind(d)))
	dungeon_box.add_child(K.hit_area(Rect2(130, 0, 460, 282), _open_dungeon_list))
	# 시작 버튼 상태
	btn_start.disabled = locked
	btn_start.modulate = Color.WHITE if not locked else Color(0.5, 0.5, 0.55)
	(btn_start.get_child(0) as Label).text = "잠긴 던전" if locked else ("다시 도전" if st == "clear" else "게임 시작")


func _step_dungeon(d: int) -> void:
	var n := _shown() + d
	if n < 1 or n > _count():
		return
	Sfx.play("button")
	_select_dungeon(n)


## 던전 n 을 화면에 보여 줌. 해금된 던전이면 선택(Save.selected_dungeon)도 바뀜. 잠긴 던전은 구경만(시작 불가).
func _select_dungeon(n: int) -> void:
	_view = n
	if save != null and save.dungeon_unlocked(n):
		save.selected_dungeon = n
	_draw_dungeon()


func _open_dungeon_list() -> void:
	Sfx.play("button")
	Popups.dungeon_list(self, save, _select_dungeon)


# ------------------------------------------------------------------ 캐릭터
func _tap_char(cid: String) -> void:
	_say(cid, _pick(LD.TAP_BUBBLES.get(cid, LD.GENERIC_BUBBLES)), 1.6)
	Sfx.play(str(LD.TAP_SOUND.get(cid, "button")))
	if save:
		save.buzz(20)
	var sp: AnimatedSprite2D = char_sprites[cid]
	var y0 := 500.0
	var tw := create_tween()
	tw.tween_property(sp, "position:y", y0 - 36.0, 0.12)
	tw.tween_property(sp, "position:y", y0, 0.14)


func _say(cid: String, text: String, secs: float) -> void:
	var bub: Panel = char_bubbles.get(cid)
	if bub == null:
		return
	(bub.get_child(0) as Label).text = text
	var tw := create_tween()
	tw.tween_property(bub, "modulate:a", 1.0, 0.12)
	tw.tween_interval(secs)
	tw.tween_property(bub, "modulate:a", 0.0, 0.25)


func _next_motto() -> void:
	_motto_t = 0.0
	motto_i = (motto_i + 1) % LD.MOTTOS.size()
	var tw := create_tween()
	tw.tween_property(lbl_motto, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): lbl_motto.text = LD.MOTTOS[motto_i])
	tw.tween_property(lbl_motto, "modulate:a", 1.0, 0.2)


# ------------------------------------------------------------------ 하단 탭
func _build_nav() -> void:
	nav_layer = Control.new()
	nav_layer.size = Vector2(720, 1280)
	nav_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_layer.z_index = 20
	add_child(nav_layer)
	_draw_nav()


func _draw_nav() -> void:
	for c in nav_layer.get_children():
		c.queue_free()
	nav_layer.add_child(K.icon(C + "nav_bg.png", Vector2(0, NAV_Y)))
	for i in NAV_ITEMS.size():
		var it: Array = NAV_ITEMS[i]
		var active: bool = it[2] == page
		var x := i * 144.0
		if active:
			nav_layer.add_child(K.icon(C + "nav_active.png", Vector2(x, NAV_Y - 4)))
		nav_layer.add_child(K.icon(C + it[1], Vector2(x + 40, NAV_Y + 14), 2.0))
		nav_layer.add_child(K.label(it[0], 23, Vector2(x, NAV_Y + 80), Vector2(144, 32), K.WHITE if active else K.DIM, HORIZONTAL_ALIGNMENT_CENTER))
		nav_layer.add_child(K.hit_area(Rect2(x, NAV_Y, 144, 120), _nav.bind(it[2])))


func _nav(target: String) -> void:
	Sfx.play("button")
	match target:
		"shop":
			K.toast(self, "준비 중이에요. 조금만 기다려 주세요!", 520.0)
		"ranking":
			if link == null:
				K.toast(self, "잠만보에서 로그인하면 랭킹에 참여해요", 520.0)
			else:
				_show_page("ranking")
		"settings":
			_open_settings()
		_:
			_show_page(target)


func _show_page(p: String) -> void:
	page = p
	home.visible = p == "home"
	if p == "cards":
		if cards == null:
			cards = CardsScene.instantiate()
			cards.back_requested.connect(func(): _show_page("home"))
			add_child(cards)
			move_child(cards, nav_layer.get_index())
		cards.visible = true
	elif cards != null:
		cards.visible = false
	if p == "ranking":
		if ranking == null:
			ranking = RankingScript.new()
			ranking.back_requested.connect(func(): _show_page("home"))
			add_child(ranking)
			move_child(ranking, nav_layer.get_index())
		ranking.visible = true
	elif ranking != null:
		ranking.visible = false
	_draw_nav()


# ------------------------------------------------------------------ 팝업/설정/시작
func _open_profile() -> void:
	Sfx.play("button")
	Popups.profile(self, save, link, _open_jmb)


func _open_quests() -> void:
	Sfx.play("button")
	Popups.quests(self, save, _refresh)


func _open_jmb() -> void:
	Sfx.play("button")
	if link != null and link.has_method("open_jammanbo"):
		link.open_jammanbo()
	else:
		K.toast(self, "잠만보 연동은 곧 열려요!", 520.0)


func _open_settings() -> void:
	if settings != null:
		return
	Sfx.play("popup_open")
	settings = SettingsScene.instantiate()
	settings.closed.connect(_close_settings)
	add_child(settings)
	settings.z_index = 50


func _close_settings() -> void:
	Sfx.play("popup_close")
	if settings != null:
		settings.queue_free()
		settings = null
	_refresh()


func _start_game() -> void:
	if save != null and not save.dungeon_unlocked(_shown()):
		K.toast(self, "먼저 앞 던전을 클리어하세요", 520.0, Color(1, 0.7, 0.7))
		return
	Sfx.play("button")
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _refresh() -> void:
	var shards: int = 0 if save == null else int(save.shards)
	lbl_shards.text = str(shards)
	var nick := "게스트"
	if link != null and link.has_method("logged_in") and link.logged_in():
		var nn := str(link.nickname())
		if nn != "":
			nick = nn
	lbl_nick.text = nick
	lbl_title.text = ("보세포" if save == null else str(save.title()))
	lbl_level.text = "Lv %d" % (1 if save == null else int(save.account_level()))
	for cid in char_labels:
		var lv: int = 1 if save == null else int(save.card_level(cid))
		char_labels[cid].text = "Lv %d" % lv
	var qs: Array = [] if save == null else save.daily_quests()
	var done := 0
	for q in qs:
		if q["claimed"]:
			done += 1
	quest_btn_label.text = "오늘의 할 일\n%d / %d 완료" % [done, qs.size()]
	quest_badge.visible = save != null and save.quests_claimable() > 0
	_draw_dungeon()


# ------------------------------------------------------------------ 첫 실행 · 일일 보상
func _first_run_flow() -> void:
	if save != null and not save.tutorial_done:
		_show_tutorial(true)
	else:
		_daily_popup()


func _show_tutorial(first: bool) -> void:
	var t := Tutorial.new()
	add_child(t)
	t.z_index = 200
	t.finished.connect(func(_skipped: bool):
		if save:
			save.set_tutorial_done()
		if first:
			_daily_popup())


func _daily_popup() -> void:
	if save == null or not save.daily_available():
		return
	var n: int = save.claim_daily()
	if n <= 0:
		return
	var layer := K.popup(self, Rect2(80, 400, 560, 440), "오늘의 첫 접속 보상")
	layer.add_child(K.icon("res://assets/screens/result/icon_card_shard.png", Vector2(260, 535), 3.0))
	layer.add_child(K.label("+%d" % n, 56, Vector2(370, 525), Vector2(200, 110), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
	layer.add_child(K.label("카드 재료를 받았어요. 하루에 한 번!", 22, Vector2(80, 650), Vector2(560, 40), K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
	layer.add_child(K.button("res://assets/td/ui/btn_green_big.png", "확인", Rect2(210, 710, 300, 100), func():
		Sfx.play("coin")
		(layer.get_meta("close") as Callable).call(), 36))


# ------------------------------------------------------------------ 검증용: 화면 저장
func _shot_setup() -> void:
	match start_page:
		"cards":
			_show_page("cards")
		"club":
			_show_page("cards")
			cards.sel = cards.ids.size() - 1
			cards._build()
		"settings":
			_open_settings()
		"odds":
			_open_settings()
			settings._show_odds()
		"tutorial":
			_show_tutorial(false)
		"daily":
			if save:
				save.daily_last = ""
			_daily_popup()
		"dungeons":
			_open_dungeon_list()
		"profile":
			_open_profile()
		"quests":
			_open_quests()
		"locked":
			_select_dungeon(4)
		"say":
			for cid in char_ids:
				_say(cid, _pick(LD.TAP_BUBBLES.get(cid, LD.GENERIC_BUBBLES)), 5.0)
		"ranking", "ranking_empty", "ranking_fail":
			_show_page("ranking")
			if start_page == "ranking":
				ranking.show_data({"scope": "week", "mine": {"rank": 12, "nick": "게스트", "wave": 23, "score": 9120},
						"top": [{"rank": 1, "nick": "보드게임왕", "wave": 40, "score": 31200}, {"rank": 2, "nick": "여름이", "wave": 38, "score": 28800},
						{"rank": 3, "nick": "아르는겁쟁이", "wave": 36, "score": 25100}, {"rank": 4, "nick": "마니마니", "wave": 33, "score": 20300},
						{"rank": 5, "nick": "카탄장인", "wave": 31, "score": 18800}, {"rank": 6, "nick": "티츄러버", "wave": 30, "score": 17600},
						{"rank": 7, "nick": "잠만보", "wave": 29, "score": 16000}, {"rank": 8, "nick": "랜덤신", "wave": 27, "score": 14900}]})
			elif start_page == "ranking_empty":
				ranking.show_data({"scope": "week", "mine": {}, "top": []})
			else:
				ranking.show_state("fail")
	for i in 6:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(lobby_shot)
	print("LOBBY_SHOT ", lobby_shot, " ", img.get_size())
	get_tree().quit()
