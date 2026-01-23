extends Camera2D

# The world size we designed for (matches wrapping boundaries)
const DESIGN_WIDTH = 1800.0/2
const DESIGN_HEIGHT = 960.0/2


func _ready():
	# Adjust zoom based on screen size
	adjust_zoom()
	
	# Enable the camera
	enabled = true


func adjust_zoom():
	# Get actual screen size
	var viewport_size = get_viewport_rect().size
	
	#print("Viewport size: ", viewport_size)
	#print("Design size: ", DESIGN_WIDTH, "x", DESIGN_HEIGHT)
	
	# Calculate zoom needed to fit the design size
	var zoom_x = viewport_size.x / DESIGN_WIDTH
	var zoom_y = viewport_size.y / DESIGN_HEIGHT
	
	# Use the smaller zoom to ensure everything fits
	var zoom_factor = min(zoom_x, zoom_y)
	
	#print("Zoom factor: ", zoom_factor)
	
	# Apply zoom (Godot's zoom is a Vector2)
	zoom = Vector2(zoom_factor, zoom_factor)
