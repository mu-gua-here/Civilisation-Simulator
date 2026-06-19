extends CharacterBody3D

const SPEED = 0.5

@onready var nav_agent = $NavigationAgent3D

var happiness: float = 100.0
var wander_timer: float = 0.0

const JUMP_HEIGHT := 1.0

func _ready():
	call_deferred("set_new_destination")
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta):
	# Gravity
	if is_on_floor():
		velocity.y = JUMP_HEIGHT
	else:
		velocity += get_gravity() * delta

	# Happiness drains over time
	happiness -= delta * 2.0
	happiness = clamp(happiness, 0.0, 100.0)

	# Wander timer
	wander_timer -= delta
	if wander_timer <= 0:
		set_new_destination()
		wander_timer = randf_range(3.0, 8.0)

	if not nav_agent.is_navigation_finished():
		var next = nav_agent.get_next_path_position()
		var direction = (next - global_position).normalized()
		var desired_velocity = Vector3(direction.x * SPEED, velocity.y, direction.z * SPEED)
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(desired_velocity)  # triggers velocity_computed signal
		else:
			velocity = desired_velocity
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func _on_velocity_computed(safe_velocity: Vector3):
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z

func set_new_destination():
	# Pick a random point on the 50x50 grid
	var target = Vector3(
		randf_range(-25, 25),
		0,
		randf_range(-25, 25)
	)
	nav_agent.target_position = target
