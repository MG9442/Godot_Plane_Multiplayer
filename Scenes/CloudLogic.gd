extends Sprite2D

var speed : float # Speed in pixels
@export var min_speed : int = 80
@export var max_speed : int = 100
@export var min_x : int = -800
@export var max_x : int = 800

var random_int = RandomNumberGenerator.new()

func _ready() -> void:
	random_int.randomize()
	randomize_speed()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	position.x += speed * delta # Move cloud to the right
	
	#print("CloudLogic: position.x = " + str(position.x))
	if position.x >= max_x:
		position.x = min_x
		randomize_speed()

func randomize_speed() -> void:
	speed = (randi_range(min_speed, max_speed)) # Obtain random speed between max/min
	#print("CloudLogic: random speed = " + str(speed))
