extends CharacterBody3D

# Constants
var plane := Plane(Vector3.UP, Vector3.ZERO)

var builder: Node = null
var view_node: Node3D

# Distance NPC/Player needs to be from a gatherable/construction cell to
# work it -- shared by both gathering and building.
const GATHER_REACH := 1.5
const NO_CELL := Vector3i(NAN, NAN, NAN)

# ID the player registers under in ConstructionSite.assigned_builders --
# distinct format from citizen ids (6-digit strings) so it can't collide.
const PLAYER_BUILDER_ID := "player_builder"

# Gathering (click-and-hold)
var is_gathering: bool = false
var gather_target_cell: Vector3i = NO_CELL

# Carrying gathered resources back to a construction site (#4 -- resources no
# longer auto-add to the stockpile on gather; the player physically carries
# what they chopped and it's deposited automatically on walking near an
# active construction site -- see _update_carried_delivery()).
var carried_resources: Dictionary = {}
const DELIVER_REACH := 1.5

# Building (click-and-hold) -- registers the player in the same
# ConstructionSite.assigned_builders array citizens use, so progress accrual
# stays in builder._process_construction() and isn't duplicated here.
var is_building_task: bool = false
var build_target_cell: Vector3i = NO_CELL

# Player stats
@export var SPEED = 0.15
@export var JUMP_VELOCITY = 2.0
@export var FRICTION = 0.8

# Player physiological settings
@export var max_health: float = 100.0
@export_range(0.0, 100.0) var health: float = max_health
@export_range(0.0, 100.0) var energy: float = 100.0
@export var invuln_time: float = 0.5  # seconds of immunity after being hit
var invuln_timer: float = 0.0
@export var metabolism: float = 0.001

# Knockback
var knockback: Vector3 = Vector3.ZERO
const KNOCKBACK_FRICTION = 6.0  # how fast knockback decays per second

signal health_changed(current: float, max: float)
signal died

func _ready():
	position = Vector3i(0, 1, 0)
	add_to_group("player")
	view_node = get_tree().get_first_node_in_group("view")
	Globals.register_player(self)
	health = max_health
	builder = get_tree().get_first_node_in_group("builder")

func _physics_process(delta: float) -> void:
	# Add the gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and energy > 0.0:
		velocity.y = JUMP_VELOCITY
		energy -= velocity.y * 0.1

	# Get the input direction and handle the movement/deceleration.
	var cam_basis = view_node.rotation.y if view_node else 0.0
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, cam_basis).normalized()
	var is_running:int = Input.is_action_pressed("run")
	if direction:
		velocity.x += direction.x * SPEED * (is_running + 1)
		velocity.z += direction.z * SPEED * (is_running + 1)
	
	energy -= (metabolism + Vector3(velocity.x, 0, velocity.z).length() * metabolism) * delta
	
	# Apply slowing down of velocity
	velocity.x *= FRICTION
	velocity.z *= FRICTION
	
	# Slow player if player need food
	if energy < 50.0:
		var energy_mult = clamp(energy * 0.02, 0.25, 1.0)
		velocity.x *= energy_mult
		velocity.z *= energy_mult

	# Layer in knockback and let it decay over time
	if knockback.length() > 0.01:
		velocity.x += knockback.x
		velocity.z += knockback.z
		knockback = knockback.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)

	# Tick down hit-immunity window
	if invuln_timer > 0.0:
		invuln_timer -= delta
	
	if energy < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
	
	Globals.set_player_energy(energy)
	
	_update_gathering(delta)
	_update_building_task(delta)
	_update_carried_delivery()
	
	move_and_slide()
	
	if position.y < -10:
		velocity = Vector3.ZERO
		position = Vector3i(0, 1, 0)

# Called by attackers (e.g. angry citizens). Ignored while invulnerable.
func take_damage(amount: float, source_position: Vector3 = global_position, knockback_force: float = 4.0) -> void:
	if invuln_timer > 0.0:
		return
	
	health = clamp(health - amount, 0.0, max_health)
	Globals.set_player_health(health)
	invuln_timer = invuln_time
	
	# Push the player directly away from whatever hit them
	var push_dir = global_position - source_position
	push_dir.y = 0
	push_dir = push_dir.normalized() if push_dir.length() > 0.01 else Vector3.FORWARD
	knockback = push_dir * knockback_force
	velocity.y = max(velocity.y, 1.0)  # small upward pop on hit, tweak/remove to taste
	
	health_changed.emit(health, max_health)
	
	if health <= 0.0:
		died.emit()
		_on_death()

func _on_death() -> void:
	# Placeholder — hook up a respawn/game-over screen later
	print("Player died.")
	health = max_health
	position = Vector3i(0, 1, 0)
	velocity = Vector3.ZERO
	knockback = Vector3.ZERO
	health_changed.emit(health, max_health)

func _unhandled_input(event: InputEvent) -> void:
	# Click-AND-HOLD to gather a resource OR help build a construction site --
	# same gesture, branches on what's under the cursor (see _try_start_work).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_work(event.position)
		else:
			_stop_work()

