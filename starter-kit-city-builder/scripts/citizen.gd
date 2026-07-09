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

# Distance a citizen needs to be from a gatherable/build cell to start contributing
const WORK_REACH := 1.5

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
var housing_check_timer: float = 0.0
const HOUSING_CHECK_INTERVAL := 2.0 # how often to re-derive housing status from builder.buildings
var _has_housing: bool = false

var is_gathering: bool = false
const NO_CELL := Vector3i(NAN, NAN, NAN)
var gather_target_cell: Vector3i = NO_CELL

# Building (A.4) -- entered only via explicit assignment (manual click for now)
var is_building: bool = false
var build_target_cell: Vector3i = NO_CELL

# Carrying gathered resources back to a construction site (#4 -- resources no
# longer auto-add to the stockpile on gather; a citizen physically carries
# what they chopped until they can hand it off via Builder.deposit_resources()).
var carried_resources: Dictionary = {}
var is_delivering: bool = false
var deliver_target_cell: Vector3i = NO_CELL

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
	
	# Periodically re-check whether this citizen is currently housed.
	# NOTE: job assignment is intentionally NOT auto-retried here -- per the
	# plan, manual (CitizenSelector) or policy (Milestone B, not yet built)
	# assignment via PolicyEngine is the only path to a job right now.
	housing_check_timer -= delta
	if housing_check_timer <= 0.0:
		housing_check_timer = HOUSING_CHECK_INTERVAL
		_refresh_housing_status()
	
	_update_gathering(delta)
	_update_building(delta)
	_update_delivering(delta)
	
	# Update citizen stats
	if data.job == "":
		data.job_satisfaction -= 10 * delta
	else:
		data.job_satisfaction += randf_range(0.0, 0.01)
	
	data.job_satisfaction = clamp(data.job_satisfaction, 0.0, 100.0)
	
	# Housing satisfaction eases toward 100 if housed, 0 if not
	var housing_target = 100.0 if _has_housing else 0.0
	data.housing_satisfaction = move_toward(data.housing_satisfaction, housing_target, delta * 20.0)
	
	data.happiness = clamp(50 - (100 - data.energy) * 0.005 + (data.job_satisfaction * 0.01 if data.job != "" else -data.job_satisfaction * 0.01) + (data.housing_satisfaction - 50.0) * 0.1, 0, 100)
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

	# Wander timer (skipped while actively gathering, building, or delivering)
	if not is_gathering and not is_building and not is_delivering:
		wander_timer -= delta
		if is_on_floor() and wander_timer > 0:
			if data.energy > 0.0:
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
	
	if not nav_agent.is_navigation_finished() and data.energy > 0.0:
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
	
	# Slow citizen if citizen need food
	if data.energy < 50.0:
		var energy_mult = clamp(data.energy * 0.02, 0.25, 1.0)
		velocity.x *= energy_mult
		velocity.z *= energy_mult
	
	data.energy -= (data.metabolism + data.metabolism * Vector3(velocity.x, 0, velocity.z).length()) * delta
	data.energy = clamp(data.energy, 0, 100)
	
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
		
	if position.y < -10:
		velocity = Vector3.ZERO
		position = Vector3(randf_range(-5, 5), 1, randf_range(-5, 5))

func _on_velocity_computed(safe_velocity: Vector3):
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z

# Derives housing status directly from builder.buildings (the source of
# truth for occupancy) instead of a since-removed has_housing_for() call.
# A citizen is housed if their id appears in any BuildingInstance's residents.
func _refresh_housing_status() -> void:
	if builder == null:
		return
	_has_housing = false
	for instance in builder.buildings.values():
		if data.id in instance.residents:
			_has_housing = true
			break
	
	# Citizens without housing/a job just wander until the player assigns them
	# something via CitizenSelector -> PolicyEngine (or a future policy).

func _start_gathering() -> void:
	var cell = builder.get_nearest_gatherable(global_position)
	if cell == NO_CELL:
		return
	_start_gathering_at(cell)

func _start_gathering_at(cell: Vector3i) -> void:
	# Targeted version -- player assigned this specific tree via click (A.3).
	# Also used by _start_gathering() after it resolves the nearest cell.
	gather_target_cell = cell
	is_gathering = true
	set_new_destination(Vector3(cell.x, cell.y, cell.z))

