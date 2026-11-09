extends Node
## 저장 · 설정 · 카드 성장 (autoload "Save").
## 파일: user://save.json (웹에서는 자동으로 IndexedDB). 깨진 파일은 save.json.bak 으로 옮기고 새로 시작합니다.
## 수치(레벨별 재료·공격력 배율·판 보상)는 data/game_data.json 의 "cards" (엑셀 '카드성장'·'카드스킬'·'메타규칙')에서
## 읽고, 없으면 아래 DEFAULT_* 내장값을 씁니다.
## ★ 아래 '고정 API' 이름·반환 형태는 game.gd 와의 약속입니다. (함수 추가는 자유)
##   card_level / card_mult / skill_unlocked / best_wave / record_run / sfx_volume / bgm_volume / vibrate / default_speed

signal changed
## 잠만보 연동(JmbLink)용 — 둘 다 없어도 게임은 그대로 동작
signal run_started(info: Dictionary)    # game.gd 가 판을 시작할 때 emit({"dungeon": selected_dungeon}). JmbLink 가 서버에 판 시작을 알림(안 보내면 JmbLink 가 장면 전환으로 대신 감지)
signal run_recorded(info: Dictionary)   # record_run() 끝에 emit {win, wave, kills, coins, dungeon, play_sec, units:{g1..g5}, shards}

const VERSION := 2
const MAX_LEVEL := 15
const DEFAULT_COSTS := [5, 5, 10, 15, 25, 35, 50, 65, 85, 105, 130, 155, 180, 215, 0]   # 레벨 n → n+1 에 필요한 재료
const DEFAULT_UNLOCK := [1, 6, 12]                                                       # 스킬 단계(0,1,2)별 해금 레벨
const DEFAULT_DUNGEONS := ["보세포", "보생아", "보린이", "보소년", "보청년", "보포티", "보중년", "보노인", "보해골", "보유령"]
const DAILY_QUESTS := [   # 오늘의 할 일 (무료·광고 없음). need: 목표, reward: 카드 재료
	{"id": "play", "text": "던전 1회 도전", "need": 1, "reward": 5},
	{"id": "wave", "text": "웨이브 15 도달", "need": 15, "reward": 8},
]
const DEFAULT_META := {"dungeon_reward_step_pct": 25, "shards_base": 2, "shards_per_wave": 1, "shards_per_30kills": 1, "shards_win_bonus": 30,
		"shards_new_best_bonus": 15, "shards_cap": 100, "daily_bonus": 10}

# ---- 설정 (고정 API 속성) ----
var sfx_volume: float = 1.0      # 0..1
var bgm_volume: float = 0.6      # 0..1
var vibrate: bool = true
var default_speed: int = 1       # 1 또는 2
var merge_popup: bool = true     # 합성 팝업(카드 뒤집기 연출) 보기. 끄면 바로 합성

# ---- 진행 상황 ----
var shards: int = 0              # 카드 재료(메타 재화). 인게임 코인과 별개
var runs: int = 0
var wins: int = 0
var total_kills: int = 0
var tutorial_done: bool = false
var daily_last: String = ""      # 마지막으로 접속 보상을 받은 날짜 "YYYY-MM-DD"
var _best_wave: int = 0
var _levels: Dictionary = {}     # char_id -> level
var _dungeons: Dictionary = {}   # 던전 번호(int) -> {"best_wave": int, "cleared": bool}
var selected_dungeon: int = 1 : set = _set_selected_dungeon   # 1..던전 수. 잠긴 던전은 선택되지 않음(game 은 이 값만 읽으면 됨)
var _quest: Dictionary = {"date": "", "runs": 0, "wave": 0, "claimed": []}   # 오늘의 할 일 진행

var save_path: String = "user://save.json"
var persist: bool = true         # false 면 디스크에 쓰지 않음(봇/스크린샷 검증용)
var cards_override: Dictionary = {}   # 테스트용: Data 대신 쓸 "cards" 표
var _flush_pending: bool = false
var run_meta: Dictionary = {}    # (선택) game.gd 가 record_run 직전에 {"units": {"g1": n, … "g5": n}, "play_sec": 초} 를 넣으면 run_recorded 에 같이 감(서버는 play_sec 를 자기 시계로 다시 잼)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autoplay" or a.begins_with("--shot"):
			persist = false      # 봇이 플레이어의 저장 파일을 건드리지 않게
	load_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()


