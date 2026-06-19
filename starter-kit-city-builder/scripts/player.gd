extends CharacterBody3D

const SPEED = 0.15
const JUMP_VELOCITY = 2.0
const FRICTION = 0.8

var view_node:Node3D

func _ready():
	position = Vector3i(0, 1, 0)
	add_to_group("player")
	view_node = get_tree().get_first_node_in_group("view")

func _physics_process(delta: float) -> void:
	# Add the gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var cam_basis = view_node.rotation.y if view_node else 0.0
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, cam_basis).normalized()
	var is_running:int = Input.is_action_pressed("run")
	if direction:
		velocity.x += direction.x * SPEED * (is_running + 1)
		velocity.z += direction.z * SPEED * (is_running + 1)
	
	# Apply slowing down of velocity
	velocity.x *= FRICTION
	velocity.z *= FRICTION

	move_and_slide()
	
	if position.y < -10:
		position = Vector3i(0, 1, 0)
