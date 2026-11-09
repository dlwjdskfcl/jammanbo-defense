extends Control
## 타이틀/로비: 화면을 누르면 게임 시작.


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/title/title_screen.png")
	bg.size = Vector2(720, 1280)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	Sfx.play_bgm("bgm_menu")
	if "--autoplay" in OS.get_cmdline_user_args():   # 시뮬레이션용: 바로 게임 시작
		get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Sfx.play("button")
		get_tree().change_scene_to_file("res://scenes/game.tscn")
