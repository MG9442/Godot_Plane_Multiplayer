extends CharacterBody2D

# Movement settings
@export var min_speed: float = 150.0  # Minimum gliding speed
@export var max_speed: float = 400.0  # Maximum speed
@export var acceleration_rate: float = 200.0  # How fast W speeds you up
@export var deceleration_rate: float = 150.0  # How fast S slows you down
@export var rotation_speed: float = 3.0  # How fast A/D rotates the plane

# Shooting settings
@export var max_bullets: int = 5
@export var bullet_spawn_offset: float = 30.0  # Distance from plane center to spawn bullet

# Player info
var player_id: int = 0
var player_name: String = "Player"
var plane_index: int = 0

# Current speed
var current_speed: float = 0.0

# Bullet tracking
var active_bullets: Array = []
var bullet_scene = preload("res://Scenes/Bullet.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $UIHolder/NameLabel
@onready var ui_holder: Node2D = $UIHolder


func _ready():
	# Set the collision layer/mask
	collision_layer = 1
	collision_mask = 1
	
	# Start at minimum speed
	current_speed = min_speed
	
	# Add to players group for bullet collision detection
	add_to_group("players")


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
	

func _physics_process(delta: float):
	if not is_multiplayer_authority():
		return
	
	# Rotation input (A/D)
	var rotation_input = Input.get_axis("move_left", "move_right")
	rotation += rotation_input * rotation_speed * delta
	
	# Speed input (W to accelerate, S to decelerate)
	if Input.is_action_pressed("move_up"):
		current_speed += acceleration_rate * delta
	elif Input.is_action_pressed("move_down"):
		current_speed -= deceleration_rate * delta
	
	# Clamp speed between min and max
	current_speed = clamp(current_speed, min_speed, max_speed)
	
	# Move forward in the direction the plane is facing
	var forward_direction = Vector2.RIGHT.rotated(rotation)
	velocity = forward_direction * current_speed
	
	# Move the plane
	move_and_slide()
	
	# Screen wrapping
	wrap_screen()
	
	# Keep UI upright
	ui_holder.rotation = -rotation
	
	# Shooting
	if Input.is_action_just_pressed("shoot"):
		shoot()

func shoot():
	# Check if we can shoot (haven't reached max bullets)
	if active_bullets.size() >= max_bullets:
		print(player_name, " can't shoot - max bullets reached (", max_bullets, ")")
		return
	
	print(player_name, " shoots! (", active_bullets.size() + 1, "/", max_bullets, ")")
	
	# Calculate bullet spawn position (in front of plane)
	var forward_direction = Vector2.RIGHT.rotated(rotation)
	var spawn_pos = global_position + forward_direction * bullet_spawn_offset
	
	# Get the Main node (which has GameManager.gd attached)
	var game_manager = get_node("/root/Main")
	if game_manager and game_manager.has_method("request_bullet_spawn"):
		game_manager.request_bullet_spawn(spawn_pos, forward_direction, player_id)
	else:
		print("ERROR: Could not find GameManager (Main node)")


func spawn_bullet_local(spawn_pos: Vector2, direction: Vector2, shooter_id: int):
	# This is called by GameManager to spawn a bullet locally
	var bullet = bullet_scene.instantiate()
	bullet.global_position = spawn_pos
	
	# If the bullet scene doesn't have a collision shape, add one programmatically
	if bullet.get_node_or_null("CollisionShape2D") == null:
		var collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(8, 3)
		collision.shape = shape
		bullet.add_child(collision)
	
	bullet.setup(direction, shooter_id)
	
	# Add to scene tree
	get_tree().root.add_child(bullet)
	
	# Track this bullet only if it's ours
	if shooter_id == player_id:
		active_bullets.append(bullet)
		bullet.tree_exiting.connect(_on_bullet_despawned.bind(bullet))


func _on_bullet_despawned(bullet):
	if bullet in active_bullets:
		active_bullets.erase(bullet)
	print(player_name, " bullet despawned. Active bullets: ", active_bullets.size(), "/", max_bullets)

# Network sync
func _process(_delta: float):
	if is_multiplayer_authority():
		# Send position and rotation to other players
		update_remote_position.rpc(global_position, rotation, current_speed)

func wrap_screen():
	# Only wrap for the local player
	if not is_multiplayer_authority():
		return
	
	# Define fixed world boundaries (not based on screen size)
	# You can adjust these to match your game world
	var world_width = 1920.0
	var world_height = 1080.0
	var right_boundary = world_width / 4
	var left_boundary = -world_width / 4
	var bottom_boundary = world_height / 4
	var top_boundary = -world_height / 4
	
	#print("Player position: ", global_position)
	#print("Boundaries - Right: ", right_boundary, " Left: ", left_boundary)
	#print("Boundaries - Top: ", top_boundary, " Bottom: ", bottom_boundary)
	
	var wrapped = false
	
	# Wrap horizontally
	if global_position.x > right_boundary:
		#print("WRAPPING RIGHT TO LEFT")
		global_position.x = left_boundary + 10  # Small offset to prevent immediate re-wrap
		wrapped = true
	elif global_position.x < left_boundary:
		#print("WRAPPING LEFT TO RIGHT")
		global_position.x = right_boundary - 10
		wrapped = true
	
	# Wrap vertically
	if global_position.y > bottom_boundary:
		#print("WRAPPING BOTTOM TO TOP")
		global_position.y = top_boundary + 10
		wrapped = true
	elif global_position.y < top_boundary:
		#print("WRAPPING TOP TO BOTTOM")
		global_position.y = bottom_boundary - 10
		wrapped = true
	
	# Force sync to all clients when wrapped (using reliable RPC)
	if wrapped:
		force_sync_position.rpc(global_position)

@rpc("authority", "call_local", "reliable")
func force_sync_position(pos: Vector2):
	global_position = pos

@rpc("unreliable")
func update_remote_position(pos: Vector2, rot: float, speed: float):
	if not is_multiplayer_authority():
		global_position = pos
		rotation = rot
		current_speed = speed
		ui_holder.rotation = -rotation
