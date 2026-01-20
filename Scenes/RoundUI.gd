extends CanvasLayer

@onready var round_label: Label = $MarginContainer/VBoxContainer/RoundLabel
@onready var timer_label: Label = $MarginContainer/VBoxContainer/TimerLabel

var round_manager: Node

func _ready():
	# Get reference to RoundManager
	round_manager = get_node("/root/Main/RoundManager")
	
	# Connect to RoundManager signals
	round_manager.round_started.connect(_on_round_started)
	round_manager.timer_updated.connect(_on_timer_updated)
	
	# Intialize display
	#update_round_display()
	update_timer_display(round_manager.round_time_remaining)
	
func _on_round_started(round_number: int):
	update_round_display()

func _on_timer_updated(time_remaining: float):
	update_timer_display(time_remaining)

func update_round_display():
	var current = round_manager.current_round
	var total = round_manager.total_rounds
	round_label.text = "Round %d/%d" % [current, total]
	visible = true

func update_timer_display(seconds: float):
	# Format as MM:SS
	var minutes =  int(seconds) / 60
	var secs = int(seconds) % 60
	timer_label.text = "%d:%02d" % [minutes, secs]
	
	# Optional: Change color when low on time
	if seconds <= 10.0:
		timer_label.modulate = Color.RED
	elif seconds <= 30.0:
		timer_label.modulate = Color.YELLOW
	else:
		timer_label.modulate = Color.WHITE
