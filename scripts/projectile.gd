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
var src                       # 쏜 유닛 (스킬 보정용, 죽었을 수 있음)
var extra: Dictionary = {}
var _rotate: bool = false


func setup(g, from: Vector2, tgt, dmg: float, st: Dictionary, source = null, ex: Dictionary = {}) -> void:
	game = g
	position = from
	target = tgt
	damage = dmg
	stat = st
	src = source
	extra = ex
	speed = float(Data.rule("projectile_speed", 420))
	last_pos = tgt.position
	_rotate = str(st["projectile"]) == "bark_wave"
	var sf = U.atlas_frames("projectiles", str(st["projectile"]), true)
	var missing: bool = sf == null
	if missing:       # 투사체 그림이 아직 없으면 hit_spark 로 대체
		sf = U.atlas_frames("projectiles", "hit_spark", true)
	if sf != null:
		spr = AnimatedSprite2D.new()
		spr.sprite_frames = sf
		add_child(spr)
		spr.play("default")
		if ex.get("punch", false):
			scale = Vector2(1.5, 1.5)
		elif missing:
			scale = Vector2(0.7, 0.7)
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
	if _rotate:
		rotation = to.angle()


func _arrive() -> void:
	if is_instance_valid(target) and not target.dead:
		var u = src if is_instance_valid(src) else null
		game.apply_hit(target, damage, stat, u, extra)
	game.spawn_fx("projectiles", "hit_spark", last_pos, 0.8)
	queue_free()
