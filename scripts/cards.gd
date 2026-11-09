extends Control
## 캐릭터 카드 성장 화면 (로비의 카드 탭). 캐릭터 탭은 Data.d["characters"] 를 돌며 자동으로 만들어집니다.
## 카드 재료(shards)를 써서 Lv1~15 로 강화. 6·12 레벨에 스킬 해금과 공격력 점프. 수치는 Save/엑셀('카드성장')에서 옵니다.
## 아래쪽 하단 탭(y 1160~)은 로비가 그립니다.

signal back_requested

const K = preload("res://scripts/ui_kit.gd")
const C := "res://assets/screens/common/"
const TAGLINE := {"arr": "겁쟁이", "mani": "개냥이", "yeoreum": "똑쟁이"}   # 엑셀에 성격 한 줄이 내보내지기 전까지의 꼬리표

var save: Node
var ids: Array = []
var sel: int = 0
var layer: Control


func _ready() -> void:
	size = Vector2(720, 1280)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	save = get_node_or_null("/root/Save")
	ids = save.card_ids() if save != null else Data.d.get("characters", {}).keys() + ["club"]
	if save:
		save.changed.connect(_build)
	_build()


const CLUB_INFO := {"name": "모임", "species": "club", "bg": "#dcd3f2", "stat": {}}


func _info(cid: String) -> Dictionary:
	return CLUB_INFO if cid == "club" else Data.d["characters"].get(cid, {"name": cid, "stat": {}})


## 모임 카드가 적용되는 유닛(units 표에서 pet=false) 수
func _club_units() -> int:
	var n := 0
	for k in Data.d.get("units", {}):
		if not bool(Data.d["units"][k].get("pet", true)):
			n += 1
	return n


func _fmt(v: float) -> String:
	return "%d" % int(round(v)) if absf(v - round(v)) < 0.05 else "%.1f" % v


func _level(cid: String) -> int:
	return 1 if save == null else int(save.card_level(cid))


