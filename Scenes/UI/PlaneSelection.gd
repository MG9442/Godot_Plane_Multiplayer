extends Control

const PlayerSelectionCard = preload("res://Scenes/UI/PlayerSelectionCard.tscn")

@onready var player_container = $ScrollContainer/PlayerContainer
@onready var ready_button = $ReadyButton
@onready var status_label = $StatusLabel

# Track player selections and ready states
var player_data = {}  # {player_id: {name: "", plane_index: 0, is_ready: false}}
var player_cards = {}  # {player_id: PlayerSelectionCard}
var local_player_id: int
var local_player_ready: bool = false


func _ready():
	local_player_id = multiplayer.get_unique_id()
	
	# Set up multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Small delay to ensure multiplayer is fully set up
	await get_tree().create_timer(0.1).timeout
	
	# Initialize all connected players
	if multiplayer.is_server():
		# Server adds itself
		add_player(local_player_id, "Host")
	else:
		# Client adds itself locally first
		add_player(local_player_id, "Player" + str(local_player_id))
		
		# Then register with server
		register_player.rpc_id(1, local_player_id, "Player" + str(local_player_id))
		
		# Request all other players from server
		await get_tree().create_timer(0.1).timeout
		request_player_data.rpc_id(1)


# Called when a new player connects
func _on_player_connected(id):
	print("Player connected to selection: ", id)


func _on_player_disconnected(id):
	print("Player disconnected from selection: ", id)
	remove_player(id)


# RPC to register a new player with the server
@rpc("any_peer")
func register_player(id: int, p_name: String):
	if not multiplayer.is_server():
		return
	
	print("Server: Registering player ", id, " with name ", p_name)
	add_player(id, p_name)
	
	# Sync this player to all clients (including the one who just joined)
	sync_player_added.rpc(id, p_name)


# RPC to sync player addition to all clients
@rpc("authority", "call_local")
func sync_player_added(id: int, p_name: String):
	# Don't add if we already have this player
	if player_data.has(id):
		return
	
	add_player(id, p_name)


# Request all current player data (for late joiners)
@rpc("any_peer")
func request_player_data():
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Send all current players to the requester
	for player_id in player_data:
		var data = player_data[player_id]
		sync_player_added.rpc_id(sender_id, player_id, data.name)
		sync_plane_selection.rpc_id(sender_id, player_id, data.plane_index)
		if data.is_ready:
			sync_ready_state.rpc_id(sender_id, player_id, true)


# Add a player to the selection screen
func add_player(id: int, p_name: String):
	if player_data.has(id):
		print("Player ", id, " already exists, skipping")
		return
	
	print("Adding player ", id, " (", p_name, ") - Local player is: ", local_player_id)
	
	# Initialize player data
	player_data[id] = {
		"name": p_name,
		"plane_index": 0,
		"is_ready": false
	}
	
	# Create selection card
	var card = PlayerSelectionCard.instantiate()
	player_container.add_child(card)
	player_cards[id] = card
	
	var is_local = (id == local_player_id)
	print("Is local player: ", is_local)
	card.setup(id, p_name, is_local)
	
	# Connect signals only for local player
	if is_local:
		card.plane_changed.connect(_on_local_plane_changed)
	
	update_status()


# Remove a player from the selection screen
func remove_player(id: int):
	if not player_data.has(id):
		return
	
	player_data.erase(id)
	
	if player_cards.has(id):
		player_cards[id].queue_free()
		player_cards.erase(id)
	
	update_status()


# When local player changes their plane selection
func _on_local_plane_changed(player_id: int, plane_index: int):
	# Update locally
	player_data[local_player_id].plane_index = plane_index
	
	# Sync to all other players
	update_plane_selection.rpc(local_player_id, plane_index)


# RPC to update plane selection
@rpc("any_peer", "call_local")
func update_plane_selection(player_id: int, plane_index: int):
	if not multiplayer.is_server():
		# Client receives update
		if player_data.has(player_id):
			player_data[player_id].plane_index = plane_index
			if player_cards.has(player_id):
				player_cards[player_id].set_plane_index(plane_index)
	else:
		# Server relays to all clients
		if player_data.has(player_id):
			player_data[player_id].plane_index = plane_index
			if player_cards.has(player_id):
				player_cards[player_id].set_plane_index(plane_index)
		
		# Broadcast to all other clients
		sync_plane_selection.rpc(player_id, plane_index)


# RPC to sync plane selection
@rpc("authority")
func sync_plane_selection(player_id: int, plane_index: int):
	if player_data.has(player_id):
		player_data[player_id].plane_index = plane_index
		if player_cards.has(player_id):
			player_cards[player_id].set_plane_index(plane_index)


# When local player clicks ready
func _on_ready_button_pressed():
	local_player_ready = !local_player_ready
	
	print("Local player ready state changed to: ", local_player_ready)
	
	# Update button
	if local_player_ready:
		ready_button.text = "Not Ready"
	else:
		ready_button.text = "Ready"
	
	# Update local card
	if player_cards.has(local_player_id):
		player_cards[local_player_id].set_ready(local_player_ready)
	
	# Update data
	player_data[local_player_id].is_ready = local_player_ready
	
	# Sync to server (which will relay to all clients)
	if multiplayer.is_server():
		# Server updates and broadcasts
		sync_ready_state.rpc(local_player_id, local_player_ready)
		check_all_ready()
	else:
		# Client sends to server
		update_ready_state.rpc_id(1, local_player_id, local_player_ready)
	
	update_status()


# RPC to update ready state (from client to server)
@rpc("any_peer")
func update_ready_state(player_id: int, is_ready: bool):
	# This should only run on the server
	if not multiplayer.is_server():
		return
	
	print("Server received ready state for player ", player_id, ": ", is_ready)
	
	# Update server's data
	if player_data.has(player_id):
		player_data[player_id].is_ready = is_ready
		if player_cards.has(player_id):
			player_cards[player_id].set_ready(is_ready)
	
	# Broadcast to all clients
	sync_ready_state.rpc(player_id, is_ready)
	
	update_status()
	check_all_ready()


# RPC to sync ready state (from server to all clients)
@rpc("authority")
func sync_ready_state(player_id: int, is_ready: bool):
	print("Client received ready sync for player ", player_id, ": ", is_ready)
	if player_data.has(player_id):
		player_data[player_id].is_ready = is_ready
		if player_cards.has(player_id):
			player_cards[player_id].set_ready(is_ready)
	update_status()


# Update status label
func update_status():
	var ready_count = 0
	var total_count = player_data.size()
	
	for player_id in player_data:
		if player_data[player_id].is_ready:
			ready_count += 1
	
	status_label.text = "%d / %d players ready" % [ready_count, total_count]


# Check if all players are ready and start game
func check_all_ready():
	if not multiplayer.is_server():
		return
	
	if player_data.size() == 0:
		return
	
	for player_id in player_data:
		if not player_data[player_id].is_ready:
			return
	
	# All players ready! Start the game
	await get_tree().create_timer(1.0).timeout
	start_game.rpc()


# RPC to start the game
@rpc("authority", "call_local")
func start_game():
	# Pass player data to the main scene
	# For now, we'll use a global autoload to store this
	# Or you can pass it via a custom scene initialization
	
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
