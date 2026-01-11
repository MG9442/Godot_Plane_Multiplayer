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
		spawn_player(player_id, player_data.name, player_data.plane_index)

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
@rpc("authority", "call_local", "reliable")
func sync_spawn_data(players_data: Dictionary):
	print("Client received spawn data: ", players_data)
	GameState.players = players_data
	_do_spawn()
