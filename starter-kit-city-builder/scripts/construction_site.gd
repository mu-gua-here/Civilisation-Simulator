extends Resource
class_name ConstructionSite

## Tracks an in-progress structure placement. Created by action_build()
## instead of an instant gridmap.set_cell_item -- a structure is now planned,
## then built, consuming committed resources and builder labor over time.
##
## "Auto-approved instantly" per the plan: the player is the only authority
## that exists yet, so a ConstructionSite starts immediately upon placement.
## This is a deliberate placeholder -- see "Deferred" in the plan doc
## ("Real approval for construction plans") for what replaces this once
## governance exists.

@export var cell: Vector3i
@export var structure_index: int
@export var orientation: int = 0       # gridmap orthogonal index, preserved from placement (rotation)
@export var progress: float = 0.0      # 0..1
@export var resources_committed: Dictionary = {}   # resource_type (String) -> amount already drawn from stockpile
@export var assigned_builders: Array[String] = []  # citizen ids currently working this site

func is_complete() -> bool:
	return progress >= 1.0
