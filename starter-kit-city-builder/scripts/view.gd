extends Node3D

var camera_position:Vector3
var camera_rotation:Vector3

@onready var spring_arm := $SpringArm3D as SpringArm3D
@onready var copy_target := $SpringArm3D/CopyMe as Marker3D
@onready var camera := $Camera as Camera3D

@export var max_zoom := 50.0
@export var min_zoom := 1.0
@export var scroll_zoom_speed := 2.0

# Viewing
@export_range(0.0, 1.0) var mouse_sensitivity = 0.01
@export var max_tilt_limit := 0.0
@export var min_tilt_limit := -90.0
@export var arm_greater_threshold := 10.0
@export var arm_less_threshold := 2.0

var zoom:float = 5.0

var camera_offset := Vector3.ZERO

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
	camera.global_transform = copy_target.global_transform
	camera.make_current()

func _process(delta):
	# Set position and rotation to targets
	position = position.lerp(camera_position, delta * 8)
	rotation_degrees = rotation_degrees.lerp(camera_rotation, delta * 6)
	
	# SpringArm3D positions CopyMe instantly every physics frame
	# So can interpolate camera zoom here
	
	spring_arm.spring_length = zoom
	camera.global_position = camera.global_position.lerp(copy_target.global_position, delta * 10.0)
	camera.global_rotation = copy_target.global_rotation
	
	# Enable/Disable SpringArm if zoom is within range
	if zoom > arm_less_threshold and zoom < arm_greater_threshold:
		spring_arm.collision_mask = 1
	else:
		spring_arm.collision_mask = 0
	
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
	## NOTE: PROBLEM: DISORIENTED WHEN PLAYER FACE DIFF DIRS
	var turn = Input.get_axis("camera_turn_right", "camera_turn_left")
	if turn != 0:
		rotate_speed = move_toward(rotate_speed, turn * ROTATE_MAX_SPEED, ROTATE_ACCEL * _delta)
	else:
		rotate_speed = move_toward(rotate_speed, 0.0, ROTATE_DECEL * _delta)

	if rotate_speed != 0.0:
		camera_rotation.y -= rotate_speed * _delta
	
	# CAMERA ZOOMING
	
	# Discrete zoom (for mouse users, mouse wheel up/down)
	if Input.is_action_just_pressed("zoom_in"):
		zoom = max(min_zoom, zoom - scroll_zoom_speed)
	if Input.is_action_just_pressed("zoom_out"):
		zoom = min(max_zoom, zoom + scroll_zoom_speed)
	
	# Continuous zoom (keyboard +/-)
	var zoom_axis = Input.get_axis("zoom_in_hold", "zoom_out_hold")
	if zoom_axis != 0:
		zoom = clamp(zoom + zoom_axis * _delta * 20.0, 3, 50)
	
	# Final camera position = player position + offset
	camera_position = get_player_position() + camera_offset

func _input(event):
	
	# Mouse drag rotation
	# NOTE: PROBLEM: camera_rotate needs a key/trackpad alternative
	if event is InputEventMouseMotion:
		if Input.is_action_pressed("camera_rotate"):
			camera_rotation += Vector3(-event.relative.y / 10, -event.relative.x / 10, 0)
			camera_rotation.x = clamp(camera_rotation.x, min_tilt_limit, max_tilt_limit)

	# Trackpad: two-finger swipe rotates camera
	elif event is InputEventPanGesture:
		camera_rotation.y -= event.delta.x * 1.5

	# Trackpad: pinch to zoom
	elif event is InputEventMagnifyGesture:
		# factor > 1 means pinching outward (fingers spreading) -> zoom in
		zoom = clamp(zoom / event.factor, 3, 50)
