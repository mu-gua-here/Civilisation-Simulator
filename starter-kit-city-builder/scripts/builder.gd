extends Node3D

@export var structures: Array[Structure] = []

var map:DataMap

var index:int = 0 # Index of structure being built

@export var selector:Node3D # The 'cursor'
@export var selector_container:Node3D # Node that holds a preview of the structure
@export var view_camera:Camera3D # Used for raycasting mouse
@export var gridmap:GridMap
@export var citizen_scene: PackedScene
@export var nav_region: NavigationRegion3D

var citizens = []

var grass_structure_index: int = -1
var tree_structure_index: int = -1
var tall_tree_structure_index: int = -1

var buildings: Dictionary = {} # Vector3i (cell) -> BuildingInstance, for placed HOUSE/SHOP/WORKPLACE structures

var construction_sites: Dictionary = {} # Vector3i (cell) -> ConstructionSite, for structures still being built (A.4)
# NOTE: Real staged visuals (scaffold/walls/roof) are still deferred
var construction_visuals: Dictionary = {} # Vector3i (cell) -> { "ghost": Node3D, "bar": ProgressIndicator3D }

const ProgressIndicatorScene := preload("res://scenes/progress_indicator_3d.tscn")
const ConstructionTileScene := preload("res://models/primitive/construction.scn")
const GHOST_BAR_HEIGHT := 1.5 # local Y offset above a construction ghost's origin
const GATHER_BAR_HEIGHT := 0.8 # local Y offset above a gathered tree's origin
const PROGRESS_BAR_VISIBLE_DISTANCE := 8.0

var gather_visuals: Dictionary = {} # Vector3i (cell) -> ProgressIndicator3D, for trees actively being chopped

# Persisted chop progress, 0.0-1.0, keyed by cell to store progress
var gather_progress: Dictionary = {}

var plane:Plane # Used for raycasting mouse

var worldSize = 25
var interact_mode:bool = true  # Toggle between building and movement modes

# Pathfinding perf vars
var _nav_bake_pending := false
var _nav_bake_timer := 0.0
const NAV_BAKE_DELAY := 0.3  # seconds to wait for more changes before baking

# UI
var hotbar_page: int = 0  # which page of 10 structure slots the player is on

var resource_display: Label = null # shows the player's stockpile (wood, etc.)
var resource_ui_layer: CanvasLayer = null
var build_hint_label: Label = null # transient warnings (e.g. "not enough wood") -- corner backup, see _flash_build_hint
var build_hint_timer: float = 0.0
const BUILD_HINT_DURATION := 3.0 # seconds a build hint stays visible
var carrying_label: Label = null # shows what the player is currently carrying (see player.gd carried_resources)
var active_hint_label3d: Label3D = null # the actual primary warning -- floats above the site/tile in question

func _ready():
	
	add_to_group("builder")
	
	map = DataMap.new()
	plane = Plane(Vector3.UP, Vector3.ZERO)
	
	# Create new MeshLibrary dynamically, can also be done in the editor
	# See: https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html
	
	var mesh_library = MeshLibrary.new()
	
	for structure in structures:
		
		var id = mesh_library.get_last_unused_item_id()
		
		mesh_library.create_item(id)
		var mesh_data = get_mesh_and_transform(structure.model)
		mesh_library.set_item_mesh(id, mesh_data.get("mesh"))
		mesh_library.set_item_mesh_transform(id, mesh_data.get("transform", Transform3D()))
		
		var sh_result = get_collision_shape(structure)
		mesh_library.set_item_shapes(id, sh_result)
	
	gridmap.mesh_library = mesh_library
	
	grass_structure_index = _find_structure_index("grass.tres")
	tree_structure_index = _find_structure_index("grass-trees.tres")
	tall_tree_structure_index = _find_structure_index("grass-trees-tall.tres")
	
	if grass_structure_index < 0:
		push_error("Builder: grass not found in `structures` -- check main.tscn wiring")

	if tree_structure_index < 0:
		push_error("Builder: grass-trees not found in `structures` -- check main.tscn wiring")

	if tall_tree_structure_index < 0:
		push_error("Builder: grass-trees-tall not found in `structures` -- check main.tscn wiring")
	
	# Generate a goofy-ahh grid of grass w/ trees to start
	
	# Unequal probability distribution so that more grass than trees
	var tree_rng := RandomNumberGenerator.new()
	var weights := [0.8, 0.15, 0.05]
	var trees := [grass_structure_index, tree_structure_index, tall_tree_structure_index]
	
	for i in range(-worldSize, worldSize):
		for j in range(-worldSize, worldSize):
			var picked_index: int
			if (true):
				picked_index = trees[tree_rng.rand_weighted(weights)]
			else:
				if (i < -10 or i > 10):
					picked_index = tall_tree_structure_index
				elif (j < -10 or j > 10):
					picked_index = tree_structure_index
				else:
					picked_index = grass_structure_index
			
			gridmap.set_cell_item(Vector3i(i, 0, j), picked_index)
	
	# Save starting scene so won't be empty when reload
	action_save()
	
	# Bake pathfinding mesh
	if nav_region != null:
		_request_nav_bake()
	
	update_structure()
	_build_resource_display()
	spawn_citizens(5)
	_rebuild_buildings()
	
	# Initialise selector to match variable
	interact_mode = !interact_mode
	selector_container.visible = interact_mode
	selector.visible = interact_mode

