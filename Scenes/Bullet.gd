extends Area2D

@export var speed: float = 800.0
@export var max_travel_distance: float = 100.0  # Extra distance past boundary before despawn

var direction: Vector2 = Vector2.RIGHT
var start_position: Vector2
var shooter_id: int = 0

# World boundaries (matching Player.gd)
var world_width = 1920.0
var world_height = 1080.0

@onready var sprite: ColorRect = $ColorRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	# Set collision layers
	collision_layer = 2  # Bullets on layer 2
	collision_mask = 1   # Can hit players on layer 1
	
	start_position = global_position
	
	# Set up visual
	sprite.color = Color.YELLOW
	sprite.size = Vector2(8, 3)
	sprite.position = -sprite.size / 2  # Center it
	
	# Connect collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float):
	# Move bullet
	global_position += direction * speed * delta
	
	# Check if bullet has traveled beyond boundaries + buffer
	if is_out_of_bounds():
		despawn()

func is_out_of_bounds() -> bool:
	var right_boundary = world_width / 4 + max_travel_distance
	var left_boundary = -world_width / 4 - max_travel_distance
	var bottom_boundary = world_height / 4 + max_travel_distance
	var top_boundary = -world_height / 4 - max_travel_distance
	
	return (global_position.x > right_boundary or 
			global_position.x < left_boundary or
			global_position.y > bottom_boundary or
			global_position.y < top_boundary)

func setup(shoot_direction: Vector2, shooter_player_id: int):
	direction = shoot_direction.normalized()
	shooter_id = shooter_player_id
	rotation = direction.angle()

func despawn():
	# Notify the player that this bullet is gone
	#print("Bullet despawned")
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		queue_free()
	else:
		# On clients, let server handle despawning
		queue_free()

func _on_body_entered(body):
	# Handle collision with CharacterBody2D (players)
	print("Bullet collided with body: ", body.name)
	
	if body.has_method("get") and body.get("player_id") != null:
		# It's a player
		if body.player_id != shooter_id:
			print("Bullet hit enemy player: ", body.player_name)
			# Apply damage to the player
			if body.has_method("take_damage"):
				body.take_damage(1)  # Deal 1 damage
			despawn()
		else:
			print("Bullet hit own player, ignoring")
	else:
		# Hit something else, despawn anyway
		despawn()

func _on_area_entered(area):
	# Handle collision with other Area2D nodes if needed
	print("Bullet hit area: ", area.name)
	despawn()