# ================================================================== 수치 표
func _cards() -> Dictionary:
	if not cards_override.is_empty():
		return cards_override
	var data = get_node_or_null("/root/Data") if is_inside_tree() else null
	if data != null:
		return data.d.get("cards", {})
	return {}


func max_level() -> int:
	var lv: Array = _cards().get("levels", [])
	return lv.size() if lv.size() >= 2 else MAX_LEVEL


## 레벨 lv → lv+1 에 필요한 재료 (최고 레벨이면 0)
func cost_of_level(lv: int) -> int:
	if lv >= max_level():
		return 0
	var lvs: Array = _cards().get("levels", [])
	if lvs.size() >= 2:
		return int(lvs[lv - 1].get("cost", 0))
	return int(DEFAULT_COSTS[lv - 1])


func mult_of_level(lv: int) -> float:
	lv = clampi(lv, 1, max_level())
	var lvs: Array = _cards().get("levels", [])
	if lvs.size() >= 2:
		return float(lvs[lv - 1].get("mult", 1.0))
	return 1.0 + 0.06 * (lv - 1) + (0.10 if lv >= 6 else 0.0) + (0.15 if lv >= 12 else 0.0)


## 스킬 단계(0,1,2)의 해금 레벨
func unlock_level(char_id: String, tier: int) -> int:
	var list: Array = _cards().get("skills", {}).get(char_id, [])
	for e in list:
		if int(e.get("tier", -1)) == tier:
			return int(e.get("unlock", 1))
	return int(DEFAULT_UNLOCK[clampi(tier, 0, 2)])


## 캐릭터의 스킬 정보 목록 [{tier, skill, unlock, name, desc, icon}] (엑셀에 없으면 빈 배열)
func skills_of(char_id: String) -> Array:
	return _cards().get("skills", {}).get(char_id, [])


func _meta(key: String) -> int:
	return int(_cards().get("meta", {}).get(key, DEFAULT_META.get(key, 0)))


# ================================================================== 고정 API
## 카드 레벨 1..15
func card_level(char_id: String) -> int:
	return clampi(int(_levels.get(char_id, 1)), 1, max_level())


## 공격력 배율 (Lv1 = 1.0)
func card_mult(char_id: String) -> float:
	return mult_of_level(card_level(char_id))


## tier 0=기본 스킬, 1=Lv6 해금, 2=Lv12 해금
func skill_unlocked(char_id: String, tier: int) -> bool:
	return card_level(char_id) >= unlock_level(char_id, tier)


func best_wave() -> int:
	return _best_wave


## 한 판이 끝날 때 호출. 반환: {"shards": int, "best_wave": int, "new_best": bool, "total_shards": int}
## 코인(인게임 재화)은 재료 계산에 쓰지 않습니다(메타 재화와 분리).
func record_run(win: bool, wave: int, kills: int, _coins: int) -> Dictionary:
	var n := selected_dungeon
	var d: Dictionary = _dungeons.get(n, {"best_wave": 0, "cleared": false})
	var new_best := wave > int(d["best_wave"])
	var gain := _meta("shards_base") + wave * _meta("shards_per_wave") + int(kills / 30) * _meta("shards_per_30kills")
	if win:
		gain += _meta("shards_win_bonus")
	if new_best:
		gain += _meta("shards_new_best_bonus")
		d["best_wave"] = wave
	gain = int(round(clampi(gain, 0, _meta("shards_cap")) * dungeon_reward_mult(n)))
	var first_clear: bool = win and not bool(d["cleared"])
	var unlocked_next := 0
	if win:
		d["cleared"] = true
		if first_clear and n < dungeon_count():
			unlocked_next = n + 1
	_dungeons[n] = d
	_best_wave = maxi(_best_wave, wave)
	shards += gain
	runs += 1
	wins += 1 if win else 0
	total_kills += maxi(kills, 0)
	_quest_roll()
	_quest["runs"] = int(_quest["runs"]) + 1
	_quest["wave"] = maxi(int(_quest["wave"]), wave)
	save_now()
	changed.emit()
	run_recorded.emit({"win": win, "wave": wave, "kills": kills, "coins": _coins, "dungeon": n, "shards": gain,
			"play_sec": int(run_meta.get("play_sec", 0)), "units": run_meta.get("units", {})})
	run_meta = {}
	return {"shards": gain, "best_wave": _best_wave, "new_best": new_best, "total_shards": shards,
			"dungeon": n, "first_clear": first_clear, "unlocked_next": unlocked_next}


