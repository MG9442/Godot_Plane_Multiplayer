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

# Server-authoritative health and respawn tracking
var player_health: Dictionary = {} # {player_id: current_health}
var player_max_health: Dictionary = {} # {player_id: max_health}
var player_respawn_state: Dictionary = {} # {player_id: {is_dead: bool, respawn_timer: float}}
var respawn_delay: float = 3.0 # Time before respawn in seconds

func _ready():
	#print("GameManager _ready() called")
	#print("Players container: ", players_container)
	
	# Wait a frame for everything to be ready
	await get_tree().process_frame
	
	# Spawn all players from GameState
	spawn_all_players()
	
	# Set up multiplayer signals for late joiners / disconnects
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Start round 1 after players spawn
	if multiplayer.is_server():
		await get_tree().create_timer(2.0).timeout # Give time for players to load
		$RoundManager.start_round()


func _process(_delta):
	# Server handles respawn countdowns
	if multiplayer.is_server():
		process_respawns(_delta)
	
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
		#print("GameManager(): Only the host can pause the game!")
		return
	
	is_game_paused = !is_game_paused
	
	if is_game_paused:
		pause_game()
	else:
		resume_game()
	
	# Sync pause state to all clients
	sync_pause_state.rpc(is_game_paused)

func pause_game():
	print("GameManager(): Pausing game...")
	
	# Pause the game tree (everything except pause menu)
	get_tree().paused = true

func resume_game():
	print("GameManager(): Resuming game...")
	
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
	#print("Number of players: ", GameState.players.size())
	#print("My multiplayer ID: ", multiplayer.get_unique_id())
	
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
	
	# Initialize server health tracking
	if multiplayer.is_server():
		player_max_health[player_id] = player.max_health
		player_health[player_id] = player_max_health[player_id]
		player_respawn_state[player_id] = {"is_dead": false, "respawn_timer": 0.0}
		print("Server initialized health for player ", player_id, ": ", player_health[player_id])

# ===== DAMAGE PROCESSING (Server Only) =====

# Process damage on server - single source of truth
func process_damage(victim_id: int, shooter_id: int, damage: int = 1):
	# This function should ONLY run on the server
	if not multiplayer.is_server():
		print("ERROR: process_damage called on client!")
		return
	
	# Check if victim exists and is alive
	if not player_health.has(victim_id):
		print("ERROR: Victim ", victim_id, " not found in health tracking")
		return
	
	if player_respawn_state[victim_id]["is_dead"]:
		print("Victim ", victim_id, " is already dead, ignoring damage")
		return
	
	# Apply damage to server's health tracking
	var previous_health = player_health[victim_id]
	player_health[victim_id] -= damage
	
	print("Server: Player ", victim_id, " took ", damage, " damage. Health ", previous_health, " -> ", player_health[victim_id])
	
	# Sync health update to all clients (including visual update)
	if spawned_players.has(victim_id):
		spawned_players[victim_id].take_damage(damage)
		sync_health_to_clients.rpc(victim_id, player_health[victim_id])
	
	# Check for death
	if player_health[victim_id] <= 0 and previous_health > 0:
		print("Server: Player ", victim_id, " DIED! Killed by player ", shooter_id)
		
		# Mark as dead
		player_respawn_state[victim_id]["is_dead"] = true
		player_respawn_state[victim_id]["respawn_timer"] = respawn_delay
		
		# Register the kill
		GameState.add_kill(shooter_id)
		sync_kill_to_clients.rpc(shooter_id)
		
		# Update killer's UI
		if spawned_players.has(shooter_id):
			spawned_players[shooter_id].update_kill_display()
		
		# Hide the dead player on all clients
		if spawned_players.has(victim_id):
			spawned_players[victim_id].sync_player_state.rpc(
				spawned_players[victim_id].global_position, # Keep current position
				0,  # Health is 0 (dead)
				false,  # Not visible
				true  # Is dead/respawning
			)

# ===== RESPAWN SYSTEM (Server Only) =====

# Process respawn timers (Server Only)
func process_respawns(delta: float):
	# Only server processes respawns
	if not multiplayer.is_server():
		return
	
	# Loop through all players and check their respawn state
	for player_id in player_respawn_state.keys():
		var state = player_respawn_state[player_id]
		
		# If player is dead and has a respawn timer
		if state["is_dead"] and state["respawn_timer"] > 0:
			# Count down the timer
			state["respawn_timer"] -= delta
			
			# Check if timer expired
			if state["respawn_timer"] <= 0:
				execute_respawn(player_id)

# Execute respawn for a player (Server Only)
func execute_respawn(player_id: int):
	if not multiplayer.is_server():
		return
	
	#print("Server: Executing respawn for player ", player_id)
	
	# Pick a random spawn point
	var new_position = spawn_positions.pick_random()
	
	# Reset health on server
	player_health[player_id] = player_max_health[player_id]
	player_respawn_state[player_id]["is_dead"] = false
	player_respawn_state[player_id]["respawn_timer"] = 0.0
	
	# Sync respawn to everyone (including server via call_local)
	if spawned_players.has(player_id):
		spawned_players[player_id].sync_player_state.rpc(
		new_position,  # New spawn position
		player_health[player_id],  # Full health
		true,  # Visible
		false  # Not dead anymore
		)
		print("Server: Player ", player_id, " respawned at ", new_position, " with health ", player_health[player_id])

# Increase a player's max health (for upgrades/powerups)
func increase_max_health(player_id: int, amount: int):
	if not multiplayer.is_server():
		return
	
	if not player_max_health.has(player_id):
		print("ERROR: Player ", player_id, " not found in max_health tracking")
		return
	
	# Increase max health
	player_max_health[player_id] += amount
	
	# Also increase current health by the same amount (so they get the benefit immediately)
	player_health[player_id] += amount
	
	print("Server: Player ", player_id, " max health increased by ", amount, ". New max: ", player_max_health[player_id])
	
	# Sync the health increase to all clients
	if spawned_players.has(player_id):
		spawned_players[player_id].max_health = player_max_health[player_id]
		spawned_players[player_id].set_health(player_health[player_id])
		sync_health_to_clients.rpc(player_id, player_health[player_id])

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
	#print("Client received spawn data: ", players_data)
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

# ===== KILL TRACKING SYNC =====
# Server -> Clients: Sync kill count update
@rpc("authority", "reliable")
func sync_kill_to_clients(killer_id: int):
	# FIRST update the client's GameState
	GameState.add_kill(killer_id)
	
	# THEN update the killer's UI on all clients
	if spawned_players.has(killer_id):
		spawned_players[killer_id].update_kill_display()

# ===== HEALTH SYNC =====
# Server -> Clients: Sync health update
@rpc("authority", "reliable")
func sync_health_to_clients(player_id: int, new_health: int):
	# Update the player's health on all clients
	if spawned_players.has(player_id):
		spawned_players[player_id].set_health(new_health)

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
