extends Control

const PORT = 7777
const MAX_PLAYERS = 8
const CONFIG_FILE = "user://settings.cfg"

@onready var player_name_input = $VBoxContainer/PlayerNameInput
@onready var ip_input = $VBoxContainer/JoinContainer/IPInput
@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinContainer/JoinButton
@onready var start_button = $VBoxContainer/StartButton
@onready var status_label = $VBoxContainer/StatusLabel

var player_name = "Player"

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Set default player name
	player_name_input.text = "Player" + str(randi() % 1000)
	
	# Load saved IP address
	load_settings()


func _on_host_button_pressed():
	player_name = player_name_input.text
	if player_name.is_empty():
		player_name = "Host"
	
	# Store in global (we'll create this next)
	GameState.local_player_name = player_name
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_PLAYERS)
	
	if error != OK:
		status_label.text = "Failed to host: " + str(error)
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	multiplayer.multiplayer_peer = peer
	
	# Disable buttons and show status
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Hosting on port " + str(PORT)
	status_label.add_theme_color_override("font_color", Color.GREEN)
	
	# Host can start the game
	start_button.visible = true
	
	print("Server started on port ", PORT)


func _on_join_button_pressed():
	player_name = player_name_input.text
	if player_name.is_empty():
		player_name = "Client"
	
	# Store in global
	GameState.local_player_name = player_name
	
	var ip = ip_input.text
	if ip.is_empty():
		ip = "127.0.0.1"
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	
	if error != OK:
		status_label.text = "Failed to connect: " + str(error)
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	multiplayer.multiplayer_peer = peer
	
	# Disable buttons and show status
	host_button.disabled = true
	join_button.disabled = true
	status_label.text = "Connecting to " + ip + "..."
	status_label.add_theme_color_override("font_color", Color.YELLOW)
	
	print("Attempting to connect to ", ip, ":", PORT)


func _on_start_button_pressed():
	# Only the host can start the game
	if not multiplayer.is_server():
		return
	
	# Load the main game scene
	start_game.rpc()


@rpc("authority", "call_local")
func start_game():
	# This will be called on all clients when the host starts the game
	get_tree().change_scene_to_file("res://Scenes/UI/PlaneSelection.tscn")


# Multiplayer callbacks
func _on_player_connected(id):
	print("Player ID connected: ", id)
	status_label.text = "Player ID connected: " + str(id)


func _on_player_disconnected(id):
	print("Player ID disconnected: ", id)
	status_label.text = "Player ID disconnected: " + str(id)


func _on_connected_to_server():
	print("Successfully connected to server")
	status_label.text = "Connected! Waiting for host..."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	
	# Save the IP that worked
	var ip = ip_input.text
	if ip.is_empty():
		ip = "127.0.0.1"
	save_settings(ip)


func _on_connection_failed():
	print("Connection failed")
	status_label.text = "Connection failed!"
	status_label.add_theme_color_override("font_color", Color.RED)
	
	# Re-enable buttons
	host_button.disabled = false
	join_button.disabled = false


func _on_server_disconnected():
	print("Server disconnected")
	status_label.text = "Server disconnected!"
	status_label.add_theme_color_override("font_color", Color.RED)
	
	# Re-enable buttons
	host_button.disabled = false
	join_button.disabled = false
	start_button.visible = false


func load_settings():
	var config = ConfigFile.new()
	var err = config.load(CONFIG_FILE)
	
	if err == OK:
		var saved_ip = config.get_value("network", "last_ip", "127.0.0.1")
		ip_input.text = saved_ip
		print("Loaded saved IP: ", saved_ip)
	else:
		# File doesn't exist yet, use default
		ip_input.text = ""


func save_settings(ip: String):
	var config = ConfigFile.new()
	
	# Load existing settings first (to preserve other settings if we add more later)
	config.load(CONFIG_FILE)
	
	# Save the IP
	config.set_value("network", "last_ip", ip)
	
	# Write to file
	var err = config.save(CONFIG_FILE)
	if err == OK:
		print("Saved IP: ", ip)
	else:
		print("Error saving settings: ", err)
