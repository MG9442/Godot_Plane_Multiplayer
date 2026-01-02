extends Node

# Player info
var local_player_name: String = "Player"
var local_player_id: int = 0

# All players data {player_id: {name: "", plane_index: 0}}
var players: Dictionary = {}

# Called when node enters scene tree
func _ready():
	pass

# Register a player
func register_player(id: int, p_name: String, plane_index: int = 0):
	players[id] = {
		"name": p_name,
		"plane_index": plane_index
	}
	print("GameState: Registered player ", id, " - ", p_name, " - Plane #", plane_index)

# Update player's plane selection
func update_player_plane(id: int, plane_index: int):
	if players.has(id):
		players[id].plane_index = plane_index

# Get player name by ID
func get_player_name(id: int) -> String:
	if players.has(id):
		return players[id].name
	return "Player" + str(id)

# Get player plane by ID
func get_player_plane(id: int) -> int:
	if players.has(id):
		return players[id].plane_index
	return 0

# Clear all player data (for disconnecting/returning to menu)
func clear_players():
	players.clear()
	local_player_name = "Player"
	local_player_id = 0
