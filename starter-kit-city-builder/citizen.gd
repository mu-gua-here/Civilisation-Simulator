extends CharacterBody3D

const SPEED = 4.0
const GRAVITY = -9.81

@onready var nav_agent = $NavigationAgent3D

var happiness: float = 100.0
var wander_timer: float = 0.0

func _ready():
	# Start wandering after nav mesh is ready
	call_deferred("set_new_destination")

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Happiness drains over time
	happiness -= delta * 2.0
	happiness = clamp(happiness, 0.0, 100.0)

	# Wander timer
	wander_timer -= delta
	if wander_timer <= 0:
		set_new_destination()
		wander_timer = randf_range(3.0, 8.0)

	# Move toward destination
	if not nav_agent.is_navigation_finished():
		var next = nav_agent.get_next_path_position()
		var direction = (next - global_position).normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func set_new_destination():
	# Pick a random point on the 50x50 grid
	var target = Vector3(
		randf_range(-25, 25),
		0,
		randf_range(-25, 25)
	)
	nav_agent.target_position = target
