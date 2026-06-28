extends CharacterBody3D

# Movement settings
const BASE_SPEED = 0.5
const JUMP_HEIGHT := 1.0
var actual_speed: float
var wander_timer: float = 0.0
var idle_timer: float = 0.0

# Chase settings
var is_chasing_player: bool = false
var chase_repath_timer := 0.0
const CHASE_REPATH_INTERVAL := 0.25

# STAT BARS
# Resources
@onready var stat_bars_display: Sprite3D = $Sprite3D
@onready var hunger_bar: ProgressBar = $SubViewport/VBoxContainer/HungerBar
@onready var happiness_bar: ProgressBar = $SubViewport/VBoxContainer/HappinessBar
@onready var health_bar: ProgressBar = $SubViewport/VBoxContainer/HealthBar
@onready var stat_viewport: SubViewport = $SubViewport

# Settings
const BAR_VISIBLE_DISTANCE := 3.0

# Attack settings (only relevant while is_chasing_player is true)
@export var attack_damage: float = 10.0
@export var attack_cooldown_time: float = 1.0  # seconds between hits on the same target
@export var attack_knockback_force: float = 0.5
var attack_cooldown: float = 0.0

@onready var nav_agent = $NavigationAgent3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

@export var data: CitizenData

var happiness_material: StandardMaterial3D

var builder: Node = null
var needs_check_timer: float = 0.0
const NEEDS_CHECK_INTERVAL := 2.0 # how often to retry claiming housing/a job if still missing one
var _has_housing: bool = false

func _ready():
	if data == null:
		data = CitizenData.new()
		
	add_to_group("citizen")
	builder = get_tree().get_first_node_in_group("builder")
		
	call_deferred("set_new_destination", Vector3(
		randf_range(-20, 20),
		0,
		randf_range(-20, 20)))
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	
	# Create the override material
	happiness_material = StandardMaterial3D.new()
	mesh_instance.set_surface_override_material(0, happiness_material)
	update_happiness_color()

func _exit_tree():
	if builder and builder.has_method("release_citizen") and data:
		builder.release_citizen(data.id)

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Periodically try to claim housing/a job if we don't have one yet.
	# Cheap to skip most frames since this only matters when something changed
	# (a new building went up) or on first spawn.
	needs_check_timer -= delta
	if needs_check_timer <= 0.0:
		needs_check_timer = NEEDS_CHECK_INTERVAL
		_refresh_housing_and_job()
	
	# Update citizen stats
	if data.job == "":
		data.job_satisfaction -= 10 * delta
	else:
		data.job_satisfaction += randf_range(0.0, 0.01)
	
	data.job_satisfaction = clamp(data.job_satisfaction, 0.0, 100.0)
	
	# Housing satisfaction eases toward 100 if housed, 0 if not -- a citizen
	# sleeping in the street should feel it, but not flip instantly.
	var housing_target = 100.0 if _has_housing else 0.0
	data.housing_satisfaction = move_toward(data.housing_satisfaction, housing_target, delta * 20.0)
	
	data.happiness = clamp(50 - (100 - data.hunger) * 0.005 + (data.job_satisfaction * 0.01 if data.job != "" else -data.job_satisfaction * 0.01) + (data.housing_satisfaction - 50.0) * 0.1, 0, 100)
	update_happiness_color()
	
	actual_speed = BASE_SPEED + (100 - data.happiness) / 100
	nav_agent.max_speed = actual_speed
	
	if data.happiness < 0.1:
		is_chasing_player = true
	elif data.happiness > 10.0:
		is_chasing_player = false
	
	if is_chasing_player:
		chase_repath_timer -= delta
		if chase_repath_timer <= 0.0:
			chase_repath_timer = CHASE_REPATH_INTERVAL
			if Globals.player:
				set_new_destination(Globals.player.global_position)
		
		# Tick down attack cooldown
		if attack_cooldown > 0.0:
			attack_cooldown -= delta

	# Wander timer
	wander_timer -= delta
	if is_on_floor() and wander_timer > 0:
		if data.hunger > 0.0:
			velocity.y = JUMP_HEIGHT
	else:
		wander_timer = randf_range(0, 2) * (100 - data.happiness)
		idle_timer -= delta
		if idle_timer <= 0:
			set_new_destination(Vector3(
				randf_range(-20, 20),
				0,
				randf_range(-20, 20)
			))
			idle_timer = clamp(data.happiness, 180, 6000)	
	
	if not nav_agent.is_navigation_finished() and data.hunger > 0.0:
		var next = nav_agent.get_next_path_position()
		var direction = (next - global_position).normalized()
		var desired_velocity = Vector3(direction.x * actual_speed, velocity.y, direction.z * actual_speed)
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(desired_velocity)  # triggers velocity_computed signal
		else:
			velocity = desired_velocity
	else:
		velocity.x = move_toward(velocity.x, 0, actual_speed)
		velocity.z = move_toward(velocity.z, 0, actual_speed)
	
	data.hunger -= (data.metabolism + data.metabolism * velocity.length()) * 0.01
	data.hunger = clamp(data.hunger, 0, 100)
	
	move_and_slide()
	
	# Real physical collision check — did we actually touch the player this frame?
	if is_chasing_player and attack_cooldown <= 0.0:
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if collider == Globals.player:
				if collider.has_method("take_damage"):
					collider.take_damage(attack_damage, global_position, attack_knockback_force)
				attack_cooldown = attack_cooldown_time
				break
	
	update_stat_bars()
	
	if position.y < -10:
		velocity = Vector3.ZERO
		position = Vector3(randf_range(-5, 5), 1, randf_range(-5, 5))

func _on_velocity_computed(safe_velocity: Vector3):
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z

func _refresh_housing_and_job() -> void:
	if builder == null:
		return
	
	if builder.has_method("has_housing_for"):
		_has_housing = builder.has_housing_for(self)
	
	if data.job == "" and builder.has_method("request_job"):
		var job_name = builder.request_job(self)
		if job_name != "":
			data.job = job_name

func set_new_destination(target):
	# Pick a random point on the grid
	nav_agent.target_position = target

func update_happiness_color():
	# Green when happy, red when unhappy
	var t = data.happiness / 100.0
	happiness_material.albedo_color = Color(1.0 - t, t, 0.0)

func update_stat_bars():
	if not Globals.player:
		stat_bars_display.visible = false
		stat_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	var dist = global_position.distance_to(Globals.player.global_position)
	var in_range = dist < BAR_VISIBLE_DISTANCE

	stat_bars_display.visible = in_range
	stat_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if in_range else SubViewport.UPDATE_DISABLED
	)

	if in_range:
		hunger_bar.value = data.hunger
		happiness_bar.value = data.happiness
		health_bar.value = data.health
