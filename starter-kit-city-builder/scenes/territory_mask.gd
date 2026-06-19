extends Node
class_name TerritoryMask

## Manages a world-space "revealed territory" mask used to drive fog-of-void.
## Each built tile spawns a soft circular brush that grows over time, so
## newly built areas smoothly expand the visible region instead of popping
## in instantly. The mask is camera-independent — it only cares about
## world XZ position, so fog never "follows" the player.

# --- Configuration ---

@export var mask_resolution: int = 512          # Pixels per side of the mask texture
@export var world_extent: float = 80.0          # World units the mask covers (centered at origin), auto-set by builder.gd from worldSize
@export var reveal_radius_tiles: float = 4.0     # Patch half-size around each built tile, in world units
@export var grow_duration: float = 1.5           # Seconds for a brush to grow from 0 to full size
@export var edge_softness: float = 0.15          # 0-1, fraction of size used for soft falloff at brush edge

# --- Internal state ---

var _image: Image
var _texture: ImageTexture
var _active_brushes: Array = []   # Array of {world_pos: Vector2, age: float}
var _dirty: bool = true

func _ready() -> void:
	_image = Image.create(mask_resolution, mask_resolution, false, Image.FORMAT_R8)
	_image.fill(Color(0, 0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)

func get_texture() -> ImageTexture:
	return _texture

## Call this whenever a structure is placed. world_pos is the XZ world position.
func reveal_at(world_pos: Vector2) -> void:
	_active_brushes.append({"world_pos": world_pos, "age": 0.0})
	_dirty = true

func _process(delta: float) -> void:
	if _active_brushes.is_empty():
		return

	var still_animating := false
	for brush in _active_brushes:
		if brush["age"] < grow_duration:
			brush["age"] = min(brush["age"] + delta, grow_duration)
			still_animating = true

	if still_animating or _dirty:
		_redraw()
		_dirty = false

func _world_to_pixel(world_pos: Vector2) -> Vector2:
	# world_extent spans [-world_extent/2, world_extent/2] -> [0, mask_resolution]
	var u := (world_pos.x + world_extent * 0.5) / world_extent
	var v := (world_pos.y + world_extent * 0.5) / world_extent
	return Vector2(u * mask_resolution, v * mask_resolution)

func _redraw() -> void:
	# Rebuild the whole mask each time a brush is animating.
	# For very large numbers of brushes you'd want incremental drawing,
	# but for a city-builder's structure count this is cheap enough.
	_image.fill(Color(0, 0, 0, 0))

	for brush in _active_brushes:
		var progress: float = brush["age"] / grow_duration
		var eased: float = ease(progress, 0.3)  # fast start, soft settle
		var radius_world: float = reveal_radius_tiles * eased
		if radius_world <= 0.01:
			continue

		_stamp_square(brush["world_pos"], radius_world)

	_texture.update(_image)

func _stamp_square(world_pos: Vector2, half_size_world: float) -> void:
	var center_px := _world_to_pixel(world_pos)
	var px_per_world := mask_resolution / world_extent
	var half_px: float = half_size_world * px_per_world
	var soft_px: float = half_px * edge_softness

	var min_x: int = max(0, int(center_px.x - half_px - soft_px))
	var max_x: int = min(mask_resolution - 1, int(center_px.x + half_px + soft_px))
	var min_y: int = max(0, int(center_px.y - half_px - soft_px))
	var max_y: int = min(mask_resolution - 1, int(center_px.y + half_px + soft_px))

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			# Chebyshev distance (max of axis distances) gives a square footprint
			# instead of the circular footprint Euclidean distance produces.
			var dist: float = max(abs(x - center_px.x), abs(y - center_px.y))
			var value: float = 1.0 - smoothstep(half_px - soft_px, half_px, dist)
			if value <= 0.0:
				continue
			var existing: float = _image.get_pixel(x, y).r
			if value > existing:
				_image.set_pixel(x, y, Color(value, 0, 0, value))
