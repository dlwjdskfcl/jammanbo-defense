extends Node
## 효과음 · 배경음악. 이벤트 이름(summon, merge_2 ...)은 sound_atlas.json 의 events 표를 따릅니다.

var players: Array = []
var next_player: int = 0
var bgm: AudioStreamPlayer
var last_time: Dictionary = {}
var cache: Dictionary = {}
var bgm_name: String = ""
var sfx_volume_db: float = 0.0
var audio_unlocked: bool = true    # 웹은 첫 터치/클릭 뒤에야 소리를 냅니다(브라우저 자동재생 정책)
var _pending_bgm: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	bgm = AudioStreamPlayer.new()
	bgm.volume_db = -10.0
	add_child(bgm)
	audio_unlocked = not OS.has_feature("web")
	call_deferred("_hook_save")


func _hook_save() -> void:
	var save = get_node_or_null("/root/Save")
	if save != null:
		save.changed.connect(apply_volumes)
	apply_volumes()


## Save 의 sfx_volume / bgm_volume(0..1)을 dB 로 반영. 배경음 기본값 0.6 이 예전 고정값(-10dB)과 같음.
func apply_volumes() -> void:
	var save = get_node_or_null("/root/Save")
	var sv: float = 1.0 if save == null else float(save.sfx_volume)
	var bv: float = 0.6 if save == null else float(save.bgm_volume)
	sfx_volume_db = linear_to_db(sv) if sv > 0.001 else -80.0
	bgm.volume_db = -10.0 + linear_to_db(bv / 0.6) if bv > 0.001 else -80.0


func _input(event: InputEvent) -> void:
	if audio_unlocked:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) 			or (event is InputEventKey and event.pressed):
		audio_unlocked = true
		if _pending_bgm != "":
			var n := _pending_bgm
			_pending_bgm = ""
			play_bgm(n)


func _stream(sound_id: String):
	if cache.has(sound_id):
		return cache[sound_id]
	var info: Dictionary = Data.sound.get("sounds", {}).get(sound_id, {})
	if info.is_empty():
		return null
	var path := "res://assets/sound/" + str(info["file"])
	if not ResourceLoader.exists(path):
		return null
	var s = load(path)
	cache[sound_id] = s
	return s


func play(event: String) -> void:
	if not audio_unlocked:
		return
	var sid: String = str(Data.sound.get("events", {}).get(event, event))
	var now := Time.get_ticks_msec()
	if now - int(last_time.get(sid, -1000)) < 60:
		return
	last_time[sid] = now
	var s = _stream(sid)
	if s == null:
		return
	var p: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	p.volume_db = sfx_volume_db
	p.stream = s
	p.play()


func play_bgm(name: String) -> void:
	if not audio_unlocked:
		_pending_bgm = name
		return
	if bgm_name == name and bgm.playing:
		return
	var s = _stream(name)
	if s == null:
		return
	if s is AudioStreamWAV:
		var w: AudioStreamWAV = s
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.data.size() / 2)   # 16bit mono
	bgm_name = name
	bgm.stream = s
	bgm.play()


func stop_bgm() -> void:
	_pending_bgm = ""
	bgm.stop()
	bgm_name = ""