# ================================================================== 던전 (티어 10개)
## 던전 목록. Data.d["dungeons"](엑셀 '던전' 시트)가 있으면 그것, 없으면 기본 10개 이름.
## 항목: {"name": String, ...(난이도 등 엑셀 열 그대로)}
func dungeon_defs() -> Array:
	var data = get_node_or_null("/root/Data") if is_inside_tree() else null
	if data != null:
		var list = data.d.get("dungeons", [])
		if list is Array and not list.is_empty():
			return list
	var out: Array = []
	for nm in DEFAULT_DUNGEONS:
		out.append({"name": nm})
	return out


func dungeon_count() -> int:
	return dungeon_defs().size()


func dungeon_name(n: int) -> String:
	var defs := dungeon_defs()
	if n < 1 or n > defs.size():
		return ""
	return str(defs[n - 1].get("name", "던전 %d" % n))


func dungeon_unlocked(n: int) -> bool:
	return n == 1 or (n >= 2 and n <= dungeon_count() and dungeon_cleared(n - 1))


func dungeon_cleared(n: int) -> bool:
	return bool(_dungeons.get(n, {}).get("cleared", false))


func dungeon_best_wave(n: int) -> int:
	return int(_dungeons.get(n, {}).get("best_wave", 0))


func dungeon_reward_mult(n: int) -> float:
	return 1.0 + float(_meta("dungeon_reward_step_pct")) / 100.0 * (n - 1)


## 칭호 = 해금한 가장 높은 던전의 이름
func title() -> String:
	var top := 1
	for n in range(1, dungeon_count() + 1):
		if dungeon_unlocked(n):
			top = n
	return dungeon_name(top)


func cleared_count() -> int:
	var c := 0
	for n in range(1, dungeon_count() + 1):
		if dungeon_cleared(n):
			c += 1
	return c


## 계정 레벨 = 1 + 클리어한 던전 수 + 카드 레벨을 올린 합 (표시용)
func account_level() -> int:
	var lv := 1 + cleared_count()
	var data = get_node_or_null("/root/Data") if is_inside_tree() else null
	if data != null:
		for cid in data.d.get("characters", {}):
			lv += card_level(cid) - 1
	return lv


func _set_selected_dungeon(n: int) -> void:
	selected_dungeon = n if dungeon_unlocked(n) else 1
	if is_inside_tree():
		_queue_save()


# ================================================================== 오늘의 할 일
func _quest_roll() -> void:
	if str(_quest.get("date", "")) != today():
		_quest = {"date": today(), "runs": 0, "wave": 0, "claimed": []}


## [{id,text,need,reward,progress,done,claimed}]
func daily_quests() -> Array:
	_quest_roll()
	var out: Array = []
	for q in DAILY_QUESTS:
		var prog: int = int(_quest["runs"]) if q["id"] == "play" else int(_quest["wave"])
		out.append({"id": q["id"], "text": q["text"], "need": q["need"], "reward": q["reward"],
				"progress": mini(prog, int(q["need"])), "done": prog >= int(q["need"]),
				"claimed": (_quest["claimed"] as Array).has(q["id"])})
	return out


func quests_claimable() -> int:
	var c := 0
	for q in daily_quests():
		if q["done"] and not q["claimed"]:
			c += 1
	return c


## 보상 받기 — 받은 재료 수(조건 미달/이미 받음이면 0)
func claim_quest(id: String) -> int:
	for q in daily_quests():
		if q["id"] == id and q["done"] and not q["claimed"]:
			(_quest["claimed"] as Array).append(id)
			shards += int(q["reward"])
			save_now()
			changed.emit()
			return int(q["reward"])
	return 0


