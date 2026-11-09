extends RefCounted
## 공용 도우미 (preload 해서 사용: const U = preload("res://scripts/util.gd"))

static var _tex_cache: Dictionary = {}
static var _frames_cache: Dictionary = {}


static func tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


## PNG 프레임 목록 → SpriteFrames (같은 key 는 캐시)
static func frames(key: String, paths: Array, fps: float, loop: bool, anim: String = "default") -> SpriteFrames:
	var ck := key + "|" + anim
	if _frames_cache.has(ck):
		return _frames_cache[ck]
	var sf := SpriteFrames.new()
	if sf.has_animation("default") and anim != "default":
		sf.remove_animation("default")
	if not sf.has_animation(anim):
		sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for p in paths:
		sf.add_frame(anim, tex(p))
	_frames_cache[ck] = sf
	return sf


## 유닛 한 칸(링+캐릭터+별) 프레임: idle 4장 + attack 3장
static func unit_frames(char_id: String, grade: int) -> SpriteFrames:
	var ck := "unit|%s|%d" % [char_id, grade]
	if _frames_cache.has(ck):
		return _frames_cache[ck]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for pair in [["idle", 4, 4.0, true], ["attack", 3, 14.0, false]]:
		var name: String = pair[0]
		sf.add_animation(name)
		sf.set_animation_speed(name, pair[2])
		sf.set_animation_loop(name, pair[3])
		for i in int(pair[1]):
			sf.add_frame(name, tex("res://assets/td/units/%s/g%d_%s_%d.png" % [char_id, grade, name, i]))
	_frames_cache[ck] = sf
	return sf


static func atlas_frames(group: String, id: String, loop: bool) -> SpriteFrames:
	var info: Dictionary = Data.atlas.get(group, {}).get(id, {})
	if info.is_empty():
		return null
	var paths: Array = []
	for f in info["frames"]:
		paths.append("res://assets/td/" + str(f))
	return frames("atlas|%s|%s" % [group, id], paths, float(info.get("fps", 8)), loop)
