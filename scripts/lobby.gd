extends Control


func _ready():
	# Called every time the node is added to the scene.
	gamestate.connect("connection_failed", self, "_on_connection_failed")
	gamestate.connect("connection_succeeded", self, "_on_connection_success")
	gamestate.connect("player_list_changed", self, "refresh_lobby")
	gamestate.connect("game_ended", self, "_on_game_ended")
	gamestate.connect("game_error", self, "_on_game_error")

	gamestate.host_game()
	refresh_lobby()
	get_node("connect").hide()
	get_node("players").show()


#func _physics_process(delta):
#	if $players.visible:
#		if all_players_ready():
#			$players/start.disabled = false
#		else:
#			$players/start.disabled = true


#func _on_host_pressed():
#	if get_node("connect/v_box_container/h_box_container2/name").text == "":
#		get_node("connect/v_box_container/h_box_container5/error_label").text = "Invalid name!"
#		return
#
#	get_node("connect").hide()
#	get_node("players").show()
#	get_node("connect/v_box_container/h_box_container5/error_label").text = ""
#
#	var player_name = get_node("connect/v_box_container/h_box_container2/name").text
#	gamestate.host_game()
#	refresh_lobby()


#func _on_join_pressed():
#	if get_node("connect/v_box_container/h_box_container2/name").text == "":
#		get_node("connect/v_box_container/h_box_container5/error_label").text = "Invalid name!"
#		return
#
#	var ip = get_node("connect/v_box_container/h_box_container4/ip").text
#	if not ip.is_valid_ip_address():
#		get_node("connect/v_box_container/h_box_container5/error_label").text = "Invalid IPv4 address!"
#		return
#
#	get_node("connect/v_box_container/h_box_container5/error_label").text=""
#	get_node("connect/v_box_container/h_box_container2/host").disabled = true
#	get_node("connect/v_box_container/h_box_container4/join").disabled = true
#
#	var player_name = get_node("connect/v_box_container/h_box_container2/name").text
#	gamestate.join_game(ip, player_name)
#	# refresh_lobby() gets called by the player_list_changed signal


#func _on_connection_success():
#	get_node("connect").hide()
#	get_node("players").show()
#
#
#func _on_connection_failed():
#	get_node("connect/v_box_container/h_box_container2/host").disabled = false
#	get_node("connect/v_box_container/h_box_container4/join").disabled = false
#	get_node("connect/v_box_container/h_box_container5/error_label").set_text("Connection failed.")


func _on_game_ended():
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_node("connect").show()
	get_node("players").hide()
	get_node("connect/v_box_container/h_box_container2/host").disabled = false

	gamestate.host_game() # Host a new game
	refresh_lobby()
	get_node("connect").hide()
	get_node("players").show()


func _on_game_error(errtxt):
	get_node("error").dialog_text = errtxt
	get_node("error").popup_centered_minsize()


func refresh_lobby():
	var players = gamestate.get_player_list()
	players.sort()
	get_node("players/list").clear()
	for p in players:
		get_node("players/list").add_item(p)

	get_node("players/start").disabled = false


func _on_start_pressed():
	gamestate.begin_game()


mastersync func start_game(id):
	if id == gamestate.starter:
		gamestate.begin_game()


func _on_round_time_text_changed(new_text):
	gamestate.set_time(int(new_text))


func all_players_ready():
	return true
