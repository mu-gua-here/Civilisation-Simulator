extends CharacterBody3D

const SPEED = 0.15
const JUMP_VELOCITY = 2.0
const FRICTION = 0.8

var view_node:Node3D

# Health/damage
@export var max_health: float = 100.0
var health: float = max_health
@export var invuln_time: float = 0.5  # seconds of immunity after being hit
var invuln_timer: float = 0.0

# STATS BAR
@onready var stat_bars_display: Sprite3D = $Sprite3D  # or whatever your Sprite3D is named
@onready var hunger_bar: ProgressBar = $SubViewport/VBoxContainer/HungerBar
@onready var health_bar: ProgressBar = $SubViewport/VBoxContainer/HealthBar
@onready var stat_viewport: SubViewport = $SubViewport

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

	# Layer in knockback and let it decay over time
	if knockback.length() > 0.01:
		velocity.x += knockback.x
		velocity.z += knockback.z
		knockback = knockback.move_toward(Vector3.ZERO, KNOCKBACK_FRICTION * delta)

	# Tick down hit-immunity window
	if invuln_timer > 0.0:
		invuln_timer -= delta

	move_and_slide()
	
	update_stat_bars()
	
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

func update_stat_bars():
	if not Globals.player:
		stat_bars_display.visible = false
		stat_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	
	hunger_bar.value = Globals.player_hunger
	health_bar.value = Globals.player_health

func _on_death() -> void:
	# Placeholder — hook up a respawn/game-over screen later
	print("Player died.")
	health = max_health
	position = Vector3i(0, 1, 0)
	velocity = Vector3.ZERO
	knockback = Vector3.ZERO
	health_changed.emit(health, max_health)
