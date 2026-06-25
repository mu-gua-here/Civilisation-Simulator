extends Node3D
class_name CitizenSelector

## Click a citizen to see their full stats in a panel. Click again (or click
## empty space) to deselect.

@export var view_camera: Camera3D
@export var max_select_distance: float = 100.0
@export var panel_offset: Vector2 = Vector2(40, -60)  # offset from citizen's screen pos to panel's top-left
@export var ring_color: Color = Color(1.0, 0.85, 0.2)

var selected_citizen: Node3D = null
var panel: PanelContainer
var name_label: Label
var stats_label: RichTextLabel
var ui_layer: CanvasLayer
var ring: MeshInstance3D

func _ready() -> void:
	_build_ui()
	_build_ring()
	# Try to auto-find the camera if not assigned, so this works even if you
	# forget to wire it up in the Inspector.
	if view_camera == null:
		var view_node = get_tree().get_first_node_in_group("view")
		if view_node and view_node.has_node("Camera"):
			view_camera = view_node.get_node("Camera")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_select_at(event.position)

func _try_select_at(screen_pos: Vector2) -> void:
	if view_camera == null:
		return
	
	var space_state = get_world_3d().direct_space_state
	var from = view_camera.project_ray_origin(screen_pos)
	var to = from + view_camera.project_ray_normal(screen_pos) * max_select_distance
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	var result = space_state.intersect_ray(query)
	
	if result and result.collider and result.collider.is_in_group("citizen"):
		if selected_citizen == result.collider:
			_deselect()
		else:
			_select(result.collider)
	else:
		_deselect()

func _select(citizen: Node3D) -> void:
	selected_citizen = citizen
	panel.visible = true
	ring.visible = true
	_refresh_panel()

func _deselect() -> void:
	selected_citizen = null
	panel.visible = false
	ring.visible = false

func _process(_delta: float) -> void:
	if selected_citizen and is_instance_valid(selected_citizen):
		_refresh_panel()
		_update_ring_position()
		_update_panel_position()
	elif selected_citizen:
		# Citizen was freed (e.g. removed from the world) while selected
		_deselect()

func _update_ring_position() -> void:
	# Flat ring sitting just above the ground at the citizen's feet, always
	# flat (no billboarding needed -- a ground ring reads fine from any angle).
	ring.global_position = selected_citizen.global_position + Vector3(0, 0.05, 0)

func _update_panel_position() -> void:
	if view_camera == null:
		return
	
	var screen_pos = view_camera.unproject_position(selected_citizen.global_position)
	
	# Don't show the panel if the citizen is behind the camera (unproject_position
	# can return a misleading on-screen point in that case).
	var cam_to_citizen = selected_citizen.global_position - view_camera.global_position
	if view_camera.global_transform.basis.z.dot(cam_to_citizen) > 0:
		panel.visible = false
		return
	panel.visible = true
	
	var target_pos = screen_pos + panel_offset
	
	# Clamp so the panel stays fully on-screen even if the citizen wanders
	# near a viewport edge. panel.size can be (0,0) for a single frame right
	# after becoming visible (before layout runs), so fall back to the
	# minimum size in that case to avoid a one-frame jump to the corner.
	var panel_size = panel.size if panel.size.length_squared() > 1.0 else panel.custom_minimum_size
	var viewport_size = get_viewport().get_visible_rect().size
	target_pos.x = clamp(target_pos.x, 0, viewport_size.x - panel_size.x)
	target_pos.y = clamp(target_pos.y, 0, viewport_size.y - panel_size.y)
	
	panel.position = target_pos

func _refresh_panel() -> void:
	var d = selected_citizen.data
	if d == null:
		return
	
	name_label.text = d.name if d.name != "" else "Citizen"
	
	var job_text = d.job if d.job != "" else "Unemployed"
	var happiness_pct = int(clamp(d.happiness, 0.0, 100.0))
	var health_pct = int(clamp(d.health, 0.0, 100.0))
	var hunger_pct = int(clamp(d.hunger, 0.0, 100.0))
	
	stats_label.clear()
	stats_label.append_text("[b]Age:[/b] %d\n" % d.age)
	stats_label.append_text("[b]Job:[/b] %s\n" % job_text)
	stats_label.append_text("\n")
	stats_label.append_text("[b]Happiness:[/b] %s\n" % _bar_text(happiness_pct))
	stats_label.append_text("[b]Health:[/b] %s\n" % _bar_text(health_pct))
	stats_label.append_text("[b]Hunger:[/b] %s\n" % _bar_text(hunger_pct))
	
	if selected_citizen.has_method("get") and "is_chasing_player" in selected_citizen:
		if selected_citizen.is_chasing_player:
			stats_label.append_text("\n[color=#ff5555][b]Hostile -- chasing player![/b][/color]")

func _bar_text(pct: int) -> String:
	var filled = int(pct / 10.0)
	var bar = "█".repeat(filled) + "░".repeat(10 - filled)
	var color = "#5fd35f" if pct > 60 else ("#e0c84a" if pct > 30 else "#e05f5f")
	return "[color=%s]%s[/color] %d%%" % [color, bar, pct]

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	
	panel = PanelContainer.new()
	panel.visible = false
	# Free-floating: top-left anchored at (0,0,0,0) so `panel.position` directly
	# controls where it sits on screen -- this is what lets it follow the
	# citizen instead of staying pinned to a screen corner.
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.custom_minimum_size = Vector2(560, 368)  # 2x width, 2x height = 4x area vs. original 280x184
	ui_layer.add_child(panel)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.92)
	style.border_color = ring_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(name_label)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	stats_label.add_theme_font_size_override("normal_font_size", 22)
	stats_label.add_theme_font_size_override("bold_font_size", 22)
	stats_label.custom_minimum_size = Vector2(520, 280)
	vbox.add_child(stats_label)

func _build_ring() -> void:
	# Flat circular outline on the ground beneath the selected citizen.
	# Built from a TorusMesh flattened on Y so it reads as a ring, not a donut.
	var torus = TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.7
	torus.rings = 24
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ring_color
	mat.emission_enabled = true
	mat.emission = ring_color
	mat.emission_energy_multiplier = 1.5
	torus.material = mat
	
	ring = MeshInstance3D.new()
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.15, 1.0)  # flatten the torus into a ground ring
	ring.visible = false
	add_child(ring)