# ================================================================== 카드 강화
## {"ok": bool, "reason": String, "cost": int}
func can_upgrade(char_id: String) -> Dictionary:
	var lv := card_level(char_id)
	if lv >= max_level():
		return {"ok": false, "reason": "최고 레벨이에요", "cost": 0}
	var cost := cost_of_level(lv)
	if shards < cost:
		return {"ok": false, "reason": "재료가 %d개 부족해요" % (cost - shards), "cost": cost}
	return {"ok": true, "reason": "", "cost": cost}


func upgrade_card(char_id: String) -> bool:
	var c := can_upgrade(char_id)
	if not c["ok"]:
		return false
	shards -= int(c["cost"])
	_levels[char_id] = card_level(char_id) + 1
	save_now()
	changed.emit()
	return true


# ================================================================== 일일 접속 보상 · 튜토리얼 · 설정
func today() -> String:
	return Time.get_date_string_from_system()


func daily_available() -> bool:
	return daily_last != today()


## 오늘 첫 접속 보상을 받으면 받은 재료 수, 이미 받았으면 0
func claim_daily() -> int:
	if not daily_available():
		return 0
	var n := _meta("daily_bonus")
	daily_last = today()
	shards += n
	save_now()
	changed.emit()
	return n


func set_tutorial_done(v: bool = true) -> void:
	tutorial_done = v
	save_now()


## 설정값을 바꾼 뒤 호출 (슬라이더처럼 자주 바뀌면 잠깐 모아서 한 번에 저장)
func settings_changed() -> void:
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	bgm_volume = clampf(bgm_volume, 0.0, 1.0)
	default_speed = 2 if default_speed == 2 else 1
	changed.emit()
	_queue_save()


