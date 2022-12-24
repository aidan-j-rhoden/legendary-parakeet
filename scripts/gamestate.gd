extends Node

# Default game port
const DEFAULT_PORT = 27015

# Max number of players
const MAX_PEERS = 12

# Names for remote players in id:name format
var players = {}
var starter

var round_time = 300

#The main scene
var main

# Signals to let lobby GUI know what's going on
signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what)


func _player_connected(_id): # Callback from SceneTree
	pass


func _player_disconnected(id): # Callback from SceneTree
	if has_node("/root/world"): # Game is in progress
		emit_signal("game_error", "Player " + players[id] + " disconnected.")
		end_game()
	else: # Game is not in progres.
		unregister_player(id)
		for p_id in players:
			# Erase in the server
			rpc_id(p_id, "unregister_player", id)


# Lobby management functions
remote func register_player(id, new_player_name):
	print("regestered player: " + new_player_name)
#	rpc_id(id, "register_player", 1, player_name) # Send myself to new dude
	for p_id in players: # Then, for each remote player
		rpc_id(id, "register_player", p_id, players[p_id]) # Send each player to new dude
		rpc_id(p_id, "register_player", id, new_player_name) # Send new dude to each player

	players[id] = new_player_name
	emit_signal("player_list_changed")
	if players.size() == 1:
		starter = new_player_name


remote func unregister_player(id):
	players.erase(id)
	emit_signal("player_list_changed")


remote func pre_start_game(spawn_points):
	# Change scene
	main = load("res://scenes/main.tscn").instance()
	get_tree().get_root().add_child(main)
#	get_tree().get_root().get_node("main").hide()

	#get_tree().get_root().get_node("lobby").hide()

	var player_scene = load("res://scenes/player/player.tscn")

	for p_id in spawn_points:
		var spawn_pos = main.get_node("spawn_points/" + str(spawn_points[p_id])).global_transform.origin
		var player = player_scene.instance()

		player.set_name(str(p_id)) # Use unique ID as node name
		player.set_network_master(p_id) #set unique id as master
		player.global_transform.origin = spawn_pos

		main.get_node("players").add_child(player)

	if players.size() == 0:
		post_start_game()


remote func post_start_game():
	get_tree().set_pause(false) # Unpause and unleash the game!


var players_ready = []


remote func ready_to_start(id):
	assert(get_tree().is_network_server())

	if not id in players_ready:
		players_ready.append(id)

	if players_ready.size() == players.size():
		for p in players:
			rpc_id(p, "post_start_game")
		post_start_game()


func host_game():
	var host = NetworkedMultiplayerENet.new()
	host.create_server(DEFAULT_PORT, MAX_PEERS)
	get_tree().set_network_peer(host)


func get_player_list():
	return players.values()


func begin_game():
	assert(get_tree().is_network_server())

	# Create a dictionary with peer id and respective spawn points, could be improved by randomizing
	var spawn_points = {}
	var spawn_point_idx = 0
	for p in players:
		spawn_points[p] = spawn_point_idx
		spawn_point_idx += 1
	# Call to pre-start game with the spawn points
	for p in players:
		rpc_id(p, "pre_start_game", spawn_points)

	pre_start_game(spawn_points)


func end_game():
	if has_node("/root/world"): # Game is in progress
		# End it
		get_node("/root/world").queue_free()
		get_tree().get_root().get_node(main).queue_free()

	emit_signal("game_ended")
	players.clear()
	get_tree().set_network_peer(null) # End networking


func _ready():
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self,"_player_disconnected")
	get_tree().connect("connected_to_server", self, "_connected_ok")
	get_tree().connect("connection_failed", self, "_connected_fail")
	get_tree().connect("server_disconnected", self, "_server_disconnected")


func set_time(time):
	round_time = time


func game_time():
	return int(round_time)
