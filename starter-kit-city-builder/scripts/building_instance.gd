extends Resource
class_name BuildingInstance

## Tracks occupancy for a single placed structure (one gridmap cell).
## Built/rebuilt at runtime by Builder whenever structures are placed or
## removed -- NOT persisted to DataMap/save files. On load, occupancy is
## recomputed from scratch and citizens re-claim slots as needed.

@export var cell: Vector3i           # gridmap cell this building occupies
@export var structure_index: int     # index into builder.structures

@export var residents: Array[String] = []  # citizen ids currently housed here
@export var workers: Array[String] = []    # citizen ids currently employed here