# Handle different types of collision meshes in Godot
# Returns a FLAT array of alternating [shape, transform, shape, transform, ...] pairs
func get_collision_shape(structure: Structure) -> Array:
	var model = structure.model
	if model is PackedScene:
		return get_collision_shape_from_scene(model, structure)
	else:
		return [model, Transform3D()]

func get_collision_shape_from_scene(scene: PackedScene, structure: Structure = null) -> Array:
	var inst := scene.instantiate()
	add_child(inst)

	# First: look for an explicitly named collision node as placed in editor
	var cs := inst.find_child("CollisionShape3D", true, false)
	if cs != null and cs is CollisionShape3D:
		var shape = (cs as CollisionShape3D).shape
		var xform = (cs as CollisionShape3D).transform
		inst.queue_free()
		return [shape, xform]

	# No explicit collision node -- build a ConcavePolygonShape3D (trimesh) from
	# every MeshInstance3D's faces, combined in the instance root's local space.
	#
	# This briefly used a single ConvexPolygonShape3D (hull) instead, to avoid a
	# "one-way wall" bug where something that ended up INSIDE a structure got
	# shoved back out. That bug's actual root cause was a separate rendering bug
	# (a multi-part model like the hut only rendering one of its parts, leaving
	# the rest walkable-looking but still solid) -- now fixed in
	# get_mesh_and_transform()/_merge_all_meshes(). A single hull over an entire
	# multi-part model has its own real cost, though: it's the convex closure of
	# EVERY vertex across every part, so a squared base merged with a separate
	# roof balloons out toward the model's full bounding footprint -- exactly
	# the "acts like an AABB" behavior reported. Trimesh doesn't have that
	# problem (it hugs the actual geometry exactly) and its one-sidedness is a
	# much smaller practical risk now that render and collision actually match.
	var faces := PackedVector3Array()
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var relative_xform = inst.global_transform.affine_inverse() * mi.global_transform
		for v in mi.mesh.get_faces():
			faces.append(relative_xform * v)

	inst.queue_free()

	if faces.is_empty():
		return [BoxShape3D.new(), Transform3D()] # no mesh geometry found -- shouldn't normally happen

	var trimesh := ConcavePolygonShape3D.new()
	trimesh.set_faces(faces)
	return [trimesh, Transform3D()]

# Generic runtime-collision helper: wraps get_collision_shape_from_scene()'s
# fallback trimesh baking into a ready-to-place StaticBody3D. Works for ANY
# PackedScene lacking its own CollisionShape3D -- not construction-tile
# specific -- so any future model missing collision can reuse this.
func _build_trimesh_collision_body(scene: PackedScene) -> StaticBody3D:
	var result = get_collision_shape_from_scene(scene)
	var shape = result[0]
	var xform = result[1]
	
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = xform
	body.add_child(collider)
	return body
	
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
	
	_process_construction(delta)
	_update_progress_bar_visibility()
	_update_carrying_display()
	
	if build_hint_timer > 0.0:
		build_hint_timer -= delta
		if build_hint_timer <= 0.0:
			if build_hint_label != null:
				build_hint_label.visible = false
			if active_hint_label3d != null:
				active_hint_label3d.queue_free()
				active_hint_label3d = null

# Finds a structure's index by its .tres filename -- see grass_structure_index etc.
func _find_structure_index(filename: String) -> int:
	for i in structures.size():
		if structures[i].resource_path.get_file() == filename:
			return i
	return -1