## 진동 (설정이 꺼져 있거나 지원 안 하면 아무 일 없음)
func buzz(ms: int = 30) -> void:
	if vibrate and (OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web")):
		Input.vibrate_handheld(ms)


# ================================================================== 저장 · 불러오기
func to_dict() -> Dictionary:
	return {"version": VERSION, "shards": shards, "best_wave": _best_wave, "runs": runs, "wins": wins,
			"total_kills": total_kills, "tutorial_done": tutorial_done,
			"daily": {"last_date": daily_last},
			"cards": _levels_out(),
			"dungeons": {"selected": selected_dungeon, "list": _dungeons_out()},
			"daily_quest": _quest,
			"settings": {"sfx_volume": sfx_volume, "bgm_volume": bgm_volume, "vibrate": vibrate,
					"default_speed": default_speed, "merge_popup": merge_popup}}


func _dungeons_out() -> Dictionary:
	var o := {}
	for k in _dungeons:
		o[str(k)] = {"best_wave": int(_dungeons[k]["best_wave"]), "cleared": bool(_dungeons[k]["cleared"])}
	return o


func _levels_out() -> Dictionary:
	var o := {}
	for k in _levels:
		o[k] = {"level": card_level(k)}
	return o


func _reset() -> void:
	sfx_volume = 1.0
	bgm_volume = 0.6
	vibrate = true
	default_speed = 1
	merge_popup = true
	shards = 0
	runs = 0
	wins = 0
	total_kills = 0
	tutorial_done = false
	daily_last = ""
	_best_wave = 0
	_levels = {}
	_dungeons = {}
	selected_dungeon = 1
	_quest = {"date": "", "runs": 0, "wave": 0, "claimed": []}


func load_game() -> void:
	_reset()
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		push_warning("저장 파일을 열 수 없음: %s" % save_path)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		_backup_broken()
		return
	apply_dict(parsed)


## 불러온 사전을 검증하며 적용 (버전 마이그레이션 자리). 이상한 값은 기본값/한계값으로 고칩니다.
func apply_dict(d: Dictionary) -> void:
	var ver := _int(d.get("version", 0), 0)
	# 마이그레이션 자리: if ver < 2: ... (지금은 v1 뿐. 버전 0 = 필드 이름이 같은 초기형으로 보고 그대로 읽음)
	if ver > VERSION:
		push_warning("더 새로운 버전의 저장 파일입니다. 아는 필드만 읽습니다.")
	shards = maxi(_int(d.get("shards", 0), 0), 0)
	_best_wave = maxi(_int(d.get("best_wave", 0), 0), 0)
	runs = maxi(_int(d.get("runs", 0), 0), 0)
	wins = maxi(_int(d.get("wins", 0), 0), 0)
	total_kills = maxi(_int(d.get("total_kills", 0), 0), 0)
	tutorial_done = _bool(d.get("tutorial_done", false), false)
	var daily = d.get("daily", {})
	daily_last = str(daily.get("last_date", "")) if daily is Dictionary else ""
	_levels = {}
	var cards = d.get("cards", {})
	if cards is Dictionary:
		for k in cards:
			var e = cards[k]
			var lv := _int(e.get("level", 1), 1) if e is Dictionary else 1
			_levels[str(k)] = clampi(lv, 1, MAX_LEVEL)
	var s = d.get("settings", {})
	if s is Dictionary:
		sfx_volume = clampf(_float(s.get("sfx_volume", 1.0), 1.0), 0.0, 1.0)
		bgm_volume = clampf(_float(s.get("bgm_volume", 0.6), 0.6), 0.0, 1.0)
		vibrate = _bool(s.get("vibrate", true), true)
		default_speed = 2 if _int(s.get("default_speed", 1), 1) == 2 else 1
		merge_popup = _bool(s.get("merge_popup", true), true)   # 옛 저장(필드 없음)은 기본 true
	_dungeons = {}
	var dg = d.get("dungeons", null)
	if dg is Dictionary and dg.get("list", null) is Dictionary:
		for k in dg["list"]:
			var n: int = str(k).to_int()
			var e = dg["list"][k]
			if n >= 1 and n <= 99 and e is Dictionary:
				_dungeons[n] = {"best_wave": maxi(_int(e.get("best_wave", 0), 0), 0), "cleared": _bool(e.get("cleared", false), false)}
	elif ver < 2 and _best_wave > 0:   # 옛 저장: 지금까지의 최고 웨이브를 1단계 기록으로
		_dungeons[1] = {"best_wave": _best_wave, "cleared": false}
	for n in _dungeons:
		_best_wave = maxi(_best_wave, int(_dungeons[n]["best_wave"]))
	selected_dungeon = 1
	if dg is Dictionary:
		var sel := _int(dg.get("selected", 1), 1)
		selected_dungeon = sel if dungeon_unlocked(sel) else 1
	_quest = {"date": "", "runs": 0, "wave": 0, "claimed": []}
	var dq = d.get("daily_quest", null)
	if dq is Dictionary:
		var cl: Array = []
		if dq.get("claimed", null) is Array:
			for x in dq["claimed"]:
				cl.append(str(x))
		_quest = {"date": str(dq.get("date", "")), "runs": maxi(_int(dq.get("runs", 0), 0), 0),
				"wave": maxi(_int(dq.get("wave", 0), 0), 0), "claimed": cl}
	changed.emit()


static func _int(v, fallback: int) -> int:
	if v is int or v is float:
		return int(v)
	return fallback


static func _bool(v, fallback: bool) -> bool:
	return v if v is bool else fallback


static func _float(v, fallback: float) -> float:
	if v is int or v is float:
		return float(v)
	return fallback


func _backup_broken() -> void:
	push_warning("저장 파일이 깨져 있어 백업하고 새로 시작합니다: %s" % save_path)
	if persist:
		DirAccess.copy_absolute(save_path, save_path + ".bak")


func _queue_save() -> void:
	if _flush_pending or not persist:
		return
	if not is_inside_tree():
		save_now()
		return
	_flush_pending = true
	get_tree().create_timer(0.4, true, false, true).timeout.connect(save_now)


## 바로 저장. 임시 파일에 쓴 뒤 이름을 바꿔서 쓰는 도중 꺼져도 파일이 깨지지 않게 합니다. 성공 여부 반환.
func save_now() -> bool:
	_flush_pending = false
	if not persist:
		return true
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("저장 실패(쓰기 불가): %s" % tmp)
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	var dir := DirAccess.open(save_path.get_base_dir())
	if dir == null:
		return false
	if dir.file_exists(save_path.get_file()):
		dir.remove(save_path.get_file())
	var err := dir.rename(tmp.get_file(), save_path.get_file())
	if err != OK:
		push_warning("저장 실패(이름 변경): %d" % err)
		return false
	return true
