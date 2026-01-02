extends CharacterBody2D

# Movement settings
@export var acceleration: float = 400.0
@export var max_speed: float = 300.0
@export var rotation_speed: float = 5.0
@export var drag: float = 0.98  # How quickly plane slows down (0.95 = more drag, 0.99 = less drag)

# Player info
var player_id: int = 0
var player_name: String = "Player"
var plane_index: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel

# Input direction
var input_direction: Vector2 = Vector2.ZERO


func _ready():
	# Set the collision layer/mask
	collision_layer = 1
	collision_mask = 1


# Setup player with their info
func setup(id: int, p_name: String, p_plane_index: int):
	player_id = id
	player_name = p_name
	plane_index = p_plane_index
	
	# Load the plane sprite
	var plane_path = "res://Sprites/Ships/ship_%04d.png" % plane_index
	var texture = load(plane_path)
	if texture:
		sprite.texture = texture
	
	# Set name label
	name_label.text = p_name
	
	# Only process input for local player
	set_physics_process(is_multiplayer_authority())


func _physics_process(delta: float):
	if not is_multiplayer_authority():
		return
	
	# Get input
	input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# Apply acceleration in input direction
	if input_direction.length() > 0:
		velocity += input_direction.normalized() * acceleration * delta
	
	# Apply drag (continuous gliding effect)
	velocity *= drag
	
	# Clamp to max speed
	if velocity.length() > max_speed:
		velocity = velocity.normalized() * max_speed
	
	# Rotate plane toward movement direction (smooth rotation)
	if velocity.length() > 10:  # Only rotate if moving
		var target_rotation = velocity.angle()
		rotation = lerp_angle(rotation, target_rotation, rotation_speed * delta)
	
	# Move the plane
	move_and_slide()
	
	# Shooting (we'll implement this later)
	if Input.is_action_just_pressed("shoot"):
		shoot()


func shoot():
	# TODO: Implement shooting
	print(player_name, " shoots!")


# Network sync (we'll add this next)
func _process(_delta: float):
	if is_multiplayer_authority():
		# Send position to other players
		rpc("update_remote_position", global_position, rotation)


@rpc("unreliable")
func update_remote_position(pos: Vector2, rot: float):
	if not is_multiplayer_authority():
		global_position = pos
		rotation = rot
