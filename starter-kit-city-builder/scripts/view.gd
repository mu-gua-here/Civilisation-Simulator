extends Node3D

var camera_position:Vector3
var camera_rotation:Vector3

var zoom:float = 5.0

var camera_offset := Vector3.ZERO

@onready var camera = $Camera

func get_player_position() -> Vector3:
	# Adjust this path to wherever your citizen/player node actually is
	var player = get_tree().get_first_node_in_group("player")
	if player:
		return player.global_position
	return Vector3.ZERO
	
func _ready():
	camera_rotation = rotation_degrees # Initial rotation
	add_to_group("view")
	pass

func _process(delta):
	# Set position and rotation to targets
	position = position.lerp(camera_position, delta * 8)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6)
	
	# Smoothly update zoom
	
	camera.position = camera.position.lerp(Vector3(0, 0, zoom), delta * 8)
	
	handle_input(delta)

# Handle input

# Replace the whole handle_input function with this:
func handle_input(_delta):
	var input := Vector3.ZERO
	input.x = Input.get_axis("camera_left", "camera_right")
	input.z = Input.get_axis("camera_forward", "camera_back")
	input = input.rotated(Vector3.UP, rotation.y).normalized()
	
	if input.length() > 0:
		# Player is panning — move away from player
		camera_offset += input / 16
	else:
		# No input — gradually drift back to player
		camera_offset = camera_offset.lerp(Vector3.ZERO, _delta * 2.0)
	
	if Input.is_action_just_pressed("zoom_in"):
		zoom = max(3, zoom - 5)
	if Input.is_action_just_pressed("zoom_out"):
		zoom = min(50, zoom + 5)
	
	# Final camera position = player position + offset
	camera_position = get_player_position() + camera_offset

func _input(event):
	# Rotate camera using mouse (hold 'middle' mouse button)
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("camera_rotate"):
			camera_rotation += Vector3(0, -event.relative.x / 10, 0)