# Retrieves a mesh AND its local transform from a PackedScene by
# instantiating it and walking the live node tree -- the same approach
# get_collision_shape_from_scene() uses -- rather than scanning SceneState
# directly (which only sees properties overridden at THIS scene's own save
# level, so a MeshInstance3D whose `mesh` is actually set deeper in an
# inherited/nested scene was invisible to it -- that's why some structures
# rendered perfectly while others, e.g. the hut, placed and collided but
# never rendered).
#
# IMPORTANT: GridMap's MeshLibrary only supports ONE mesh per item id. A
# multi-part model (e.g. the hut: separate MeshInstance3D nodes for walls
# and roof) needs ALL of its parts merged into a single mesh with multiple
# surfaces -- just grabbing the first MeshInstance3D found (an earlier
# version of this function did exactly that) silently drops every part
# after the first, which is why only the hut's roof cone was ever showing.
func get_mesh_and_transform(packed_scene: PackedScene) -> Dictionary:
	var inst := packed_scene.instantiate()
	add_child(inst)
	
	var result := {}
	var merged := _merge_all_meshes(inst)
	if merged.get_surface_count() > 0:
		result["mesh"] = merged
		# Each part's own offset is already baked into the merged mesh's vertex
		# data (relative to inst's own origin) by _merge_all_meshes -- no
		# additional item-level transform is needed on top of that.
		result["transform"] = Transform3D()
	
	inst.queue_free()
	return result

# Merges every MeshInstance3D under `inst` into a single ArrayMesh, one
# surface per source surface, with each part's vertices/normals baked into
# object space relative to `inst`'s own origin (so the result can be used
# directly as a MeshLibrary item mesh with an identity transform).
func _merge_all_meshes(inst: Node) -> ArrayMesh:
	var merged := ArrayMesh.new()
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var relative_xform = inst.global_transform.affine_inverse() * mi.global_transform
		var normal_basis = relative_xform.basis.orthonormalized()
		
		for surf in mi.mesh.get_surface_count():
			var arrays = mi.mesh.surface_get_arrays(surf)
			if arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var new_verts := PackedVector3Array()
			new_verts.resize(verts.size())
			for i in verts.size():
				new_verts[i] = relative_xform * verts[i]
			arrays[Mesh.ARRAY_VERTEX] = new_verts
			
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var new_normals := PackedVector3Array()
				new_normals.resize(normals.size())
				for i in normals.size():
					new_normals[i] = (normal_basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = new_normals
			
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var new_surf_idx = merged.get_surface_count() - 1
			var mat = mi.get_active_material(surf)
			if mat:
				merged.surface_set_material(new_surf_idx, mat)
	
	return merged

# Build (place) a structure

func action_build(gridmap_position):
	if Input.is_action_just_pressed("build"):
		
		var cell := Vector3i(gridmap_position)
		var cell_world_pos := Vector3(cell.x, cell.y, cell.z)
		var previous_tile = gridmap.get_cell_item(gridmap_position)
		
		if previous_tile == index:
			return # already this structure -- nothing to do
		if previous_tile != grass_structure_index:
			_flash_build_hint("Area not cleared for construction yet.", cell_world_pos)
			return # Tile not cleared yet, cannot build stuff
		if construction_sites.has(cell):
			_flash_build_hint("A site is already under construction there.", cell_world_pos)
			return
		
		_warn_if_insufficient_resources(structures[index], cell_world_pos)
		_start_construction(cell, index, gridmap.get_orthogonal_index_from_basis(selector.basis))
		
		Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)

# Flashes a heads-up if the stockpile can't currently cover the full
# build_cost -- construction still starts (per the "auto-approve" design in
# _start_construction), it'll simply sit stalled (see _process_construction,
# which also tints the site's progress bar red while this is true) until
# enough resources are gathered and delivered.
#
# Also flags when the player is CARRYING enough to cover the shortfall but
# hasn't delivered it yet -- "I have 30 wood" (carried) and "the site has 0
# wood" (stockpile) are two different numbers now that gathering doesn't
# auto-add to the stockpile (see player.gd/citizen.gd carried_resources),
# and that distinction is exactly what was confusing without this note.
func _warn_if_insufficient_resources(structure: Structure, world_pos: Vector3) -> void:
	var missing: Array[String] = []
	for resource_type in structure.build_cost.keys():
		var needed: int = structure.build_cost[resource_type]
		var available: int = map.stockpile.get(resource_type, 0)
		if available < needed:
			var note := ""
			if Globals.player and ("carried_resources" in Globals.player):
				var carried: int = Globals.player.carried_resources.get(resource_type, 0)
				if carried > 0:
					note = " -- you're carrying %d, walk it here to deliver" % carried
			missing.append("%s (%d/%d)%s" % [String(resource_type).capitalize(), available, needed, note])
	if not missing.is_empty():
		_flash_build_hint("Not enough resources yet -- site will wait for: " + ", ".join(missing), world_pos)

