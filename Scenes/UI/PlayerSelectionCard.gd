extends PanelContainer

const TOTAL_PLANES = 24  # ship_0000 to ship_0023

@onready var player_name_label = $VBoxContainer/PlayerNameLabel
@onready var plane_sprite = $VBoxContainer/PlaneViewport/SubViewport/PlaneSprite
@onready var plane_name_label = $VBoxContainer/PlaneNameLabel
@onready var prev_button = $VBoxContainer/ControlsContainer/PrevButton
@onready var next_button = $VBoxContainer/ControlsContainer/NextButton
@onready var ready_indicator = $VBoxContainer/ReadyIndicator

var player_id: int = 0
var player_name: String = "Player"
var current_plane_index: int = 0
var is_ready: bool = false
var is_local_player: bool = false

signal plane_changed(player_id: int, plane_index: int)
signal ready_changed(player_id: int, is_ready: bool)


func _ready():
	update_plane_sprite()


func setup(p_id: int, p_name: String, is_local: bool):
	player_id = p_id
	player_name = p_name
	is_local_player = is_local
	
	player_name_label.text = p_name
	
	# Only local player can use controls
	prev_button.visible = is_local
	next_button.visible = is_local
	
	# Add visual indicator for local player
	if is_local:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.5, 0.7, 0.3)
		style.border_color = Color(0.4, 0.7, 1.0, 1.0)
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		add_theme_stylebox_override("panel", style)


func set_plane_index(index: int):
	current_plane_index = index
	update_plane_sprite()


func update_plane_sprite():
	var plane_path = "res://Sprites/Ships/ship_%04d.png" % current_plane_index
	var texture = load(plane_path)
	
	if texture:
		plane_sprite.texture = texture
		plane_name_label.text = "Plane #%d" % current_plane_index
	else:
		print("Failed to load plane texture: ", plane_path)


func set_ready(ready: bool):
	is_ready = ready
	ready_indicator.visible = ready
	
	if is_local_player:
		prev_button.disabled = ready
		next_button.disabled = ready


func _on_prev_button_pressed():
	if not is_local_player or is_ready:
		return
	
	current_plane_index -= 1
	if current_plane_index < 0:
		current_plane_index = TOTAL_PLANES - 1
	
	update_plane_sprite()
	plane_changed.emit(player_id, current_plane_index)


func _on_next_button_pressed():
	if not is_local_player or is_ready:
		return
	
	current_plane_index += 1
	if current_plane_index >= TOTAL_PLANES:
		current_plane_index = 0
	
	update_plane_sprite()
	plane_changed.emit(player_id, current_plane_index)
