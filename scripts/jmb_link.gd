extends Node
## 잠만보 연동 (autoload "JmbLink") — 설계: 설정집/잠만보_연동_설계.md. 웹 내보내기에서만 동작, 그 밖(편집기·봇·--headless)은 전부 건너뜀.
## 서버와의 통신은 전부 web/shell.html 의 window.JMBDEF 가 함(카카오 로그인 토큰은 거기서만 읽고 이 스크립트로 오지 않음).
## 여기는 JMBDEF.call(id, op, JSON) 로 시작시키고 JMBDEF.take(id) 를 0.4초마다 물어 결과를 받는 얇은 다리일 뿐.
## 실패(로그인 안 함·네트워크·서버 오류)는 모두 '게스트'로 취급하고 게임은 그대로 진행. 아무것도 기다리지 않음.
##
## ★ 공개 계약 (다른 화면이 이 이름으로 씀 — 바꾸지 말 것)
##   logged_in() -> bool · nickname() -> String(게스트 "") · signal state_changed
##   request_rank(scope: "week"|"all"|"season") -> signal rank_loaded(data) , data = {"scope", "mine": {rank, nick, wave, score}, "top": [{rank, nick, wave, score}, …]}
##     (추가 키: "guest": true 로그인 안 함 · "cached": true 마지막으로 받은 값을 먼저 보여 줌 · "error": 문구 · rank 0 = 순위 없음)
##   open_jammanbo() — 웹: 새 창으로 잠만보, 그 외 OS.shell_open
## 판 기록: Save.run_recorded(info) 를 받아 서버에 제출(실패하면 shell 의 대기열 jmbdef_pending 에 두고 다음 로비 진입 때 재전송)
## 판 시작: Save.run_started(info) 를 받아 서버에 알림(게임 화면 game.tscn 이 열리면 0.6초 뒤 대신 보냄 — 신호가 없어도 동작)

signal state_changed
signal rank_loaded(data: Dictionary)
signal submit_finished(result: Dictionary)   # (추가) 기록 제출 결과 {"ok": bool, "score", "wave", "win", "new_best", "new_week_best", "msg"} — 결과 화면이 '저장됨' 표시에 쓸 수 있음

const JAMMANBO_URL := "https://dlwjdskfcl.github.io/jammanbo/"
const JAMMANBO_BETA_URL := "https://dlwjdskfcl.github.io/jammanbo-beta/"
const LOGIN_DELAY_SEC := 1.0           # 게임이 뜨고 나서 로그인 확인 (로딩을 방해하지 않게)
const POLL_SEC := 0.4
const START_FALLBACK_SEC := 0.6        # game.tscn 이 열린 뒤 Save.run_started 가 안 오면 대신 보내는 시간

var _web := false
var _nick := ""
var _message := ""                     # 마지막 서버 안내(예: "닉네임을 먼저 연결해 주세요")
var _login_done := false
var _seq := 0
var _jobs := {}                        # id -> {"op": String, "scope": String}
var _poll_left := 0.0
var _scene: Node = null
var _scene_gen := 0
var _scene_msec := 0
var _last_start_msec := -100000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # 결과 화면에서 트리가 멈춰 있어도 응답을 받음
	if not _web:
		_web = OS.has_feature("web")
	if _web and not bool(_js("typeof JMBDEF !== 'undefined'", true)):
		_web = false                           # 셸이 옛 버전 — 연동 없이 게스트로
	if not _web:
		set_process(false)
		return
	var sv := get_node_or_null("/root/Save")
	if sv != null:
		if sv.has_signal("run_started"):
			sv.connect("run_started", _on_run_started)
		if sv.has_signal("run_recorded"):
			sv.connect("run_recorded", _on_run_recorded)
	get_tree().create_timer(LOGIN_DELAY_SEC).timeout.connect(_login)


# ================================================================== 공개 계약
func logged_in() -> bool:
	return _nick != ""


func nickname() -> String:
	return _nick


## (추가) 서버가 준 마지막 안내 문구. 비어 있으면 없음
func message() -> String:
	return _message


func request_rank(scope: String) -> void:
	if not _web:
		_deliver_rank.call_deferred(_empty_rank(scope, {"guest": true}))
		return
	var cached = _js_json("JMBDEF.cachedRank(%s)" % _q(scope))
	if cached is Dictionary and not cached.is_empty():
		cached["cached"] = true
		_deliver_rank.call_deferred(_clean_rank(cached, scope))
	_call("rank", {"scope": scope}, {"scope": scope})


func open_jammanbo() -> void:
	if _web:
		var url := JAMMANBO_BETA_URL if str(_js("JMBDEF.env", true)) == "beta" else JAMMANBO_URL
		_js("window.open(%s,'_blank','noopener')" % _q(url))
	else:
		OS.shell_open(JAMMANBO_URL)


# ================================================================== 로그인 · 접속기록
func _login() -> void:
	_call("login")


func _set_nick(n: String) -> void:
	var changed := n != _nick or not _login_done
	_nick = n
	_login_done = true
	if changed:
		state_changed.emit()


# ================================================================== 판 시작 · 기록
func _selected_dungeon() -> int:
	var sv := get_node_or_null("/root/Save")
	if sv != null and "selected_dungeon" in sv:
		return maxi(int(sv.get("selected_dungeon")), 1)
	return 1


func _on_run_started(info: Dictionary = {}) -> void:
	_send_start(info)


func _send_start(info: Dictionary) -> void:
	_last_start_msec = Time.get_ticks_msec()
	_call("start", {"dungeon": maxi(int(info.get("dungeon", _selected_dungeon())), 1)})