# Demolish (remove) a structure

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish"):
		var cell := Vector3i(gridmap_position)
		if construction_sites.has(cell):
			construction_sites.erase(cell)
			_clear_construction_visual(cell)
			gridmap.set_cell_item(gridmap_position, grass_structure_index)
			_rebuild_buildings()
			if nav_region != null:
				_request_nav_bake()
			Audio.play("sounds/removal-a.ogg, sounds/removal-b.ogg, sounds/removal-c.ogg, sounds/removal-d.ogg", -20)
			return

# Toggle between building mode and movement mode

func action_interact_mode():
	if InputMap.has_action("interact_mode") and Input.is_action_just_pressed("interact_mode"):
		interact_mode = !interact_mode
		selector_container.visible = interact_mode
		selector.visible = interact_mode
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

# --- Resource stockpile UI -------------------------------------------------

# Create resource when showing progress bar for trees etc

func _build_resource_display() -> void:
	resource_ui_layer = CanvasLayer.new()
	add_child(resource_ui_layer)

	resource_display = Label.new()
	resource_display.add_theme_font_size_override("font_size", 22)
	resource_display.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	resource_display.add_theme_constant_override("shadow_offset_x", 2)
	resource_display.add_theme_constant_override("shadow_offset_y", 2)
	resource_display.position = Vector2(20, 90)
	resource_ui_layer.add_child(resource_display)

	build_hint_label = Label.new()
	build_hint_label.add_theme_font_size_override("font_size", 20)
	build_hint_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35))
	build_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	build_hint_label.add_theme_constant_override("shadow_offset_x", 2)
	build_hint_label.add_theme_constant_override("shadow_offset_y", 2)
	build_hint_label.position = Vector2(20, 120)
	build_hint_label.visible = false
	resource_ui_layer.add_child(build_hint_label)

	carrying_label = Label.new()
	carrying_label.add_theme_font_size_override("font_size", 18)
	carrying_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.5))
	carrying_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	carrying_label.add_theme_constant_override("shadow_offset_x", 2)
	carrying_label.add_theme_constant_override("shadow_offset_y", 2)
	carrying_label.position = Vector2(20, 150)
	carrying_label.visible = false
	resource_ui_layer.add_child(carrying_label)

	update_resource_display()

# Shows a build/site warning two ways: a floating Label3D anchored right
# above world_pos (the primary, actually-readable feedback -- addresses it
# being "very small and not very visible" stuck in the corner before), plus
# the corner label as a redundant backup for when the site isn't currently
# in view. world_pos defaults to Vector3.INF, meaning "no specific location"
# -- in that case only the corner label is shown.
func _flash_build_hint(text: String, world_pos: Vector3 = Vector3.INF) -> void:
	if build_hint_label != null:
		build_hint_label.text = text
		build_hint_label.visible = true
	build_hint_timer = BUILD_HINT_DURATION
	
	if active_hint_label3d != null:
		active_hint_label3d.queue_free()
		active_hint_label3d = null
	
	if world_pos == Vector3.INF:
		return
	
	var label3d := Label3D.new()
	label3d.text = text
	label3d.font_size = 40
	label3d.outline_size = 12
	label3d.modulate = Color(1.0, 0.55, 0.35)
	label3d.outline_modulate = Color(0, 0, 0, 0.85)
	label3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label3d.no_depth_test = true
	label3d.width = 400
	label3d.position = world_pos + Vector3(0, 2.2, 0)
	add_child(label3d)
	active_hint_label3d = label3d

func update_resource_display() -> void:
	if resource_display == null:
		return
	if map.stockpile.is_empty():
		resource_display.text = ""
		return
	var parts: Array[String] = []
	for key in map.stockpile.keys():
		parts.append("%s: %d" % [String(key).capitalize(), map.stockpile[key]])
	resource_display.text = " | ".join(parts)

