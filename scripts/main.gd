extends Spatial


func _ready():
	var timer = $game_timer
	timer.set_wait_time(gamestate.game_time())
	timer.start()


func _on_game_timer_timeout():
	gamestate.end_game()