func _on_run_recorded(info: Dictionary) -> void:
	var u: Dictionary = {}
	var raw = info.get("units", {})
	if raw is Dictionary:
		for g in range(1, 6):
			u["g%d" % g] = maxi(int(raw.get("g%d" % g, 0)), 0)
	var result := {"win": bool(info.get("win", false)), "wave": int(info.get("wave", 0)), "kills": int(info.get("kills", 0)),
			"coins": int(info.get("coins", 0)), "dungeon": maxi(int(info.get("dungeon", 1)), 1), "units": u}
	_call("submit", {"result": result})
	_call("visit")        # 게임 종료 시 접속기록 (기기당 30분 1회는 셸이 거름)


# ================================================================== 장면 감시 (Save.run_started 가 없을 때를 위한 대비)
func _watch_scene() -> void:
	var cs := get_tree().current_scene
	if cs == _scene:
		return
	_scene = cs
	_scene_gen += 1
	_scene_msec = Time.get_ticks_msec()
	if cs == null:
		return
	var path := cs.scene_file_path
	if path.ends_with("game.tscn"):
		_start_fallback(_scene_gen)
	elif path.ends_with("lobby.tscn") and _login_done:
		_call("flush")


func _start_fallback(gen: int) -> void:
	await get_tree().create_timer(START_FALLBACK_SEC).timeout
	if gen != _scene_gen or _last_start_msec >= _scene_msec - 1000:
		return        # 이미 신호로 보냈거나 다른 장면으로 넘어감
	_send_start({})


# ================================================================== 셸(JMBDEF) 호출
func _q(s: String) -> String:
	return JSON.stringify(s)        # JSON 글자는 그대로 JS 글자 리터럴


func _js(code: String, want_return: bool = false) -> Variant:
	return JavaScriptBridge.eval(code, want_return)


func _js_json(code: String) -> Variant:
	var raw = _js(code, true)
	return JSON.parse_string(raw) if raw is String else null


func _call(op: String, args: Dictionary = {}, extra: Dictionary = {}) -> void:
	_seq += 1
	var id := "j%d" % _seq
	var job := {"op": op}
	job.merge(extra)
	_jobs[id] = job
	_js("JMBDEF.call(%s,%s,%s)" % [_q(id), _q(op), _q(JSON.stringify(args))])


func _process(delta: float) -> void:
	_watch_scene()
	if _jobs.is_empty():
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = POLL_SEC
	for id in _jobs.keys():
		var res = _js_json("JMBDEF.take(%s)" % _q(id))
		if res == null:
			_finish(id, {"state": "err", "msg": "lost"})       # 셸이 모르는 요청(새로고침 등) → 포기
		elif res is Dictionary and str(res.get("state", "wait")) != "wait":
			_finish(id, res)


func _finish(id: String, res: Dictionary) -> void:
	var job: Dictionary = _jobs.get(id, {})
	_jobs.erase(id)
	var ok := str(res.get("state", "")) == "ok"
	var data: Dictionary = res.get("data", {}) if res.get("data", {}) is Dictionary else {}
	var msg := str(res.get("msg", ""))
	match str(job.get("op", "")):
		"login":
			if ok:
				_message = ""
				_set_nick(str(data.get("nick", "")))
				_call("flush")
				_call("visit")
			else:
				_message = "" if bool(res.get("net", false)) else msg
				_set_nick("")
				_call("visit")
			print("[JmbLink] 로그인 확인: ", "닉네임 있음" if _nick != "" else "게스트", " ", _message)
		"rank":
			if ok:
				_deliver_rank(_clean_rank(data, str(job.get("scope", "all"))))
			else:
				_deliver_rank(_empty_rank(str(job.get("scope", "all")), {"error": msg}))
		"submit":
			if ok and bool(data.get("skipped", false)):
				return        # 게스트 · 시작 확인값 없음: 기록하지 않음
			var out := {"ok": ok and not bool(data.get("queued", false)), "msg": msg}
			if data.get("queued", false):
				out["queued"] = true
			for k in ["score", "wave", "win", "playSec"]:
				if data.has(k):
					out[k] = data[k]
			out["new_best"] = bool(data.get("newBest", false))
			out["new_week_best"] = bool(data.get("newWeekBest", false))
			print("[JmbLink] 기록 제출: ", "저장됨" if out["ok"] else ("대기열" if out.has("queued") else "실패 " + msg))
			submit_finished.emit(out)
		"start":
			if not ok:
				print("[JmbLink] 판 시작 알림 실패(기록 없이 진행): ", msg)


# ================================================================== 랭킹 데이터 정리
func _rank_row(v: Variant) -> Dictionary:
	var d: Dictionary = v if v is Dictionary else {}
	return {"rank": int(d.get("rank", 0)), "nick": str(d.get("nick", "")), "wave": int(d.get("wave", 0)), "score": int(d.get("score", 0))}


func _clean_rank(data: Dictionary, scope: String) -> Dictionary:
	var top: Array = []
	var raw = data.get("top", [])
	if raw is Array:
		for r in raw:
			top.append(_rank_row(r))
	var out := {"scope": str(data.get("scope", scope)), "mine": _rank_row(data.get("mine", {})), "top": top}
	for k in ["guest", "cached", "error"]:
		if data.has(k):
			out[k] = data[k]
	return out


func _empty_rank(scope: String, extra: Dictionary = {}) -> Dictionary:
	var out := {"scope": scope, "mine": _rank_row({}), "top": []}
	out.merge(extra)
	return out


func _deliver_rank(data: Dictionary) -> void:
	rank_loaded.emit(data)
