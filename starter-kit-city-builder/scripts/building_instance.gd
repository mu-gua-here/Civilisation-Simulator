extends Resource
class_name BuildingInstance

## Tracks occupancy for a single placed structure (one gridmap cell)

@export var cell: Vector3i           # gridmap cell this building occupies
@export var structure_index: int     # index into builder.structures

@export var residents: Array[String] = []  # citizen ids currently housed here
@export var workers: Array[String] = []    # citizen ids currently employed here