# Reflects the player's carried_resources (set in player.gd on a completed
# gather, cleared once delivered to a construction site) -- lets the player
# see what they're holding since it no longer auto-adds to the stockpile (#4).
func _update_carrying_display() -> void:
	if carrying_label == null:
		return
	if not Globals.player or not ("carried_resources" in Globals.player):
		carrying_label.visible = false
		return
	var carried: Dictionary = Globals.player.carried_resources
	if carried.is_empty():
		carrying_label.visible = false
		return
	var parts: Array[String] = []
	for key in carried.keys():
		parts.append("%s: %d" % [String(key).capitalize(), carried[key]])
	carrying_label.text = "Carrying: " + ", ".join(parts)
	carrying_label.visible = true

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
		
		_rebuild_buildings()
		
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
		
		_rebuild_buildings()
		
		if nav_region != null:
			# Rebuild pathfinding mesh
			_request_nav_bake()
		
		print("Prebuilt map loaded...")

func spawn_citizens(count: int):
	for i in count:
		var c = citizen_scene.instantiate()
		add_child(c)
		c.global_position = Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
		c.data.id = "%06d" % randi_range(0, 999999)
		citizens.append(c)

# --- Building occupancy (housing / jobs) ---------------------------------

# Rebuild the buildings dictionary from the current gridmap state.
func _rebuild_buildings() -> void:
	var old_buildings = buildings
	buildings = {}
	
	for cell in gridmap.get_used_cells():
		var structure_index = gridmap.get_cell_item(cell)
		if structure_index < 0 or structure_index >= structures.size():
			continue
		
		var structure = structures[structure_index]
		var is_housing = structure.type == Structure.Type.HOUSE or structure.type == Structure.Type.SHOP
		var is_workplace = structure.type == Structure.Type.WORKPLACE
		
		if not is_housing and not is_workplace:
			continue # purely decorative, nothing to track
		
		var instance: BuildingInstance
		if old_buildings.has(cell) and old_buildings[cell].structure_index == structure_index:
			# Same structure still here -- keep its existing occupants
			instance = old_buildings[cell]
		else:
			# New building, or the structure at this cell changed -- start fresh.
			instance = BuildingInstance.new()
			instance.cell = cell
			instance.structure_index = structure_index
		
		buildings[cell] = instance

