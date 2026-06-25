extends Node3D

@export var structures: Array[Structure] = []

var map:DataMap

var index:int = 0 # Index of structure being built

@export var selector:Node3D # The 'cursor'
@export var selector_container:Node3D # Node that holds a preview of the structure
@export var view_camera:Camera3D # Used for raycasting mouse
@export var gridmap:GridMap
@export var cash_display:Label
@export var citizen_scene: PackedScene
@export var nav_region: NavigationRegion3D

var citizens = []

var plane:Plane # Used for raycasting mouse

var worldSize = 25
var interact_mode:bool = true  # Toggle between building and movement modes

# Pathfinding perf vars
var _nav_bake_pending := false
var _nav_bake_timer := 0.0
const NAV_BAKE_DELAY := 0.3  # seconds to wait for more changes before baking

# UI
var hotbar_page: int = 0  # which page of 10 structure slots the player is on

func _ready():
	
	map = DataMap.new()
	plane = Plane(Vector3.UP, Vector3.ZERO)
	
	# Generate a goofy-ahh grid of grass to start
	for i in range(-worldSize, worldSize):
		for j in range(-worldSize, worldSize):
			gridmap.set_cell_item(Vector3i(i, 0, j), 12)
	
	# Save starting scene so won't be empty
	action_save()
	
	# Generate border
	# generate_border()
	
	# Create new MeshLibrary dynamically, can also be done in the editor
	# See: https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html
	
	var mesh_library = MeshLibrary.new()
	
	for structure in structures:
		
		var id = mesh_library.get_last_unused_item_id()
		
		mesh_library.create_item(id)
		mesh_library.set_item_mesh(id, get_mesh(structure.model))
		mesh_library.set_item_mesh_transform(id, Transform3D())
		
		mesh_library.set_item_shapes(id, [get_collision_shape(structure.model), Transform3D()])

		
	gridmap.mesh_library = mesh_library
	
	# Bake pathfinding mesh
	if nav_region != null:
		_request_nav_bake()
	
	update_structure()
	update_cash()
	spawn_citizens(100)
	
func _bake_nav():
	if nav_region != null and nav_region.navigation_mesh != null:
		nav_region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nav_region.navigation_mesh.geometry_collision_mask = 1

		var half_extent = float(worldSize) + 1.0  # small margin past the playable grid
		nav_region.navigation_mesh.filter_baking_aabb = AABB(
			Vector3(-half_extent, -2.0, -half_extent),
			Vector3(half_extent * 2.0, 4.0, half_extent * 2.0)
		)

		nav_region.bake_navigation_mesh(true)
	
func _request_nav_bake():
	_nav_bake_pending = true
	_nav_bake_timer = NAV_BAKE_DELAY
	
func _process(delta):
	
	# Controls
	action_interact_mode() # Toggle between building and movement modes
	action_rotate() # Rotates selection 90 degrees
	action_structure_toggle() # Toggles between structures
	
	action_save() # Saving
	action_load() # Loading
	action_load_resources() # Loading from resources
	
	# Map position based on mouse
	var world_position = plane.intersects_ray(
		view_camera.project_ray_origin(get_viewport().get_mouse_position()),
		view_camera.project_ray_normal(get_viewport().get_mouse_position()))
	
	# Return invalid values
	if world_position == null:
		return

	var gridmap_position = Vector3(round(world_position.x), 0, round(world_position.z))
	
	# Only show selector and process building in building mode
	if interact_mode:
		selector.position = lerp(selector.position, gridmap_position, min(delta * 40, 1.0))
		action_build(gridmap_position)
		action_demolish(gridmap_position)
	
	if _nav_bake_pending:
		_nav_bake_timer -= delta
		if _nav_bake_timer <= 0.0:
			_nav_bake_pending = false
			_bake_nav()

# Retrieve the mesh from a PackedScene, used for dynamically creating a MeshLibrary

func get_mesh(packed_scene):
	var scene_state:SceneState = packed_scene.get_state()
	for i in range(scene_state.get_node_count()):
		if(scene_state.get_node_type(i) == "MeshInstance3D"):
			for j in scene_state.get_node_property_count(i):
				var prop_name = scene_state.get_node_property_name(i, j)
				if prop_name == "mesh":
					var prop_value = scene_state.get_node_property_value(i, j)
					
					return prop_value.duplicate()

func get_collision_shape(packed_scene):
	var mesh = get_mesh(packed_scene)
	var shape = mesh.create_trimesh_shape()
	return shape

# Build (place) a structure

func action_build(gridmap_position):
	if Input.is_action_just_pressed("build"):
		
		var previous_tile = gridmap.get_cell_item(gridmap_position)
		gridmap.set_cell_item(gridmap_position, index, gridmap.get_orthogonal_index_from_basis(selector.basis))
		
		if previous_tile != index:
			map.cash -= structures[index].price
			update_cash()
			
			if nav_region != null:
				# Rebuild pathfinding mesh
				_request_nav_bake()
			
			Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)