func _build() -> void:
	if layer != null:
		layer.queue_free()
	layer = Control.new()
	layer.size = Vector2(720, 1280)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	K.menu_bg(layer)
	K.header(layer, "캐릭터 카드", _on_back)
	if ids.is_empty():
		return
	sel = clampi(sel, 0, ids.size() - 1)
	var cid: String = ids[sel]
	var info: Dictionary = _info(cid)
	var is_club := cid == "club"
	var lv := _level(cid)
	var max_lv: int = 15 if save == null else int(save.max_level())
	var shards: int = 0 if save == null else int(save.shards)
	var cost: int = 0 if save == null else int(save.cost_of_level(lv))

	_tabs(layer)

	# 카드
	var bg_col := Color.html(str(info.get("bg", "#e9dfc4")))
	layer.add_child(K.panel(Rect2(45, 235, 215, 300), Color(0.2, 0.15, 0.1), Color(0.35, 0.27, 0.2), 16, 4))
	layer.add_child(K.panel(Rect2(53, 243, 199, 284), bg_col, bg_col.darkened(0.2), 10, 2))
	if is_club:
		layer.add_child(K.icon(C + "icon_card.png", Vector2(88, 270), 4.5))   # 임시 그림(모임 유닛 초상화가 생기면 교체)
	else:
		layer.add_child(K.icon("res://assets/portraits/%s_normal.png" % cid, Vector2(58, 252), 3.0))
	layer.add_child(K.label(str(info.get("name", cid)), 34, Vector2(53, 448), Vector2(199, 46), Color(0.2, 0.14, 0.12),
			HORIZONTAL_ALIGNMENT_CENTER, false))
	var species := "고양이" if str(info.get("species", "")) == "cat" else "강아지"
	if is_club:
		species = "모임 유닛 공통"
	var tag: String = str(TAGLINE.get(cid, ""))
	layer.add_child(K.label(species + (" · " + tag if tag != "" else ""), 21, Vector2(53, 490), Vector2(199, 32),
			Color(0.4, 0.32, 0.28), HORIZONTAL_ALIGNMENT_CENTER, false))

	# 레벨 + 진행바
	layer.add_child(K.label("Lv %d" % lv, 66, Vector2(290, 228), Vector2(190, 84), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	layer.add_child(K.label("/ %d" % max_lv, 30, Vector2(480, 252), Vector2(100, 50), K.DIM, HORIZONTAL_ALIGNMENT_LEFT, false))
	var ratio := 1.0 if cost <= 0 else clampf(float(shards) / float(cost), 0.0, 1.0)
	layer.add_child(K.panel(Rect2(290, 322, 400, 24), Color(0.1, 0.08, 0.16), Color(0.3, 0.27, 0.4), 10, 2))
	if ratio > 0.0:
		layer.add_child(K.panel(Rect2(292, 324, maxf(396.0 * ratio, 12.0), 20), Color(0.98, 0.7, 0.2),
				Color(0.98, 0.7, 0.2), 8, 0))
	layer.add_child(K.icon("res://assets/screens/result/icon_card_shard.png", Vector2(290, 354), 1.5))
	var shard_text := "카드 재료   %d / %d" % [shards, cost] if cost > 0 else "카드 재료   %d  (최고 레벨)" % shards
	layer.add_child(K.label(shard_text, 26, Vector2(344, 352), Vector2(350, 52), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))

	# 능력치
	var st: Dictionary = info.get("stat", {})
	var base_dmg := float(st.get("damage", 0))
	var mult_now: float = 1.0 if save == null else float(save.mult_of_level(lv))
	var mult_next: float = mult_now if (save == null or lv >= max_lv) else float(save.mult_of_level(lv + 1))
	var dmg_now := base_dmg * mult_now
	var dmg_delta := base_dmg * mult_next - dmg_now
	var delta_text := ""
	if lv >= max_lv:
		delta_text = "MAX"
	elif dmg_delta > 0.001:
		delta_text = "+" + _fmt(dmg_delta)
	var rows: Array = [
		["공격력", _fmt(dmg_now), delta_text],
		["공격속도", "%s /초" % _fmt(1.0 / maxf(float(st.get("interval", 1.0)), 0.01)), ""],
		["사거리", "%s칸" % _fmt(float(st.get("range_tiles", 0))), ""],
	]
	if is_club:
		var bonus_now := (mult_now - 1.0) * 100.0
		var bonus_next := (mult_next - 1.0) * 100.0
		rows = [
			["공격력 보너스", "+%s%%" % _fmt(bonus_now), ("+" + _fmt(bonus_next - bonus_now) + "%") if lv < max_lv else "MAX"],
			["적용 대상", "모임 유닛 %d종" % _club_units(), ""],
			["큰 성장", "Lv6 · Lv12", ""],
		]
	for i in rows.size():
		var y := 410.0 + i * 56.0
		layer.add_child(K.panel(Rect2(290, y, 400, 48), K.ROW_FILL, K.ROW_LINE, 12, 2))
		layer.add_child(K.label(rows[i][0], 22, Vector2(306, y), Vector2(130, 48), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false))
		layer.add_child(K.label(rows[i][1], 24, Vector2(430, y), Vector2(150, 48), K.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, false))
		layer.add_child(K.label(rows[i][2], 22, Vector2(580, y), Vector2(100, 48), K.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, false))
	var note := "※ 공격력은 1성 기준, 합성하면 등급 배율이 곱해져요 (공속 상한 %s/초)" % str(Data.rule("max_attack_speed", 8))
	if is_club:
		note = "※ 반려(아르·마니·여름)가 아닌 모든 유닛에 적용돼요"
	layer.add_child(K.label(note, 18, Vector2(45, 586), Vector2(645, 30), K.DIM, HORIZONTAL_ALIGNMENT_LEFT, false))

	# 성장 단계 트랙
	layer.add_child(K.label("성장 단계", 30, Vector2(60, 624), Vector2(300, 44), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	var star_lvs: Array = []
	for t in [1, 2]:
		star_lvs.append(100 if save == null else int(save.unlock_level(cid, t)))
	var step := 600.0 / (max_lv - 1)
	for l in range(1, max_lv + 1):
		var x := 60.0 + (l - 1) * step
		var reached := l <= lv
		if star_lvs.has(l):
			layer.add_child(K.icon(C + ("pip_star_on.png" if reached else "pip_star_off.png"), Vector2(x - 15, 676), 1.0))
			layer.add_child(K.label("Lv%d" % l, 18, Vector2(x - 30, 710), Vector2(60, 26), K.WHITE if reached else K.DIM,
					HORIZONTAL_ALIGNMENT_CENTER, false))
		else:
			layer.add_child(K.icon(C + ("pip_on.png" if reached else "pip_off.png"), Vector2(x - 13, 680), 1.0))

	# 스킬
	layer.add_child(K.label("스킬" if not is_club else "효과", 30, Vector2(60, 750), Vector2(300, 44), K.GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	var skills: Array = [] if (save == null or is_club) else save.skills_of(cid)
	for i in skills.size():
		_skill_cell(skills[i], i, skills.size(), lv)
	if is_club:
		layer.add_child(K.panel(Rect2(60, 790, 600, 200), K.ROW_FILL, K.ROW_LINE, 16, 3))
		layer.add_child(K.icon(C + "icon_card.png", Vector2(90, 860), 2.5))
		var club_txt := K.label("모임 카드\n모든 모임 유닛 공격력 +%s%%" % _fmt((mult_now - 1.0) * 100.0), 26, Vector2(190, 800),
				Vector2(450, 180), K.WHITE, HORIZONTAL_ALIGNMENT_LEFT, false)
		club_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		layer.add_child(club_txt)

	# 강화 버튼
	var chk: Dictionary = {"ok": false, "reason": "", "cost": 0} if save == null else save.can_upgrade(cid)
	var btn := K.button("res://assets/td/ui/btn_gold_big.png", "강화하기" if lv < max_lv else "최고 레벨",
			Rect2(210, 1010, 300, 100), _upgrade, 36)
	K.set_enabled(btn, bool(chk["ok"]))
	layer.add_child(btn)
	if chk["ok"]:
		layer.add_child(K.icon("res://assets/screens/result/icon_card_shard.png", Vector2(300, 1122), 1.3))
		layer.add_child(K.label("%d" % int(chk["cost"]), 28, Vector2(344, 1118), Vector2(120, 40), K.GOLD,
				HORIZONTAL_ALIGNMENT_LEFT))
	else:
		layer.add_child(K.label(str(chk["reason"]), 24, Vector2(60, 1116), Vector2(600, 40), Color(1, 0.7, 0.7),
				HORIZONTAL_ALIGNMENT_CENTER, false))


func _tabs(parent: Control) -> void:
	var n := ids.size()
	var gap := 12.0
	var w := (660.0 - gap * (n - 1)) / n
	for i in n:
		var on := i == sel
		var x := 30.0 + i * (w + gap)
		parent.add_child(K.button(C + ("tab_on.png" if on else "tab_off.png"), str(_info(ids[i]).get("name", ids[i])),
				Rect2(x, 128, w, 84), _select.bind(i), 30))


func _skill_cell(sk: Dictionary, i: int, n: int, lv: int) -> void:
	var w := 190.0
	var gap := (600.0 - w * n) / maxf(n - 1, 1)
	var x := 60.0 + i * (w + gap)
	var y := 790.0
	var unl := int(sk.get("unlock", 1))
	var unlocked: bool = lv >= unl
	layer.add_child(K.panel(Rect2(x, y, w, 200), K.ROW_FILL, K.ROW_LINE if unlocked else Color(0.25, 0.22, 0.33), 16, 3))
	var ic := K.icon("res://assets/skill_icons/%s" % str(sk.get("icon", "")), Vector2(x + 47, y + 12), 3.0)
	if not unlocked:
		ic.modulate = Color(0.45, 0.45, 0.5, 0.6)
	layer.add_child(ic)
	if not unlocked:
		layer.add_child(K.icon(C + "icon_lock.png", Vector2(x + 63, y + 44), 2.0))
	layer.add_child(K.label("기본" if unl <= 1 else "Lv %d 해금" % unl, 21, Vector2(x, y + 112), Vector2(w, 34),
			K.WHITE if unlocked else K.DIM, HORIZONTAL_ALIGNMENT_CENTER, false))
	layer.add_child(K.label(str(sk.get("name", "")), 20, Vector2(x, y + 148), Vector2(w, 34), K.GOLD if unlocked else K.DIM,
			HORIZONTAL_ALIGNMENT_CENTER, false))
	layer.add_child(K.hit_area(Rect2(x, y, w, 200), _skill_info.bind(sk, unlocked)))


func _skill_info(sk: Dictionary, unlocked: bool) -> void:
	Sfx.play("button")
	var text := "%s : %s" % [sk.get("name", ""), sk.get("desc", "")]
	if not unlocked:
		text = "Lv %d 에 해금돼요 : %s" % [int(sk.get("unlock", 1)), sk.get("name", "")]
	K.toast(self, text, 740.0)


func _select(i: int) -> void:
	Sfx.play("card_flip")
	sel = i
	_build()


func _on_back() -> void:
	Sfx.play("button")
	back_requested.emit()


func _upgrade() -> void:
	if save == null or ids.is_empty():
		return
	var cid: String = ids[sel]
	var before: int = save.card_level(cid)
	if save.upgrade_card(cid):
		var after: int = save.card_level(cid)
		Sfx.play("level_up")
		save.buzz(40)
		var msg := "Lv %d !" % after
		for sk in save.skills_of(cid):
			if int(sk.get("unlock", 1)) > before and int(sk.get("unlock", 1)) <= after:
				msg = "스킬 해금!  %s" % str(sk.get("name", ""))
				Sfx.play("mythic_summon")
		K.toast(self, msg, 540.0)
	else:
		Sfx.play("no_coin")
