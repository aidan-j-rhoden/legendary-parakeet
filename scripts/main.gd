extends Spatial


func _ready():
	var timer = $game_timer
	timer.set_wait_time(gamestate.game_time())
	timer.start()
	var window_size = OS.window_size
	var minsize = Vector2(window_size.x * 200 / window_size.y, 200.0)
	get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_VIEWPORT, SceneTree.STRETCH_ASPECT_EXPAND, minsize)


func _on_game_timer_timeout():
	get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_VIEWPORT, SceneTree.STRETCH_ASPECT_EXPAND, Vector2(OS.window_size.x, OS.window_size.y))
	gamestate.end_game()
