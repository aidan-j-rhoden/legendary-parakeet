extends Node

# Default game port
const DEFAULT_PORT = 27015

# Max number of players
const MAX_PEERS = 4

# Names for remote players in id:name format
var players = {}
var not_registered_players = []
var starter # who gets to tell the server to start the game

var round_time = 300

#The main scene
var main

# Signals to let lobby GUI know what's going on
signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what)


func _player_connected(id): # Callback from SceneTree
#	var player_name = rpc_id(id, "get_name")
#	print(player_name)
#	register_player(id, player_name)
	not_registered_players.append(id)


master func player_set(name):
	var sender = get_tree().get_rpc_sender_id()
	for id in not_registered_players:
		if id == sender:
			register_player(sender, name)
			not_registered_players.erase(sender)
			break


func _player_disconnected(id): # Callback from SceneTree
	if has_node("/root/world"): # Game is in progress (needs to be changed to /root/main to work, but I don't want it too)
		emit_signal("game_error", "Player " + players[id] + " disconnected.")
		end_game()
	else: # Game is not in progres.
		unregister_player(id)
		if players.size() == 0:
			end_game()
		else:
			for p_id in players:
				# Erase in the server
				rpc_id(p_id, "unregister_player", id)


func register_player(id, new_player_name): # Lobby management functions
	print("regestered player: " + new_player_name)
	for p_id in players: # Then, for each remote player
		rpc_id(id, "register_player", p_id, players[p_id]) # Send each player to new dude
		rpc_id(p_id, "register_player", id, new_player_name) # Send new dude to each player

	players[id] = new_player_name
	emit_signal("player_list_changed")
	if players.size() == 1:
		starter = new_player_name


func unregister_player(id):
	players.erase(id)
	emit_signal("player_list_changed")
	if has_node("/root/main"):
		if has_node("/root/main/players/" + str(id)):
			get_node("/root/main/players/" + str(id)).queue_free()


remote func pre_start_game(spawn_points):
	# Change scene
	main = load("res://scenes/main.tscn").instance()
	get_tree().get_root().add_child(main)
#	get_tree().get_root().get_node("main").hide()
	main.set_network_master(1)

	get_tree().get_root().get_node("lobby").hide()

	var player_scene = load("res://scenes/player/player.tscn")

	for p_id in spawn_points:
		var spawn_pos = main.get_node("spawn_points/" + str(spawn_points[p_id])).global_transform.origin
		var player = player_scene.instance()

		player.set_name(str(p_id)) # Use unique ID as node name
		player.set_network_master(p_id) #set unique id as master

		main.get_node("players").add_child(player)
		player.global_transform.origin = spawn_pos

	if players.size() == 0:
		post_start_game()


remote func post_start_game():
	get_tree().set_pause(false) # Unpause and unleash the game!


var players_ready = []


master func ready_to_start(id):
	assert(get_tree().is_network_server())

	if not id in players_ready:
		players_ready.append(id)

	if players_ready.size() == players.size():
		for p in players:
			print(str(p) + " is ready!")
			rpc_id(p, "post_start_game")
#		post_start_game()


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
#	get_tree().set_network_peer(null) # Causes problems, but it seems necessary
	if has_node("/root/main"): # Game is in progress
		# End it
		get_node("/root/main").queue_free()

	emit_signal("game_ended")
	players.clear()


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
