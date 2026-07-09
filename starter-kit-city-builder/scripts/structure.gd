extends Resource
class_name Structure

# What role this structure plays in the simulation
enum Type { DECORATIVE, HOUSE, WORKPLACE, SHOP }

@export_subgroup("Model")
@export var model:PackedScene # Model of the structure

@export_subgroup("Gameplay")
@export var type: Type = Type.DECORATIVE # What role this structure plays
@export var capacity: int = 0 # Job slots if WORKPLACE (unused for HOUSE — see residential_floors below)
@export var happiness_bonus: float = 0.0 # Passive happiness boost for nearby citizens (decorative structures)

@export_subgroup("Housing")
@export var residential_floors: int = 0 # Floors usable as housing (HOUSE/SHOP types). Each floor = 1 household, household size rolled 2-6 at move-in.
@export var commercial_floors: int = 0 # Floors usable as shopfront (SHOP type). Not yet used by gameplay — reserved for the economy system.

@export_subgroup("Resources")
@export var gatherable: bool = false # If true, citizens can chop/mine this structure for raw resources
@export var resource_type: String = "" # e.g. "wood", "stone" — matches a key in DataMap's stockpile
@export var resource_yield: int = 0 # Amount granted to the stockpile per gather
@export var gather_time: float = 3.0 # Seconds a citizen must spend gathering before the yield is granted
@export var clicks_required: int = 10 # Number of player clicks needed to fully gather this node
@export var energy_required: float = 1.0 # Energy collecting the resource costs player/NPC
@export_range(0.0, 1.0) var food_chance: float = 0.1 # chance this gatherable yields bonus energy for whoever chops it down (e.g. a tree occasionally carrying something edible)
@export var food_energy_bonus: float = 15.0 # energy granted to the gatherer on a successful food_chance roll

@export_subgroup("Construction")
@export var build_cost: Dictionary = {} # resource_type (String) -> amount required from the stockpile, drawn down as builders work the site
@export var build_time: float = 10.0 # Total builder-seconds of labor needed to finish (see ConstructionSite.progress)
@export var build_energy_required: float = 1.0 # Energy cost per second of active labor spent building this structure (player or citizen)

@export_subgroup("Unlock")
@export var unlock_requirements: Dictionary = {} # resource_type (String) -> cumulative lifetime amount gathered (DataMap.lifetime_gathered, not current stockpile) needed before this is buildable. Empty = unlocked from the start.
