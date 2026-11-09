extends Node2D
## 적: 순환 경로를 따라 계속 돕니다.

const U = preload("res://scripts/util.gd")
const BadgesScript = preload("res://scripts/gp_badges.gd")

var game
var id: String = ""
var hp: float = 1.0
var max_hp: float = 1.0
var speed: float = 50.0
var reward: int = 1
var boss: bool = false
var flying: bool = false
var dist: float = 0.0
var slow_t: float = 0.0
var slow_f: float = 1.0
var stun_t: float = 0.0
var dead: bool = false
var spr: AnimatedSprite2D
var _last_x: float = 0.0
var flash_t: float = 0.0
var badges: Node2D
var _bar_w: float = 26.0
var _bar_y: float = -34.0
var mark_t: float = 0.0     # 룰북 표식: 받는 피해 증가 남은 시간
var mark_v: float = 0.0
var killer = null          # 마지막으로 때린 유닛(coin_kill 판정)
var _tint: int = 0   # 0 보통 1 둔화 2 피격


func setup(g, eid: String, hp_value: float, reward_value: int) -> void:
	game = g
	id = eid
	var info: Dictionary = Data.d["enemies"][eid]
	hp = hp_value
	max_hp = hp_value
	speed = float(info["speed"])
	reward = reward_value
	boss = bool(info["boss"])
	flying = bool(info["flying"])
	spr = AnimatedSprite2D.new()
	spr.sprite_frames = U.atlas_frames("enemies", eid, true)
	add_child(spr)
	spr.play("default")
	# 체력바/상태 아이콘 위치: 스프라이트 크기(일반 48, 정예 64, 보스 96~144)에 맞춤
	var tex: Texture2D = spr.sprite_frames.get_frame_texture("default", 0) if spr.sprite_frames != null else null
	var sz := Vector2(48, 48) if tex == null else tex.get_size()
	_bar_w = clamp(sz.x * 0.55, 26.0, 70.0)
	_bar_y = -sz.y / 2.0 - 8.0
	badges = BadgesScript.new()
	badges.position = Vector2(0, _bar_y - 12.0)
	badges.z_index = 2
	add_child(badges)
	position = game.path_pos(0.0)
	_last_x = position.x
	z_index = 3 if boss else 2


func _process(delta: float) -> void:
	if dead:
		return
	if slow_t > 0.0:
		slow_t -= delta
	if mark_t > 0.0:
		mark_t -= delta
	if stun_t > 0.0:
		stun_t -= delta
	elif game.freeze_t > 0.0 and not (boss and game.freeze_t <= game.freeze_total * 0.5):
		pass     # 모래시계 이벤트: 정지(보스는 절반만)
	else:
		var sp := speed * (slow_f if slow_t > 0.0 else 1.0)
		if game.global_slow_t > 0.0:
			sp *= 1.0 - game.global_slow_f
		dist += sp * delta
	position = game.path_pos(dist)
	if abs(position.x - _last_x) > 0.01:
		spr.flip_h = position.x < _last_x
	_last_x = position.x
	var tint := 1 if slow_t > 0.0 else 0
	if flash_t > 0.0:
		flash_t -= delta
		tint = 2
		spr.offset = Vector2(randf_range(-2.0, 2.0), 0.0)
	elif _tint == 2:
		spr.offset = Vector2.ZERO
	if tint != _tint:
		_tint = tint
		spr.modulate = [Color.WHITE, Color(0.6, 0.8, 1.0), Color(2.2, 2.2, 2.2)][tint]
	badges.set_on("debuff_slow", slow_t > 0.0)
	badges.set_on("debuff_stun", stun_t > 0.0)


func take_hit(dmg: float, color: Color = Color.WHITE) -> void:
	if dead:
		return
	if mark_t > 0.0:
		dmg *= 1.0 + mark_v
	hp -= dmg
	flash_t = 0.07
	game.add_floater(position, dmg, color, boss)
	queue_redraw()
	if hp <= 0.0:
		dead = true
		game.on_enemy_died(self)


func _draw() -> void:
	if dead or hp >= max_hp:
		return
	var w := _bar_w
	var y := _bar_y
	draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 6), Color(0.13, 0.1, 0.13))
	draw_rect(Rect2(-w / 2, y, w * clamp(hp / max_hp, 0.0, 1.0), 4), Color(0.35, 0.85, 0.4))
