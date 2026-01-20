extends Node

# Round state
var current_round: int = 1
var total_rounds: int = 5
var round_duration_seconds: int = 60 # Will be set from GameState

# Timer
var round_time_remaining: float = 0.0
var round_active: bool = false
var round_paused: bool = false

# Signals for communicating with other systems
signal round_started(round_number: int)
signal round_ended(round_number: int)
signal timer_updated(time_remaining: float)

func _ready():
	# Load total_rounds for both Server/Clients
	total_rounds = GameState.num_rounds
	
	# This should only run on server
	if not multiplayer.is_server():
		return
	
	# Load round duartion which is then controlled by Server
	round_duration_seconds = GameState.round_duration_minutes * 60
	print("[RoundMananger] Initialized: %d rounds, %d seconds each" % [total_rounds, round_duration_seconds])
	
func _process(delta):
	# Only server updates the timer
	if not multiplayer.is_server():
		return
	
	if not round_active or round_paused:
		return
	
	# Countdown
	round_time_remaining -= delta
	
	# Emit signal locally for server's UI
	timer_updated.emit(round_time_remaining)
	
	# Sync to clients every frame (unreliable is fine for UI updates)
	sync_timer.rpc(round_time_remaining)
	
	# Check if round ended
	if round_time_remaining <= 0.0:
		end_round()


# Server: Start a new round
func start_round():
	if not multiplayer.is_server():
		return
	
	round_time_remaining = round_duration_seconds
	round_active = true
	round_paused = false
	
	print("[RoundManager] Starting round %d/%d" % [current_round, total_rounds])
	
	# Notify everyone the round started
	notify_round_start.rpc(current_round)
	
	# Emit local signal
	round_started.emit(current_round)
	
# Server: End the current round
func end_round():
	if not multiplayer.is_server():
		return
	
	round_active = false
	
	print("[RoundManager] Round %d ended" % current_round)
	
	# Notify everyone the round ended
	notify_round_end.rpc(current_round)
	
	# Emit local signal
	round_ended.emit(current_round)
	
	# TODO: Later we'll add ability selection and round win logic here
	
	# For now, auto-advance to next round after 3 seconds
	await get_tree().create_timer(3.0).timeout
	
	if current_round < total_rounds:
		current_round += 1
		start_round()
	else:
		print("[RoundManager] All rounds complete")
		# TODO: Victory screen logic will go here

# Server: Pause/unpause the round timer
func set_paused(paused: bool):
	if not multiplayer.is_server():
		return
	
	round_paused = paused
	print("[RoundManager] Timer paused: ", paused)
	
# RPC: Sync timer to all clients (unreliable for performance)
@rpc("authority", "unreliable")
func sync_timer(time_remaining: float):
	round_time_remaining = time_remaining
	timer_updated.emit(time_remaining)

# RPC: Nofity all clients that round started
@rpc("authority", "call_local", "reliable")
func notify_round_start(round_number: int):
	current_round = round_number
	round_active = true
	round_started.emit(round_number)
	print("[Client] Round %d started" % round_number)

# RPC: Notify all clients that round ended
@rpc("authority", "call_local", "reliable")
func notify_round_end(round_number: int):
	round_active = false
	round_ended.emit(round_number)
	print("[Client] Round %d ended" % round_number)
