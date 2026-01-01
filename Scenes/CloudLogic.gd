extends Sprite2D

var speed : int # Speed in pixels
var speed_increment : int = 10
@export var min_speed : int = 90
@export var max_speed : int = 110

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
		increment_speed()

# Establish random starting speed for clouds
func randomize_speed() -> void:
	speed = (randi_range(min_speed, max_speed)) # Obtain random speed between max/min
	speed = snapped(speed, 10) # Round to the nearest tenth
	#print(self.name + " random speed = " + str(speed))

# Increase speed by 1 until reaching max speed
# Gives clouds variability but keeps it consistent
func increment_speed() -> void:
	if speed >= max_speed:
		speed = min_speed
	else:
		speed += 10
	#print(self.name + " random speed = " + str(speed))