# Finds the nearest placed structure of a given type to a world position.
func get_nearest_structure_of_type(pos: Vector3, type: Structure.Type) -> Vector3:
	var nearest_pos := Vector3.INF
	var nearest_dist := INF
	
	for instance in buildings.values():
		if structures[instance.structure_index].type != type:
			continue
		var world_pos = Vector3(instance.cell.x, instance.cell.y, instance.cell.z)
		var dist = pos.distance_squared_to(world_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = world_pos
	
	return nearest_pos

# --- Resource gathering ----------------------------------

# Finds the nearest gatherable structure (e.g. a tree) to a world position.

const NO_GATHERABLE_CELL := Vector3i(NAN, NAN, NAN)

func get_nearest_gatherable(pos: Vector3) -> Vector3i:
	var nearest_cell := NO_GATHERABLE_CELL
	var nearest_dist := INF
	
	for cell in gridmap.get_used_cells():
		var structure_index = gridmap.get_cell_item(cell)
		if structure_index < 0 or structure_index >= structures.size():
			continue
		if not structures[structure_index].gatherable:
			continue
		
		var world_pos = Vector3(cell.x, cell.y, cell.z)
		var dist = pos.distance_squared_to(world_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_cell = cell
	
	return nearest_cell

# Attempts to gather the resource at the given cell. Returns what was
# granted -- {"resource_type": String, "resource_yield": int} -- rather than
# adding it straight to the stockpile. The gatherer (player/citizen) now
# carries this until it's physically delivered via deposit_resources().
func gather_resource_at(cell: Vector3i) -> Dictionary:
	var structure_index = gridmap.get_cell_item(cell)
	if structure_index < 0 or structure_index >= structures.size():
		return {}
	
	var structure = structures[structure_index]
	if not structure.gatherable:
		return {}
	
	# Destroy the tree (per design: chopping is permanent, player must replant)
	gridmap.set_cell_item(cell, grass_structure_index)
	clear_chop_progress(cell)
	
	_rebuild_buildings() # gridmap changed, keep buildings dict in sync
	
	if nav_region != null:
		_request_nav_bake() # tree was a nav obstacle; removing it changes walkable space
	
	if structure.resource_type == "":
		return {}
	return {"resource_type": structure.resource_type, "resource_yield": structure.resource_yield}

# Adds carried resources (e.g. from gather_resource_at) into the shared
# stockpile -- called once a gatherer physically delivers what they're
# carrying to a construction site (or wherever a drop-off point ends up
# being). ConstructionSite._commit_resources() draws from map.stockpile
# automatically, so nothing else needs to change once this is called.
func deposit_resources(resources: Dictionary) -> void:
	if resources.is_empty():
		return
	for key in resources.keys():
		map.stockpile[key] = map.stockpile.get(key, 0) + resources[key]
	update_resource_display()

# --- Construction pipeline (A.4) ------------------------------------------

# NOTE: For now, no authority to approve/reject building plan, approval is automatic

func _start_construction(cell: Vector3i, structure_index: int, orientation: int) -> void:
	var structure := structures[structure_index]
	
	var site := ConstructionSite.new()
	site.cell = cell
	site.structure_index = structure_index
	site.orientation = orientation
	construction_sites[cell] = site
	
	# Leave the cell empty (-1)
	gridmap.set_cell_item(cell, -1)
	_spawn_construction_visual(cell, structure, orientation)

# Ticks every active construction site forward based on assigned builder labor.
# Only builders CURRENTLY WITHIN REACH of the site contribute labor this
# frame -- being in assigned_builders means "I'm walking there / I'm the
# one responsible for this", not "I'm actively working it right now". Without
# this check, progress started accruing the instant a citizen was assigned,
# even while they were still nav-walking from the other side of the map.
func _process_construction(delta: float) -> void:
	if construction_sites.is_empty():
		return
	
	var completed_cells: Array[Vector3i] = []
	
	for cell in construction_sites.keys():
		var site: ConstructionSite = construction_sites[cell]
		var structure := structures[site.structure_index]
		
		_commit_resources(site, structure)
		
		var fully_committed := _resources_fully_committed(site, structure)
		if construction_visuals.has(cell):
			var bar: ProgressIndicator3D = construction_visuals[cell]["bar"]
			if fully_committed:
				bar.set_bar_color(Color(0.6, 0.6, 0.65)) # neutral grey-blue -- resourced
			else:
				bar.set_bar_color(Color(0.85, 0.35, 0.25)) # stalled -- missing resources
		
		if not fully_committed:
			continue # waiting on the stockpile -- builders stand by, no progress yet
		
		if site.assigned_builders.is_empty():
			continue # no labor assigned yet -- nothing progresses on its own
		
		var builders_in_range := _count_builders_in_range(site, cell)
		if builders_in_range <= 0:
			continue # assigned, but nobody has physically arrived yet
		
		var labor := float(builders_in_range) * delta
		site.progress = clamp(site.progress + labor / max(structure.build_time, 0.01), 0.0, 1.0)
		
		if construction_visuals.has(cell):
			construction_visuals[cell]["bar"].set_progress(site.progress)
		
		if site.is_complete():
			completed_cells.append(cell)
	
	for cell in completed_cells:
		_complete_construction(cell)

# Reach a builder must be within to actively contribute labor -- matches
# citizen.gd's WORK_REACH and player.gd's GATHER_REACH (kept as a separate
# constant here since builder.gd can't reference either script's directly).
const BUILD_LABOR_REACH := 1.5

# Player registers under this id in assigned_builders -- must match
# player.gd's PLAYER_BUILDER_ID.
const PLAYER_BUILDER_ID := "player_builder"

# Counts how many of a site's assigned_builders are CURRENTLY within
# BUILD_LABOR_REACH of the site's cell (as opposed to just "assigned", which
# only means "walking there or responsible for it").
func _count_builders_in_range(site: ConstructionSite, cell: Vector3i) -> int:
	var site_world_pos := Vector3(cell.x, cell.y, cell.z)
	var count := 0
	for builder_id in site.assigned_builders:
		var node: Node3D = null
		if builder_id == PLAYER_BUILDER_ID:
			node = Globals.player
		else:
			for c in citizens:
				if is_instance_valid(c) and c.data != null and c.data.id == builder_id:
					node = c
					break
		if node == null or not is_instance_valid(node):
			continue
		if node.global_position.distance_to(site_world_pos) <= BUILD_LABOR_REACH:
			count += 1
	return count

# Draws as much of build_cost from the stockpile as is currently available,
# tracking what's been committed so far so it's only drawn once.
func _commit_resources(site: ConstructionSite, structure: Structure) -> void:
	var drew_any := false
	for resource_type in structure.build_cost.keys():
		var needed: int = structure.build_cost[resource_type]
		var already: int = site.resources_committed.get(resource_type, 0)
		if already >= needed:
			continue
		
		var available: int = map.stockpile.get(resource_type, 0)
		var to_draw: int = min(needed - already, available)
		if to_draw <= 0:
			continue
		
		map.stockpile[resource_type] = available - to_draw
		site.resources_committed[resource_type] = already + to_draw
		drew_any = true
	
	if drew_any:
		update_resource_display()

func _resources_fully_committed(site: ConstructionSite, structure: Structure) -> bool:
	for resource_type in structure.build_cost.keys():
		var needed: int = structure.build_cost[resource_type]
		var committed: int = site.resources_committed.get(resource_type, 0)
		if committed < needed:
			return false
	return true

func _complete_construction(cell: Vector3i) -> void:
	var site: ConstructionSite = construction_sites[cell]
	construction_sites.erase(cell)
	
	# Release builders from the finished site
	_clear_construction_visual(cell)
	gridmap.set_cell_item(cell, site.structure_index, site.orientation)
	_rebuild_buildings() # resolves into the normal BuildingInstance system
	
	if nav_region != null:
		_request_nav_bake()
	
	Audio.play("sounds/placement-a.ogg, sounds/placement-b.ogg, sounds/placement-c.ogg, sounds/placement-d.ogg", -20)

# Finds the nearest active construction site to a world position
func get_nearest_construction_site(pos: Vector3) -> Vector3i:
	var nearest_cell := NO_GATHERABLE_CELL
	var nearest_dist := INF
	
	for cell in construction_sites.keys():
		var world_pos = Vector3(cell.x, cell.y, cell.z)
		var dist = pos.distance_squared_to(world_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_cell = cell
	
	return nearest_cell

# Assigns a citizen (or the player) as a builder on the site at the given
# cell. A builder can only actively work one site at a time -- release them
# from any other site first, otherwise they'd silently count as labor on
# both simultaneously (double-counted progress).
func assign_builder_to_site(citizen_id: String, cell: Vector3i) -> bool:
	if not construction_sites.has(cell):
		return false
	release_builder(citizen_id)
	var site: ConstructionSite = construction_sites[cell]
	if not citizen_id in site.assigned_builders:
		site.assigned_builders.append(citizen_id)
	return true

# Releases a citizen from whatever construction site they're assigned to, if any
func release_builder(citizen_id: String) -> void:
	for site in construction_sites.values():
		site.assigned_builders.erase(citizen_id)

# --- Construction & gather progress visuals --------------------------------
#
# Both construction sites and gathered trees get a floating progress bar

# Spawns the translucent grey "ghost" of a structure's real model, the
# physical construction tile marker (walkable), and a progress bar above both
func _spawn_construction_visual(cell: Vector3i, structure: Structure, orientation: int) -> void:
	var ghost := structure.model.instantiate()
	ghost.position = Vector3(cell.x, cell.y, cell.z)
	ghost.transform.basis = gridmap.get_basis_with_orthogonal_index(orientation)
	add_child(ghost)
	_apply_ghost_material(ghost)
	
	var construction := ConstructionTileScene.instantiate()
	construction.position = Vector3(cell.x, cell.y, cell.z)
	construction.transform.basis = gridmap.get_basis_with_orthogonal_index(orientation)
	add_child(construction)
	
	# construction-tile.tscn doesn't ship its own collision -- bake one from its
	# mesh geometry (same convex-hull fallback logic used for gridmap structures)
	# so the player/citizens can walk on the site instead of falling through
	# it while under construction.
	var tile_body := _build_trimesh_collision_body(ConstructionTileScene)
	tile_body.position = Vector3(cell.x, cell.y, cell.z)
	tile_body.transform.basis = gridmap.get_basis_with_orthogonal_index(orientation)
	add_child(tile_body)
	
	var bar: ProgressIndicator3D = ProgressIndicatorScene.instantiate()
	add_child(bar)
	bar.position = Vector3(cell.x, cell.y + GHOST_BAR_HEIGHT, cell.z)
	bar.bar_color = Color(0.6, 0.6, 0.65) # neutral grey-blue, distinct from citizen happiness green and the gather bar
	bar.set_progress(0.0)
	
	construction_visuals[cell] = {"ghost": ghost, "construction": construction, "tile_body": tile_body, "bar": bar}

# Recursively swaps every MeshInstance3D's surface materials in the ghost for a single shared translucent grey override
func _apply_ghost_material(node: Node) -> void:
	var ghost_material := StandardMaterial3D.new()
	ghost_material.albedo_color = Color(0.5, 0.5, 0.5, 0.45)
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_apply_material_recursive(node, ghost_material)

func _apply_material_recursive(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)
	# Ghosts are visual-only -- strip any collision the real model might carry
	if node is CollisionShape3D or node is CollisionObject3D:
		node.queue_free()
		return
	for child in node.get_children():
		_apply_material_recursive(child, material)

# Removes a construction site's ghost + tile + bar, if any
func _clear_construction_visual(cell: Vector3i) -> void:
	if not construction_visuals.has(cell):
		return
	var visual = construction_visuals[cell]
	visual["ghost"].queue_free()
	visual["construction"].queue_free()
	visual["tile_body"].queue_free()
	visual["bar"].queue_free()
	construction_visuals.erase(cell)

# Shows the gather progress bar for a tree at given cell
func update_gather_progress(cell: Vector3i, progress01: float) -> void:
	if not gather_visuals.has(cell):
		var bar: ProgressIndicator3D = ProgressIndicatorScene.instantiate()
		add_child(bar)
		bar.position = Vector3(cell.x, cell.y + GATHER_BAR_HEIGHT, cell.z)
		bar.bar_color = Color(0.8, 0.4, 0.1) # matches citizen HungerBar orange
		gather_visuals[cell] = bar
	gather_visuals[cell].set_progress(progress01)

# Removes a resource's gather bar when finished
func clear_gather_progress(cell: Vector3i) -> void:
	if not gather_visuals.has(cell):
		return
	gather_visuals[cell].queue_free()
	gather_visuals.erase(cell)

# --- Chop progress (persisted) ---------------------------------------------

func get_chop_progress(cell: Vector3i) -> float:
	return gather_progress.get(cell, 0.0)

# amount01 is a fraction of the total work (0..1) contributed by this call.
# Returns {"completed": bool, "energy_bonus": float, "resource_type": String,
# "resource_yield": int} -- energy_bonus and the resource fields are only
# meaningful the tick a gather actually completes. energy_bonus is > 0 when
# structure.food_chance rolls true (e.g. a tree occasionally carrying
# something edible); the resource fields are what the caller should now
# carry (see Builder.deposit_resources) rather than an automatic stockpile add.
func add_chop_progress(cell: Vector3i, amount: float) -> Dictionary:
	var structure_index = gridmap.get_cell_item(cell)
	if structure_index < 0 or structure_index >= structures.size():
		return {"completed": false, "energy_bonus": 0.0}
	var structure = structures[structure_index]
	if not structure.gatherable:
		return {"completed": false, "energy_bonus": 0.0}
	
	var progress = clamp(gather_progress.get(cell, 0.0) + amount, 0.0, 1.0)
	gather_progress[cell] = progress
	update_gather_progress(cell, progress)
	
	if progress >= 1.0:
		var energy_bonus := 0.0
		if randf() < structure.food_chance:
			energy_bonus = structure.food_energy_bonus
		var yield_info := gather_resource_at(cell)
		return {
			"completed": true,
			"energy_bonus": energy_bonus,
			"resource_type": yield_info.get("resource_type", ""),
			"resource_yield": yield_info.get("resource_yield", 0),
		}
	return {"completed": false, "energy_bonus": 0.0}

# Clears both the persisted numeric progress and the visual bar for a cell
func clear_chop_progress(cell: Vector3i) -> void:
	gather_progress.erase(cell)
	clear_gather_progress(cell)

# Converts a world-space hit position (e.g. from a raycast) to its gridmap cell
func world_to_cell(world_pos: Vector3) -> Vector3i:
	var cell = gridmap.local_to_map(gridmap.to_local(world_pos))
	cell.y = 0
	return cell

# Distance-gates every active progress bar against the player each frame
func _update_progress_bar_visibility() -> void:
	if not Globals.player:
		return
	var player_pos = Globals.player.global_position
	
	for visual in construction_visuals.values():
		var bar: ProgressIndicator3D = visual["bar"]
		var in_range = bar.global_position.distance_to(player_pos) < PROGRESS_BAR_VISIBLE_DISTANCE
		bar.set_visible_in_range(in_range)
	
	for bar in gather_visuals.values():
		var in_range = bar.global_position.distance_to(player_pos) < PROGRESS_BAR_VISIBLE_DISTANCE
		bar.set_visible_in_range(in_range)
