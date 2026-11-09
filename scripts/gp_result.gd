extends RefCounted
## 결과 화면(승리/패배). game.gd 의 _end 에서 build() 로 만들어 ui 에 붙입니다.
## rec = Save.record_run() 결과 {shards, best_wave, new_best}

const U = preload("res://scripts/util.gd")
const R := "res://assets/screens/result/"
const INK := Color(0.23, 0.14, 0.19)


static func _label(text: String, size: int, pos: Vector2, box: Vector2, color: Color = Color.WHITE,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", max(2, int(size / 7)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func build(game, win: bool, reason: String, rec: Dictionary) -> Control:
	var layer := Control.new()
	layer.size = Vector2(720, 1280)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.size = Vector2(720, 1280)
	layer.add_child(dim)
	# 배경 효과: 승리=색종이, 패배=비
	var fx := AnimatedSprite2D.new()
	var sf := U.frames("result_fx|" + ("confetti" if win else "rain"),
			[R + "fx_%s_0.png" % ("confetti" if win else "rain"), R + "fx_%s_1.png" % ("confetti" if win else "rain"),
			R + "fx_%s_2.png" % ("confetti" if win else "rain"), R + "fx_%s_3.png" % ("confetti" if win else "rain")],
			8.0, true)
	fx.sprite_frames = sf
	fx.centered = false
	fx.scale = Vector2(1.125, 1.125)
	fx.position = Vector2(0, 120)
	layer.add_child(fx)
	fx.play("default")

	var banner := TextureRect.new()
	banner.texture = U.tex(R + "banner_%s.png" % ("victory" if win else "defeat"))
	banner.position = Vector2(40, 170)
	layer.add_child(banner)
	var panel := TextureRect.new()
	panel.texture = U.tex(R + "panel.png")
	panel.position = Vector2(70, 390)
	layer.add_child(panel)

	var star_n := 0
	if win:
		star_n = 3 if game.enemies.size() < int(Data.rule("field_limit", 60)) * 0.3 else 2
	var stars := TextureRect.new()
	stars.texture = U.tex(R + "stars_%d.png" % star_n)
	stars.position = Vector2(70 + 182, 408)
	layer.add_child(stars)
	layer.add_child(_label("웨이브 %d / %d  ·  처치 %d" % [game.wave, int(Data.rule("total_waves", 40)), game.kills], 32,
			Vector2(70, 490), Vector2(580, 50)))
	if reason != "":
		var r := _label(reason, 22, Vector2(90, 538), Vector2(540, 36), Color(1, 0.7, 0.7))
		layer.add_child(r)
	# 카드 조각 보상
	var shards := int(rec.get("shards", 0))
	var sh := TextureRect.new()
	sh.texture = U.tex(R + "icon_card_shard.png")
	sh.scale = Vector2(2, 2)
	sh.position = Vector2(190, 596)
	layer.add_child(sh)
	layer.add_child(_label("카드 조각 +%d" % shards, 36, Vector2(268, 592), Vector2(360, 64), Color(1, 0.9, 0.5),
			HORIZONTAL_ALIGNMENT_LEFT))
	var best := int(rec.get("best_wave", game.wave))
	var best_txt := "최고 기록  %d 웨이브" % best
	layer.add_child(_label(best_txt, 26, Vector2(70, 670), Vector2(580, 40), Color(0.85, 0.9, 1.0)))
	if bool(rec.get("new_best", false)):
		var nb := _label("신기록!", 34, Vector2(70, 708), Vector2(580, 44), Color(1, 0.6, 0.8))
		layer.add_child(nb)
		var tw := nb.create_tween().set_loops()
		tw.tween_property(nb, "modulate:a", 0.4, 0.5)
		tw.tween_property(nb, "modulate:a", 1.0, 0.5)
	layer.add_child(game._button("res://assets/td/ui/btn_green_big.png", "다시 하기", Vector2(100, 830), Vector2(240, 96),
			game._restart, 34))
	layer.add_child(game._button("res://assets/td/ui/btn_blue_big.png", "로비로", Vector2(380, 830), Vector2(240, 96),
			game._to_lobby, 34))
	return layer
