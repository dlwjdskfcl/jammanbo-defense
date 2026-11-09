extends Node2D
## 타워 유닛 (캐릭터 + 등급). 수치는 data/game_data.json 의 characters.<id>.stat, 스킬 수치는 gp_skills.gd 에서 옵니다.

const U = preload("res://scripts/util.gd")
const GS = preload("res://scripts/gp_skills.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")
const BadgesScript = preload("res://scripts/gp_badges.gd")

var game
var char_id: String = ""
var grade: int = 1
var slot: int = -1
var stat: Dictionary = {}
var fire_stat: Dictionary = {}     # 발사 때 쓰는 stat (스킬로 보정된 복사본)
var base_damage: float = 0.0       # 등급·카드 배율 반영, 인접 효과 전
var damage: float = 0.0            # 인접 효과까지 반영한 공격력
var base_interval: float = 1.0
var interval: float = 1.0
var base_range_px: float = 0.0
var range_px: float = 0.0
var spd_mult: float = 1.0
var cd: float = 0.0
var spr: AnimatedSprite2D
var badges: Node2D

var synergy_partner: bool = false  # 여름×아르 인접 시너지 중
var anger_t: float = 0.0           # 여름 분노(괴롭히기) 남은 시간
var dodge_stacks: int = 0
var attack_count: int = 0
var dragging: bool = false
var absent: bool = false           # 노쇼 이벤트: 이번 웨이브 불참
var aura_mult: float = 1.0         # 인접 미플 aura
var _tier: Array = [true, false, false]


func setup(g, cid: String, gr: int, slot_index: int) -> void:
	game = g
	char_id = cid
	grade = gr
	slot = slot_index
	stat = Data.unit_def(cid)["stat"]
	fire_stat = stat
	for t in [1, 2]:
		_tier[t] = GS.unlocked(cid, t)
	base_damage = float(stat["damage"]) * Data.grade_mult(gr) * GS.card_mult(cid)
	damage = base_damage
	var min_interval: float = 1.0 / float(Data.rule("max_attack_speed", 8))
	base_interval = max(float(stat["interval"]), min_interval)
	interval = base_interval
	base_range_px = float(stat["range_tiles"]) * game.T
	range_px = base_range_px
	cd = randf() * interval
	spr = AnimatedSprite2D.new()
	spr.sprite_frames = GS.unit_frames(cid, gr)
	spr.modulate = GS.unit_mod(cid, gr)
	add_child(spr)
	spr.play("idle")
	spr.animation_finished.connect(_on_anim_finished)
	badges = BadgesScript.new()
	badges.position = Vector2(0, -42)
	badges.z_index = 2
	add_child(badges)
	if cid == "mani" and _tier[1]:
		fire_stat = stat.duplicate()
		fire_stat["effect_chance"] = min(1.0, float(stat["effect_chance"]) * GS.v("charm_chance_mult"))


func _on_anim_finished() -> void:
	if spr.animation == "attack":
		spr.play("idle")


## 인접(8방향) 아군에 따른 보정 — 슬롯 구성이 바뀔 때마다 game 이 호출
func recalc() -> void:
	var dm := 1.0
	var sm := 1.0
	var rm := 1.0
	var nbs: Array = game.neighbors(slot)
	var has_arr := false
	var has_yeo := false
	var near_mani := false
	var aura := 1.0
	var non_pet_nb := false
	for n in nbs:
		if n.stat["effect"] == "aura_spd":      # 미플: 인접 아군 공속 (등급이 높을수록 +15%씩 상대 증가)
			aura *= 1.0 + float(n.stat["effect_value"]) * (1.0 + 0.15 * (n.grade - 1))
		if not Data.is_pet(n.char_id):
			non_pet_nb = true
		if n.char_id == "arr":
			has_arr = true
		elif n.char_id == "yeoreum":
			has_yeo = true
		elif n.char_id == "mani" and n._tier[2]:
			near_mani = true
	synergy_partner = (char_id == "yeoreum" and has_arr) or (char_id == "arr" and has_yeo)
	var b_atk := false
	var b_rng := false
	if char_id == "yeoreum":
		if nbs.is_empty():
			dm += GS.v("lonely_atk")
			b_atk = true
		else:
			rm += GS.v("lonely_range")
			b_rng = true
		if has_arr:
			dm += GS.v("syn_yeo_dmg")
			b_atk = true
	elif char_id == "arr" and has_yeo and not _tier[2]:
		sm *= 1.0 - GS.v("syn_arr_slow")
	if near_mani:
		sm += GS.v("doglike_spd")
	if char_id == "mani" and non_pet_nb:       # 판 위에 누운 고양이: 모임 유닛 옆이면 공속 +8%
		sm *= 1.08
	sm *= aura
	aura_mult = aura
	spd_mult = sm
	damage = base_damage * dm
	range_px = base_range_px * rm
	badges.set_on("buff_atk", b_atk)
	badges.set_on("buff_range", b_rng)
	_update_spd_badge(near_mani or aura > 1.0)


