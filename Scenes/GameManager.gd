extends Node

const Player = preload("res://Scenes/Player.tscn")
const player_scene = preload("res://Scenes/Player.tscn")

# Spawn positions (spread players out in a circle)
var spawn_positions = [
	Vector2(0, -200),
	Vector2(200, 0),
	Vector2(0, 200),
	Vector2(-200, 0),
	Vector2(150, -150),
	Vector2(150, 150),
	Vector2(-150, 150),
	Vector2(-150, -150),
]

@onready var players_container = $Players

var spawned_players = {}  # {player_id: Player node}
var is_game_paused: bool = false


func _ready():
	print("GameManager _ready() called")
	print("Players container: ", players_container)
	
	# Wait a frame for everything to be ready
	await get_tree().process_frame
	
	# Spawn all players from GameState
	spawn_all_players()
	
	# Set up multiplayer signals for late joiners / disconnects
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta):
	# Only host can pause the game
	if multiplayer.is_server():
		# Check for CTRL + ~ (grave key, keycode 96)
		# Or CTRL + ~ (tilde key, keycode 126)
		if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_CTRL):
			if Input.is_physical_key_pressed(KEY_QUOTELEFT):  # The ` / ~ key
				if not is_game_paused:  # Only trigger once
					toggle_pause()

func toggle_pause():
	if not multiplayer.is_server():
		print("Only the host can pause the game!")
		return
	
	is_game_paused = !is_game_paused
	
	if is_game_paused:
		pause_game()
	else:
		resume_game()
	
	# Sync pause state to all clients
	sync_pause_state.rpc(is_game_paused)

func pause_game():
	print("Pausing game...")
	
	# Pause the game tree (everything except pause menu)
	get_tree().paused = true

func resume_game():
	print("Resuming game...")
	
	# Resume the game tree
	get_tree().paused = false

# Server -> Clients: Sync pause state
@rpc("authority", "reliable", "call_local")
func sync_pause_state(paused: bool):
	is_game_paused = paused
	
	if paused:
		# Pause the game
		get_tree().paused = true
	else:
		# Resume the game
		get_tree().paused = false

func spawn_all_players():
	print("=== GameManager: Spawning all players ===")
	print("GameState.players: ", GameState.players)
	print("Number of players: ", GameState.players.size())
	print("My multiplayer ID: ", multiplayer.get_unique_id())
	
	if multiplayer.is_server():
		# Server spawns immediately
		_do_spawn()
		# Then tell clients to spawn with the data
		sync_spawn_data.rpc(GameState.players)
	# Clients wait for sync_spawn_data RPC
	

func _do_spawn():
	if GameState.players.is_empty():
		print("ERROR: No players in GameState!")
		return
	
	for player_id in GameState.players.keys():
		var player_data = GameState.players[player_id]
		spawn_player(player_id, player_data["name"], player_data["plane_index"])

func spawn_player(player_id: int, player_name: String, plane_index: int):
	print("Spawning player: ID=", player_id, " Name=", player_name, " Plane=", plane_index)
	
	var player = player_scene.instantiate()
	player.name = str(player_id)
	player.z_index = 10
	
	# Set spawn position
	var spawn_index = spawned_players.size() % spawn_positions.size()
	player.global_position = spawn_positions[spawn_index]
	
	# Add to scene
	players_container.add_child(player, true)
	
	# Setup player (loads sprite, sets name)
	player.setup(player_id, player_name, plane_index)
	
	# Set multiplayer authority
	player.set_multiplayer_authority(player_id)
	
	# Store reference
	spawned_players[player_id] = player
	
	print("Player spawned successfully: ", player_name)


# Handle late joiners (someone joins after game started)
func _on_player_connected(id):
	print("Player connected mid-game: ", id)
	# In a full implementation, you'd sync game state to them
	# For now, they'll need to restart


# Handle disconnects
func _on_player_disconnected(id):
	print("Player disconnected: ", id)
	
	# Remove their player node
	if spawned_players.has(id):
		spawned_players[id].queue_free()
		spawned_players.erase(id)


# Server sends player data to clients
@rpc("authority", "reliable")
func sync_spawn_data(players_data: Dictionary):
	print("Client received spawn data: ", players_data)
	GameState.players = players_data
	_do_spawn()


# Handle server disconnect (host left)
func _on_server_disconnected():
	print("Server disconnected! Returning to main menu...")
	
	# Clear multiplayer peer
	multiplayer.multiplayer_peer = null
	
	# Clear game state
	GameState.clear_players()
	
	# Return to main menu
	get_tree().change_scene_to_file("res://Scenes/UI/MainMenu.tscn")


# ===== BULLET SPAWNING =====

# Called by any player (client or server) when they want to shoot
func request_bullet_spawn(spawn_pos: Vector2, direction: Vector2, shooter_id: int):
	if multiplayer.is_server():
		# Server spawns immediately and tells clients
		spawn_bullet_everywhere(spawn_pos, direction, shooter_id)
		spawn_bullet_on_clients.rpc(spawn_pos, direction, shooter_id)
	else:
		# Client requests server to spawn
		request_bullet_from_server.rpc_id(1, spawn_pos, direction, shooter_id)


# Client -> Server: Request to spawn a bullet
@rpc("any_peer", "reliable")
func request_bullet_from_server(spawn_pos: Vector2, direction: Vector2, shooter_id: int):
	if multiplayer.is_server():
		# Verify the request is from the actual player
		var sender_id = multiplayer.get_remote_sender_id()
		if sender_id == shooter_id:
			# Spawn on server and all clients
			spawn_bullet_everywhere(spawn_pos, direction, shooter_id)
			spawn_bullet_on_clients.rpc(spawn_pos, direction, shooter_id)
		else:
			print("WARNING: Player ", sender_id, " tried to shoot as player ", shooter_id)


# Server -> Clients: Spawn this bullet
@rpc("authority", "reliable")
func spawn_bullet_on_clients(spawn_pos: Vector2, direction: Vector2, shooter_id: int):
	if not multiplayer.is_server():
		spawn_bullet_everywhere(spawn_pos, direction, shooter_id)


# Actually spawn the bullet locally (on server or client)
func spawn_bullet_everywhere(spawn_pos: Vector2, direction: Vector2, shooter_id: int):
	# Find the player node
	if spawned_players.has(shooter_id):
		var player = spawned_players[shooter_id]
		player.spawn_bullet_local(spawn_pos, direction, shooter_id)
	else:
		print("ERROR: Could not find player ", shooter_id, " to spawn bullet")
