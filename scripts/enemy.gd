extends Node2D
## 적: 순환 경로를 따라 계속 돕니다.

const U = preload("res://scripts/util.gd")

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
	position = game.path_pos(0.0)
	_last_x = position.x
	z_index = 3 if boss else 2


func _process(delta: float) -> void:
	if dead:
		return
	if slow_t > 0.0:
		slow_t -= delta
	if stun_t > 0.0:
		stun_t -= delta
	else:
		var sp := speed * (slow_f if slow_t > 0.0 else 1.0)
		dist += sp * delta
	position = game.path_pos(dist)
	if abs(position.x - _last_x) > 0.01:
		spr.flip_h = position.x < _last_x
	_last_x = position.x
	spr.modulate = Color(0.6, 0.8, 1.0) if slow_t > 0.0 else Color.WHITE


func take_hit(dmg: float) -> void:
	if dead:
		return
	hp -= dmg
	queue_redraw()
	if hp <= 0.0:
		dead = true
		game.on_enemy_died(self)


func _draw() -> void:
	if dead or hp >= max_hp:
		return
	var w := 40.0 if boss else 26.0
	var y := -34.0 if not boss else -52.0
	draw_rect(Rect2(-w / 2 - 1, y - 1, w + 2, 6), Color(0.13, 0.1, 0.13))
	draw_rect(Rect2(-w / 2, y, w * clamp(hp / max_hp, 0.0, 1.0), 4), Color(0.35, 0.85, 0.4))
