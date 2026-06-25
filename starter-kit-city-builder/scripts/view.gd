extends Node3D

var camera_position:Vector3
var camera_rotation:Vector3

var zoom:float = 5.0

var camera_offset := Vector3.ZERO

@onready var camera = $Camera

# Keyboard camera rotation controls
var rotate_speed: float = 0.0  # current angular speed (ramps up while held)
const ROTATE_MAX_SPEED := 120.0  # degrees/sec at full ramp
const ROTATE_ACCEL := 240.0      # degrees/sec^2 ramp-up rate
const ROTATE_DECEL := 480.0      # degrees/sec^2 ramp-down rate when released

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

func handle_input(_delta):
	
	# Move camera but not player to look around
	var input := Vector3.ZERO
	input.x = Input.get_axis("camera_left", "camera_right")
	input.z = Input.get_axis("camera_forward", "camera_back")
	input = input.rotated(Vector3.UP, rotation.y).normalized()
	
	# CAMERA TURNING
	
	# Mouse camera turn
	if input.length() > 0:
		# Player is panning — move away from player
		camera_offset += input / 16
	else:
		# No input — gradually drift back to player
		camera_offset = camera_offset.lerp(Vector3.ZERO, _delta * 2.0)
	
	# Keyboard/gamepad camera turn (Q/E)
	var turn = Input.get_axis("camera_turn_right", "camera_turn_left")
	if turn != 0:
		rotate_speed = move_toward(rotate_speed, turn * ROTATE_MAX_SPEED, ROTATE_ACCEL * _delta)
	else:
		rotate_speed = move_toward(rotate_speed, 0.0, ROTATE_DECEL * _delta)

	if rotate_speed != 0.0:
		camera_rotation.y -= rotate_speed * _delta

	camera_position = get_player_position() + camera_offset
	
	# CAMERA ZOOMING
	
	# Discrete zoom (for mouse users, mouse wheel up/down)
	if Input.is_action_just_pressed("zoom_in"):
		zoom = max(3, zoom - 5)
	if Input.is_action_just_pressed("zoom_out"):
		zoom = min(50, zoom + 5)
	
	# Continuous zoom (keyboard +/-)
	var zoom_axis = Input.get_axis("zoom_in_hold", "zoom_out_hold")
	if zoom_axis != 0:
		zoom = clamp(zoom + zoom_axis * _delta * 20.0, 3, 50)
	
	# Final camera position = player position + offset
	camera_position = get_player_position() + camera_offset

func _input(event):
	# Mouse drag rotation
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("camera_rotate"):
			camera_rotation += Vector3(0, -event.relative.x / 10, 0)

	# Trackpad: two-finger swipe rotates camera, no key held needed
	elif event is InputEventPanGesture:
		camera_rotation.y -= event.delta.x * 1.5

	# Trackpad: pinch to zoom
	elif event is InputEventMagnifyGesture:
		# factor > 1 means pinching outward (fingers spreading) -> zoom in
		zoom = clamp(zoom / event.factor, 3, 50)
