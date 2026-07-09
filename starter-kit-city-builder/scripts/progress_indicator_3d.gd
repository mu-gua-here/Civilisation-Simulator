extends Node3D
class_name ProgressIndicator3D

## A single floating progress bar, billboarded toward the camera. Same construction sites and
## gathering trees can reuse it without duplicating the SubViewport setup.
##
## Usage: instantiate, add_child it, set bar_color if you want something
## other than the default green, then call set_progress(0..1) each tick.
## Distance-to-player gating (visibility + render pause) is the caller's
## job via set_visible_in_range(), same as citizen.gd's BAR_VISIBLE_DISTANCE
## pattern -- a tree or construction site knows its own "is this worth
## rendering" logic better than this generic node does.

@onready var sprite: Sprite3D = $Sprite3D
@onready var viewport: SubViewport = $Sprite3D/SubViewport
@onready var bar: ProgressBar = $Sprite3D/SubViewport/ProgressBar

@export var bar_color: Color = Color(0.4050653, 0.765706, 0.2580341, 1) # matches citizen HappinessBar fill green
@export var bg_color: Color = Color(0.16745102, 0.16745105, 0.16745093, 1) # matches citizen bar background

var _fill_style: StyleBoxFlat
var _bg_style: StyleBoxFlat

func _ready() -> void:
	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = bg_color
	_bg_style.corner_radius_top_left = 10
	_bg_style.corner_radius_top_right = 10
	_bg_style.corner_radius_bottom_right = 10
	_bg_style.corner_radius_bottom_left = 10

	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = bar_color
	_fill_style.corner_radius_top_left = 10
	_fill_style.corner_radius_top_right = 10
	_fill_style.corner_radius_bottom_right = 10
	_fill_style.corner_radius_bottom_left = 10

	bar.add_theme_stylebox_override("background", _bg_style)
	bar.add_theme_stylebox_override("fill", _fill_style)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0

	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func set_progress(value01: float) -> void:
	bar.value = clamp(value01, 0.0, 1.0)

# Changes the fill color after the fact -- used by construction sites to
# flag "stalled, missing resources" (e.g. a red/orange tint) without needing
# a second bar node.
func set_bar_color(new_color: Color) -> void:
	bar_color = new_color
	if _fill_style != null:
		_fill_style.bg_color = new_color

func set_visible_in_range(in_range: bool) -> void:
	sprite.visible = in_range
	viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if in_range else SubViewport.UPDATE_DISABLED
	)
