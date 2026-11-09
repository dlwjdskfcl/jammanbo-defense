extends RefCounted
## 소환/합성 확률 계산 (순수 함수 — settings_panel '확률 보기'와 합성 팝업이 같이 읽음).
## 분류 키: pet(반려) dealer(딜러) support(서포터) dud(꽝)

const KINDS := ["pet", "dealer", "support", "dud"]
const KIND_NAMES := {"pet": "반려", "dealer": "딜러", "support": "서포터", "dud": "꽝"}
## 아직 효과를 구현하지 못한 유닛은 여기에 id 를 넣으면 소환/합성 풀에서 가중치 0 으로 취급(현재 14종 모두 구현 → 비어 있음)
const EXCLUDED_UNITS: Array = []


static func _w(id: String, key: String) -> float:
	if id in EXCLUDED_UNITS:
		return 0.0
	return float(Data.unit_def(id).get(key, 0))


static func use_pool() -> bool:
	return int(Data.rule("use_unit_pool", 1)) != 0 and not Data.units.is_empty()


## 소환 확률 {id: 0..1}. exclude_kind 로 분류 하나를 뺄 수 있음(소환 보호)
static func summon_probs(exclude_kind: String = "") -> Dictionary:
	var out: Dictionary = {}
	var total := 0.0
	if not use_pool():
		var pets: Array = Data.d.get("characters", {}).keys()
		for k in pets:
			out[str(k)] = 1.0 / pets.size()
		return out
	for id in Data.units.keys():
		var w := _w(str(id), "summon_weight")
		if exclude_kind != "" and str(Data.units[id].get("kind", "")) == exclude_kind:
			w = 0.0
		if w > 0.0:
			out[str(id)] = w
			total += w
	for id in out.keys():
		out[id] = float(out[id]) / total
	return out


## 합성 결과 확률 {id: 0..1}. to_grade = 결과 등급, lucky = 대박(꽝 없음, 소환 분포) 여부, dud_guard = 꽝 천장 발동(꽝 없음)
static func merge_probs(to_grade: int, lucky: bool = false, dud_guard: bool = false) -> Dictionary:
	if not use_pool():
		return summon_probs()
	if lucky:
		return summon_probs()
	var dud_rate := 0.0
	if not dud_guard:
		dud_rate = float(Data.rule("dud_rate_g%d" % to_grade, 0.0))
	var out: Dictionary = {}
	var duds: Array = []
	var total := 0.0
	for id in Data.units.keys():
		var def: Dictionary = Data.units[id]
		if bool(def.get("dud", false)):
			duds.append(str(id))
		else:
			var w := _w(str(id), "merge_weight")
			if w > 0.0:
				out[str(id)] = w
				total += w
	for id in out.keys():
		out[id] = float(out[id]) / total * (1.0 - dud_rate)
	for id in duds:
		out[id] = dud_rate / max(1, duds.size())
	return out


## 분류별 합계 {kind: 0..1}
static func by_kind(probs: Dictionary) -> Dictionary:
	var out: Dictionary = {"pet": 0.0, "dealer": 0.0, "support": 0.0, "dud": 0.0}
	for id in probs.keys():
		var k := str(Data.unit_def(str(id)).get("kind", "pet"))
		out[k] = float(out.get(k, 0.0)) + float(probs[id])
	return out


## 표시용 표: [{id, name, kind, pct}] (pct 는 0..100, 소수 1자리) — 합성이면 to_grade>0
static func table(to_grade: int = 0) -> Array:
	var probs := merge_probs(to_grade) if to_grade > 0 else summon_probs()
	var rows: Array = []
	for id in probs.keys():
		rows.append({"id": id, "name": Data.unit_name(str(id)), "kind": str(Data.unit_def(str(id)).get("kind", "pet")),
				"pct": snappedf(float(probs[id]) * 100.0, 0.1)})
	return rows


## 가중 추첨 (probs: {id: p})
static func pick(probs: Dictionary, rng: RandomNumberGenerator) -> String:
	var x := rng.randf()
	var last := ""
	for id in probs.keys():
		last = str(id)
		x -= float(probs[id])
		if x <= 0.0:
			return last
	return last
