extends RefCounted
## 스킬 수치·설명·해금 판정 + 소소한 공용 도우미 (게임플레이 핵심).
## 수치는 한곳(DEFAULTS)에 모았고, data/game_data.json 에 "skills" 객체가 생기면 그 값이 우선합니다
## (엑셀 '스킬' 시트로 옮길 후보 — 작업보고 참고).

const U = preload("res://scripts/util.gd")

const DEFAULTS := {
	# 아르 — 겁쟁이 본능(기본): 적이 가까울수록 공격속도 증가 (사거리 안쪽에 붙을수록 최대치)
	"instinct_max_speed": 0.6,
	# 아르 — 재빠른 회피(Lv6): 공격할 때마다 확률로 회피 스택(최대 N), 스택당 피해 증가
	"dodge_chance": 0.15, "dodge_max_stacks": 3, "dodge_stack_dmg": 0.12,
	# 아르 — 냥펀치(Lv12): N번째 공격은 강타(피해 배율 + 스턴), 회피 스택 소모
	"swat_every": 6, "swat_dmg_mult": 2.5, "swat_stun": 0.6,
	# 마니 — 자유로운 영혼(기본): 랜덤 타겟(엑셀 target=random) + 확률로 자유로운 한방
	"free_crit_chance": 0.1, "free_crit_mult": 1.5,
	# 마니 — 하트 매혹(Lv6): 둔화 확률 배율, 둔화된 적에게 추가 피해
	"charm_chance_mult": 1.5, "charm_bonus_dmg": 0.2,
	# 마니 — 개냥이(Lv12): 인접(8방향) 아군의 공격속도 증가
	"doglike_spd": 0.2,
	# 여름 — 외로움(기본): 인접 아군이 없으면 공격력 증가, 있으면 사거리 증가
	"lonely_atk": 0.3, "lonely_range": 0.2,
	# 여름 — 똑쟁이(Lv6): 보스·선두 적에게 추가 피해
	"smart_boss_bonus": 0.35, "smart_lead_bonus": 0.15,
	# 여름 — 괴롭히기(Lv12): 아르의 냥펀치를 맞으면 분노(공격속도 증가), 시너지 페널티 제거
	"pester_spd": 0.25, "pester_time": 3.0,
	# 여름×아르 인접 시너지(기본): 여름 공격력 증가 / 아르 공격 간격 증가(괴롭힘 당함)
	"syn_yeo_dmg": 0.25, "syn_arr_slow": 0.10,
}

## 캐릭터별 스킬 목록 (표시용). tier: 0=기본, 1=Lv6, 2=Lv12
const LIST := {
	"arr": [
		{"id": "arr_instinct", "tier": 0, "name": "겁쟁이 본능", "desc": "적이 가까울수록 공격속도 최대 +{instinct_max_speed%}"},
		{"id": "arr_dodge", "tier": 1, "name": "재빠른 회피", "desc": "공격 시 {dodge_chance%} 확률로 회피 스택(최대 {dodge_max_stacks}), 스택당 피해 +{dodge_stack_dmg%}"},
		{"id": "arr_swat", "tier": 2, "name": "냥펀치", "desc": "{swat_every}번째 공격은 x{swat_dmg_mult} 강타 + 스턴, 인접 여름이 분노"},
	],
	"mani": [
		{"id": "mani_free", "tier": 0, "name": "자유로운 영혼", "desc": "매번 랜덤 적을 노림, {free_crit_chance%} 확률로 x{free_crit_mult} 한방"},
		{"id": "mani_charm", "tier": 1, "name": "하트 매혹", "desc": "둔화 확률 x{charm_chance_mult}, 둔화된 적에게 피해 +{charm_bonus_dmg%}"},
		{"id": "mani_doglike", "tier": 2, "name": "개냥이", "desc": "인접한 아군 공격속도 +{doglike_spd%}"},
	],
	"yeoreum": [
		{"id": "yeo_lonely", "tier": 0, "name": "외로움", "desc": "인접 아군이 없으면 공격력 +{lonely_atk%}, 있으면 사거리 +{lonely_range%}"},
		{"id": "yeo_smart", "tier": 1, "name": "똑쟁이", "desc": "보스에게 피해 +{smart_boss_bonus%}, 선두 적에게 +{smart_lead_bonus%}"},
		{"id": "yeo_pester", "tier": 2, "name": "괴롭히기", "desc": "아르 냥펀치에 맞으면 분노(공속 +{pester_spd%}), 시너지 페널티 제거"},
	],
}
const SYNERGY := {"id": "synergy_yeo_arr", "name": "여름×아르 시너지",
		"desc": "인접하면 여름 공격력 +{syn_yeo_dmg%}, 아르 공격 간격 +{syn_arr_slow%}"}

