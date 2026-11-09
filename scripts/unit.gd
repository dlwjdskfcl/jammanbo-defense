extends Node2D
## 타워 유닛 (캐릭터 + 등급). 수치는 data/game_data.json 의 characters.<id>.stat 에서 옵니다.

const U = preload("res://scripts/util.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")

var game
var char_id: String = ""
var grade: int = 1
var slot: int = -1
var stat: Dictionary = {}
var damage: float = 0.0
var interval: float = 1.0
var range_px: float = 0.0
var cd: float = 0.0
var spr: AnimatedSprite2D


func setup(g, cid: String, gr: int, slot_index: int) -> void:
	game = g
	char_id = cid
	grade = gr
	slot = slot_index
	stat = Data.d["characters"][cid]["stat"]
	damage = float(stat["damage"]) * Data.grade_mult(gr)
	var min_interval: float = 1.0 / float(Data.rule("max_attack_speed", 8))
	interval = max(float(stat["interval"]), min_interval)
	range_px = float(stat["range_tiles"]) * game.T
	cd = randf() * interval
	spr = AnimatedSprite2D.new()
	spr.sprite_frames = U.unit_frames(cid, gr)
	add_child(spr)
	spr.play("idle")
	spr.animation_finished.connect(_on_anim_finished)


func _on_anim_finished() -> void:
	if spr.animation == "attack":
		spr.play("idle")


func _process(delta: float) -> void:
	cd -= delta
	if cd > 0.0:
		return
	var target = game.find_target(self)
	if target == null:
		cd = 0.05
		return
	cd = interval
	fire(target)


func fire(target) -> void:
	spr.play("attack")
	Sfx.play("attack_" + char_id)
	var p := ProjectileScript.new()
	game.proj_node.add_child(p)
	p.setup(game, position, target, damage, stat)