func _update_gathering(delta: float) -> void:
	if not is_gathering:
		return
	if builder == null:
		is_gathering = false
		return
	
	# Tree already destroyed, go somewhere else
	var structure_index = builder.gridmap.get_cell_item(gather_target_cell)
	if structure_index < 0 or structure_index >= builder.structures.size() or not builder.structures[structure_index].gatherable:
		is_gathering = false
		_start_gathering()
		return
	
	# Still walking -- no progress, UNLESS already physically close enough
	# (guards against is_navigation_finished() never triggering -- see WORK_REACH).
	var target_world_pos = Vector3(gather_target_cell.x, global_position.y, gather_target_cell.z)
	var close_enough = global_position.distance_to(target_world_pos) <= WORK_REACH
	if not nav_agent.is_navigation_finished() and not close_enough:
		return
	
	# Arrived -- contribute labor toward the shared, persisted chop progress.
	var gather_time = builder.structures[structure_index].gather_time
	var energy_required = builder.structures[structure_index].energy_required
	data.energy = clamp(data.energy - energy_required * delta, 0.0, 100.0)
	# add_chop_progress returns a Dictionary (not a bool) -- it's ALWAYS
	# truthy since it always has keys, even mid-chop. Must check the
	# "completed" key explicitly, not the dict itself.
	var result: Dictionary = builder.add_chop_progress(gather_target_cell, delta / gather_time)
	if result.get("completed", false):
		is_gathering = false
		var energy_bonus: float = result.get("energy_bonus", 0.0)
		if energy_bonus > 0.0:
			data.energy = clamp(data.energy + energy_bonus, 0.0, 100.0)
		var resource_type: String = result.get("resource_type", "")
		var resource_yield: int = result.get("resource_yield", 0)
		if resource_type != "" and resource_yield > 0:
			carried_resources[resource_type] = carried_resources.get(resource_type, 0) + resource_yield
		_try_deliver_or_resume_gathering()

# Called once a gather finishes. If carrying resources, walk them to the
# nearest active construction site (#4 -- wood only counts once it's
# physically delivered). If none exists right now, per the design ("if
# theres none they just carry it") the citizen simply keeps gathering with
# the resources still on hand -- delivery is re-attempted after every
# future gather completes, and a site may appear in the meantime.
func _try_deliver_or_resume_gathering() -> void:
	if carried_resources.is_empty() or builder == null:
		_start_gathering()
		return
	var cell = builder.get_nearest_construction_site(global_position)
	if cell == builder.NO_GATHERABLE_CELL:
		_start_gathering()
	else:
		_start_delivering(cell)

# Begins walking a load of carried resources to a construction site
func _start_delivering(cell: Vector3i) -> void:
	deliver_target_cell = cell
	is_delivering = true
	set_new_destination(Vector3(cell.x, cell.y, cell.z))

func _update_delivering(_delta: float) -> void:
	if not is_delivering:
		return
	if builder == null:
		is_delivering = false
		return

	# Site finished, got demolished, or otherwise vanished mid-walk -- look for
	# another site to deliver to (or just resume gathering while carrying).
	if not builder.construction_sites.has(deliver_target_cell):
		is_delivering = false
		deliver_target_cell = NO_CELL
		_try_deliver_or_resume_gathering()
		return

	var target_world_pos = Vector3(deliver_target_cell.x, global_position.y, deliver_target_cell.z)
	var close_enough = global_position.distance_to(target_world_pos) <= WORK_REACH
	if not nav_agent.is_navigation_finished() and not close_enough:
		return

	# Arrived -- hand the carried load off to the shared stockpile.
	builder.deposit_resources(carried_resources)
	carried_resources.clear()
	is_delivering = false
	deliver_target_cell = NO_CELL
	_start_gathering()

# Begins walking to an already-assigned construction site
func _start_building(cell: Vector3i) -> void:
	build_target_cell = cell
	is_building = true
	set_new_destination(Vector3(cell.x, cell.y, cell.z))

func _update_building(delta: float) -> void:
	if not is_building:
		return
	if builder == null:
		is_building = false
		return
	
	# Site finished, got demolished, or was unassigned -- stop walking toward it
	if not builder.construction_sites.has(build_target_cell):
		is_building = false
		build_target_cell = NO_CELL
		return
	
	var site = builder.construction_sites[build_target_cell]
	if not data.id in site.assigned_builders:
		is_building = false
		build_target_cell = NO_CELL
		return
	
	# Building costs energy while actively assigned to a site -- same
	# per-second model as gathering (see Structure.build_energy_required).
	var structure: Structure = builder.structures[site.structure_index]
	data.energy = clamp(data.energy - structure.build_energy_required * delta, 0.0, 100.0)

func set_new_destination(target):
	nav_agent.target_position = target

func update_happiness_color():
	# Green when happy, red when unhappy
	var t = data.happiness / 100.0
	happiness_material.albedo_color = Color(1.0 - t, t, 0.0)