static var _prefs: ConfigFile = null


static func v(key: String) -> float:
	var s: Dictionary = Data.d.get("skills", {})
	return float(s.get(key, DEFAULTS.get(key, 0.0)))


static func _save_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("/root/Save") if tree != null else null


static func unlocked(char_id: String, tier: int) -> bool:
	if tier <= 0:
		return true
	if "--all-skills" in OS.get_cmdline_user_args():     # 검증용: Lv6/Lv12 스킬을 모두 켬
		return true
	var sv := _save_node()
	if sv != null and sv.has_method("skill_unlocked"):
		return bool(sv.skill_unlocked(char_id, tier))
	return false


static func card_mult(char_id: String) -> float:
	var sv := _save_node()
	if sv != null and sv.has_method("card_mult"):
		return float(sv.card_mult(char_id))
	return 1.0


static func card_level(char_id: String) -> int:
	var sv := _save_node()
	if sv != null and sv.has_method("card_level"):
		return int(sv.card_level(char_id))
	return 1


## "{key%}" → 퍼센트 문자열, "{key}" → 숫자
static func describe(text: String) -> String:
	var out := text
	for k in DEFAULTS.keys():
		out = out.replace("{%s%%}" % k, "%d%%" % int(round(v(k) * 100.0)))
		var n := v(k)
		out = out.replace("{%s}" % k, str(int(n)) if is_equal_approx(n, round(n)) else str(n))
	return out


static func skill_list(char_id: String) -> Array:
	return LIST.get(char_id, [])


## 상태/스킬 이펙트 프레임 (assets/<dir>/<id>_N.png 를 순서대로 읽음)
static func fx_frames(dir: String, id: String, fps: float, loop: bool) -> SpriteFrames:
	var paths: Array = []
	var i := 0
	while ResourceLoader.exists("res://assets/%s/%s_%d.png" % [dir, id, i]):
		paths.append("res://assets/%s/%s_%d.png" % [dir, id, i])
		i += 1
	if paths.is_empty():
		return null
	return U.frames("gp|%s|%s" % [dir, id], paths, fps, loop)


## 합성 팝업 생략 여부. Save.merge_popup(bool)이 있으면 그 값(팝업 켜짐=true)을 우선, 없으면 gp_prefs 사용
static func quick_merge() -> bool:
	var sv := _save_node()
	if sv != null and "merge_popup" in sv:
		return not bool(sv.merge_popup)
	return bool(pref("quick_merge", false))


static func set_quick_merge(on: bool) -> void:
	var sv := _save_node()
	if sv != null and "merge_popup" in sv:
		sv.merge_popup = not on
		if sv.has_method("settings_changed"):
			sv.settings_changed()
	else:
		set_pref("quick_merge", on)


# ---- 사용자 설정(합성 팝업 생략 등) — 자체 파일, Save 와 무관
static func pref(key: String, default_value):
	_load_prefs()
	return _prefs.get_value("gp", key, default_value)


static func set_pref(key: String, value) -> void:
	_load_prefs()
	_prefs.set_value("gp", key, value)
	_prefs.save("user://gp_prefs.cfg")


static func _load_prefs() -> void:
	if _prefs == null:
		_prefs = ConfigFile.new()
		_prefs.load("user://gp_prefs.cfg")
