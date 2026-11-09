extends Node2D
## 투사체: 대상에게 날아가 맞으면 피해/효과를 적용합니다.

const U = preload("res://scripts/util.gd")

var game
var target
var damage: float = 0.0
var stat: Dictionary = {}
var speed: float = 420.0
var last_pos: Vector2 = Vector2.ZERO
var spr: AnimatedSprite2D


func setup(g, from: Vector2, tgt, dmg: float, st: Dictionary) -> void:
	game = g
	position = from
	target = tgt
	damage = dmg
	stat = st
	speed = float(Data.rule("projectile_speed", 420))
	last_pos = tgt.position
	var sf = U.atlas_frames("projectiles", str(st["projectile"]), true)
	if sf != null:
		spr = AnimatedSprite2D.new()
		spr.sprite_frames = sf
		add_child(spr)
		spr.play("default")
	z_index = 5


func _process(delta: float) -> void:
	if is_instance_valid(target) and not target.dead:
		last_pos = target.position
	var to := last_pos - position
	var step := speed * delta
	if to.length() <= step:
		_arrive()
		return
	position += to.normalized() * step
	if str(stat["projectile"]) == "bark_wave":
		rotation = to.angle()


func _arrive() -> void:
	if is_instance_valid(target) and not target.dead:
		game.apply_hit(target, damage, stat)
	game.spawn_fx("projectiles", "hit_spark", last_pos, 0.8)
	queue_free()