func _try_start_work(screen_pos: Vector2) -> void:
	if builder == null or builder.interact_mode:
		return
	# A citizen is selected -- this click is for assigning them (see
	# CitizenSelector), not for the player's own work.
	var selector = get_tree().get_first_node_in_group("citizen_selector")
	if selector and selector.selected_citizen != null:
		return
	
	var cell = _raycast_cell_in_reach(screen_pos)
	if cell == NO_CELL:
		return
	
	# Construction site takes priority over gathering at the same cell (a
	# site clears the gridmap tile to -1 while building, so in practice the
	# two never actually overlap -- this is just an explicit precedence).
	if builder.construction_sites.has(cell):
		build_target_cell = cell
		is_building_task = true
		builder.assign_builder_to_site(PLAYER_BUILDER_ID, cell)
		get_viewport().set_input_as_handled()
		return
	
	var si = builder.gridmap.get_cell_item(cell)
	if si >= 0 and si < builder.structures.size() and builder.structures[si].gatherable:
		gather_target_cell = cell
		is_gathering = true
		get_viewport().set_input_as_handled()

func _stop_work() -> void:
	_stop_gathering()
	_stop_building_task()

func _stop_gathering() -> void:
	is_gathering = false
	gather_target_cell = NO_CELL

func _stop_building_task() -> void:
	if is_building_task and builder != null:
		builder.release_builder(PLAYER_BUILDER_ID)
	is_building_task = false
	build_target_cell = NO_CELL

# Called every physics frame while the mouse button is held (see _physics_process).
func _update_gathering(delta: float) -> void:
	if not is_gathering:
		return
	if builder == null:
		_stop_gathering()
		return
	
	# Tree already destroyed (by us or someone/something else) -- stop.
	var structure_index = builder.gridmap.get_cell_item(gather_target_cell)
	if structure_index < 0 or structure_index >= builder.structures.size() or not builder.structures[structure_index].gatherable:
		_stop_gathering()
		return
	
	# Wandered out of reach while holding -- stop rather than gathering at a distance.
	var world_pos = Vector3(gather_target_cell.x, global_position.y, gather_target_cell.z)
	if global_position.distance_to(world_pos) > GATHER_REACH:
		_stop_gathering()
		return
	
	var gather_time = builder.structures[structure_index].gather_time
	var energy_required = builder.structures[structure_index].energy_required
	energy = clamp(energy - energy_required * delta, 0.0, 100.0)
	# add_chop_progress returns a Dictionary (not a bool) -- it's ALWAYS
	# truthy since it always has keys, even mid-chop. Must check the
	# "completed" key explicitly, not the dict itself.
	var result: Dictionary = builder.add_chop_progress(gather_target_cell, delta / gather_time)
	if result.get("completed", false):
		var energy_bonus: float = result.get("energy_bonus", 0.0)
		if energy_bonus > 0.0:
			energy = clamp(energy + energy_bonus, 0.0, 100.0)
		var resource_type: String = result.get("resource_type", "")
		var resource_yield: int = result.get("resource_yield", 0)
		if resource_type != "" and resource_yield > 0:
			carried_resources[resource_type] = carried_resources.get(resource_type, 0) + resource_yield
		_stop_gathering()

# Checked every physics frame (not just while holding the gather button) --
# if the player is carrying resources and wanders within DELIVER_REACH of
# any active construction site, hand the load off automatically. No extra
# input needed; walking it over there IS the delivery action.
func _update_carried_delivery() -> void:
	if carried_resources.is_empty() or builder == null:
		return
	for cell in builder.construction_sites.keys():
		var world_pos = Vector3(cell.x, global_position.y, cell.z)
		if global_position.distance_to(world_pos) <= DELIVER_REACH:
			builder.deposit_resources(carried_resources)
			carried_resources.clear()
			return

# Called every physics frame while the mouse button is held on a construction
# site. Progress itself accrues in builder._process_construction() purely by
# virtue of PLAYER_BUILDER_ID being present in assigned_builders -- this only
# needs to validate the hold is still legitimate and pay the energy cost.
func _update_building_task(delta: float) -> void:
	if not is_building_task:
		return
	if builder == null:
		_stop_building_task()
		return
	
	# Site finished or got demolished mid-hold -- stop.
	if not builder.construction_sites.has(build_target_cell):
		_stop_building_task()
		return
	
	# Wandered out of reach while holding -- stop, same as gathering.
	var world_pos = Vector3(build_target_cell.x, global_position.y, build_target_cell.z)
	if global_position.distance_to(world_pos) > GATHER_REACH:
		_stop_building_task()
		return
	
	var site = builder.construction_sites[build_target_cell]
	var structure: Structure = builder.structures[site.structure_index]
	energy = clamp(energy - structure.build_energy_required * delta, 0.0, 100.0)

func _raycast_cell_in_reach(screen_pos: Vector2) -> Vector3i:
	# Raycast from the camera into the world, return the cell if it's within
	# GATHER_REACH of the player. Returns NO_CELL otherwise. Caller decides
	# what to actually do with the cell (gather vs. build).
	if builder == null or view_node == null:
		return NO_CELL
	var camera = view_node.get_node_or_null("Camera")
	if camera == null:
		return NO_CELL
	
	var world_position = plane.intersects_ray(
		camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos))
	
	# Return invalid values
	if world_position == null:
		return NO_CELL

	var cell = Vector3(round(world_position.x), 0, round(world_position.z))
	
	var world_pos = Vector3(cell.x, global_position.y, cell.z)
	if global_position.distance_to(world_pos) > GATHER_REACH:
		return NO_CELL
	return cell