# Demolish (remove) a structure

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish"):
		if gridmap.get_cell_item(gridmap_position) != -1:
			gridmap.set_cell_item(gridmap_position, -1)
			
			if nav_region != null:
				# Rebuild pathfinding mesh
				_request_nav_bake()
			
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)

# Toggle between building mode and movement mode

func action_interact_mode():
	if InputMap.has_action("interact_mode") and Input.is_action_just_pressed("interact_mode"):
		interact_mode = !interact_mode
		selector_container.visible = interact_mode
		selector.visible = interact_mode
		print("Mode switched to: " + ("Building" if interact_mode else "Movement"))
		if Audio:
			Audio.play("sounds/toggle.ogg", -30)

# Rotates the 'cursor' 90 degrees

func action_rotate():
	if Input.is_action_just_pressed("rotate"):
		selector.rotate_y(deg_to_rad(90))
		
		Audio.play("sounds/rotate.ogg", -30)

# Toggle between structures to build

func action_structure_toggle():
	# Direct hotbar select: keys 1-9, 0 map to slots 0-9 of the current page
	var page_count = ceili(float(structures.size()) / 10.0)
	for i in range(10):
		if Input.is_action_just_pressed("selection_%d" % i):
			var target = hotbar_page * 10 + i
			if target < structures.size():
				index = target
				Audio.play("sounds/toggle.ogg", -30)

	# Page through the hotbar when there are more than 10 structures
	if Input.is_action_just_pressed("hotbar_page_next"):
		hotbar_page = wrap(hotbar_page + 1, 0, page_count)
		Audio.play("sounds/toggle.ogg", -30)

	if Input.is_action_just_pressed("hotbar_page_prev"):
		hotbar_page = wrap(hotbar_page - 1, 0, page_count)
		Audio.play("sounds/toggle.ogg", -30)

	update_structure()

# Update the structure visual in the 'cursor'

func update_structure():
	# Clear previous structure preview in selector
	for n in selector_container.get_children():
		selector_container.remove_child(n)
	
	# Create new structure preview in selector
	var _model = structures[index].model.instantiate()
	selector_container.add_child(_model)
	_model.position.y += 0.25
	
func update_cash():
	cash_display.text = "$" + str(map.cash)

# Saving/load

func action_save():
	if Input.is_action_just_pressed("save"):
		print("Saving map...")
		
		map.structures.clear()
		for cell in gridmap.get_used_cells():
			
			var data_structure:DataStructure = DataStructure.new()
			
			data_structure.position = Vector2i(cell.x, cell.z)
			data_structure.orientation = gridmap.get_cell_item_orientation(cell)
			data_structure.structure = gridmap.get_cell_item(cell)
			
			map.structures.append(data_structure)
			
		ResourceSaver.save(map, "user://map.res")
		
		print("Map saved.")
	
func action_load():
	if Input.is_action_just_pressed("load"):
		print("Loading map...")
		
		gridmap.clear()
		
		map = ResourceLoader.load("user://map.res")
		if not map:
			map = DataMap.new()
		for cell in map.structures:
			gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
			
		update_cash()
		
		if nav_region != null:
			# Rebuild pathfinding mesh
			_request_nav_bake()
		
		print("Map loaded.")

func action_load_resources():
	if Input.is_action_just_pressed("load_resources"):
		print("Loading prebuilt map...")
		
		gridmap.clear()
		
		map = ResourceLoader.load("res://sample map/map.res")
		if not map:
			map = DataMap.new()
		for cell in map.structures:
			gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
			
		update_cash()
		
		if nav_region != null:
			# Rebuild pathfinding mesh
			_request_nav_bake()
		
		print("Prebuilt map loaded...")

func spawn_citizens(count: int):
	for i in count:
		var c = citizen_scene.instantiate()
		add_child(c)
		c.global_position = Vector3(
			randf_range(-20, 20),
			1.0,
			randf_range(-20, 20)
			)
		citizens.append(c)

func generate_border():
	for i in range(-worldSize, worldSize + 1):
		# North and south edges
		place_mountain(Vector3i(i, 0, -worldSize))
		place_mountain(Vector3i(i, 0, worldSize))
		# East and west edges
		place_mountain(Vector3i(-worldSize, 0, i))
		place_mountain(Vector3i(worldSize, 0, i))

		# Double up the ring for a thicker mountain range
		place_mountain(Vector3i(i, 0, -worldSize - 1))
		place_mountain(Vector3i(i, 0, worldSize + 1))
		place_mountain(Vector3i(-worldSize - 1, 0, i))
		place_mountain(Vector3i(worldSize + 1, 0, i))

		# Add a second height layer for visual depth
		place_mountain(Vector3i(i, 1, -worldSize))
		place_mountain(Vector3i(i, 1, worldSize))
		place_mountain(Vector3i(-worldSize, 1, i))
		place_mountain(Vector3i(worldSize, 1, i))

func place_mountain(pos: Vector3i):
	var mountain_tile = 14
	gridmap.set_cell_item(pos, mountain_tile)
