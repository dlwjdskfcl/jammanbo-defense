extends Node
## 효과음 · 배경음악. 이벤트 이름(summon, merge_2 ...)은 sound_atlas.json 의 events 표를 따릅니다.

var players: Array = []
var next_player: int = 0
var bgm: AudioStreamPlayer
var last_time: Dictionary = {}
var cache: Dictionary = {}
var bgm_name: String = ""
var sfx_volume_db: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	bgm = AudioStreamPlayer.new()
	bgm.volume_db = -10.0
	add_child(bgm)


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
	bgm.stop()
	bgm_name = ""
