extends Resource
class_name DataMap

@export var structures:Array[DataStructure]

@export var stockpile: Dictionary = {"wood": 0} # resource_type (String) -> amount. More keys (e.g. "stone") added as they're introduced.

@export var lifetime_gathered: Dictionary = {} # resource_type (String) -> total EVER gathered, never decremented on spend. Checked against Structure.unlock_requirements so unlocks don't get re-locked after spending resources.