func set_absent(on: bool) -> void:
	absent = on
	spr.modulate = Color(0.45, 0.45, 0.5) if on else GS.unit_mod(char_id, grade)


func _update_spd_badge(boosted: bool) -> void:
	badges.set_on("buff_spd", boosted or anger_t > 0.0)


func _process(delta: float) -> void:
	if absent:
		return
	if anger_t > 0.0:
		anger_t -= delta
		if anger_t <= 0.0:
			_update_spd_badge(spd_mult > 1.0)
	cd -= delta
	if cd > 0.0:
		return
	var target = game.find_target(self)
	if target == null:
		cd = 0.05
		return
	cd = _next_interval(target)
	fire(target)


func _next_interval(target) -> float:
	var f := spd_mult
	if anger_t > 0.0:
		f += GS.v("pester_spd")
	if char_id == "arr":       # 겁쟁이 본능(기본 스킬): 가까울수록 빠르게
		var d: float = position.distance_to(target.position)
		f *= 1.0 + GS.v("instinct_max_speed") * clamp(1.0 - d / max(range_px, 1.0), 0.0, 1.0)
	var min_interval: float = 1.0 / float(Data.rule("max_attack_speed", 8))
	return max(base_interval / f, min_interval)


func fire(target) -> void:
	spr.play("attack")
	Sfx.play("attack_" + char_id)
	attack_count += 1
	var dmg: float = damage * game.cur_atk_mult()
	var extra: Dictionary = {}
	match char_id:
		"arr":
			if _tier[1] and dodge_stacks < int(GS.v("dodge_max_stacks")) and randf() < GS.v("dodge_chance"):
				dodge_stacks += 1
				game.spawn_skill_fx("arr_dodge", position + Vector2(0, 8), 0.7, 12.0)
			dmg *= 1.0 + dodge_stacks * GS.v("dodge_stack_dmg")
			if _tier[2] and attack_count % int(GS.v("swat_every")) == 0:
				dmg *= GS.v("swat_dmg_mult")
				dodge_stacks = 0
				extra["punch"] = true
		"mani":
			if randf() < GS.v("free_crit_chance"):
				dmg *= GS.v("free_crit_mult")
				extra["free"] = true
	var p := ProjectileScript.new()
	game.proj_node.add_child(p)
	p.setup(game, position, target, dmg, fire_stat, self, extra)


## 투사체가 맞는 순간 호출: 스킬에 따른 피해 보정·효과. 최종 피해를 돌려줌.
func on_hit(target, dmg: float, extra: Dictionary) -> float:
	match char_id:
		"mani":
			if _tier[1] and target.slow_t > 0.0:
				dmg *= 1.0 + GS.v("charm_bonus_dmg")
			if extra.get("free", false):
				game.spawn_skill_fx("mani_free", target.position, 0.6, 12.0)
		"yeoreum":
			if _tier[1]:
				var bonus := 0.0
				if target.boss:
					bonus = GS.v("smart_boss_bonus")
				elif game.is_leader(target):
					bonus = GS.v("smart_lead_bonus")
				if bonus > 0.0:
					dmg *= 1.0 + bonus
					game.spawn_skill_fx("yeo_smart", target.position + Vector2(0, -26), 0.7, 10.0)
		"arr":
			if extra.get("punch", false):
				game.spawn_skill_fx("arr_swat", target.position, 0.8, 14.0)
				if not target.boss:
					target.stun_t = max(target.stun_t, GS.v("swat_stun"))
				for n in game.neighbors(slot):
					if n.char_id == "yeoreum" and n._tier[2]:
						n.get_angry()
	return dmg


func get_angry() -> void:
	anger_t = GS.v("pester_time")
	badges.set_on("buff_spd", true)
	game.spawn_skill_fx("yeo_pester", position + Vector2(18, -34), 0.9, 10.0)


func skill_text() -> String:
	var out := ""
	for s in GS.skill_list(char_id):
		var ok: bool = GS.unlocked(char_id, int(s["tier"]))
		out += "%s %s" % ["●" if ok else "○", s["name"]]
		out += "  " if ok else "(Lv%d 해금)  " % (6 if int(s["tier"]) == 1 else 12)
	return out
