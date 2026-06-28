extends Resource
class_name Structure

# What role this structure plays in the simulation.
# DECORATIVE structures (trees, fountain, pavement, roads) have no capacity
# but may still contribute a small happiness bonus to nearby citizens.
enum Type { DECORATIVE, HOUSE, WORKPLACE, SHOP }

@export_subgroup("Model")
@export var model:PackedScene # Model of the structure

@export_subgroup("Gameplay")
@export var price:int # Price of the structure when building
@export var type: Type = Type.DECORATIVE # What role this structure plays
@export var capacity: int = 0 # Job slots if WORKPLACE (unused for HOUSE — see residential_floors below)
@export var happiness_bonus: float = 0.0 # Passive happiness boost for nearby citizens (decorative structures)

@export_subgroup("Housing")
@export var residential_floors: int = 0 # Floors usable as housing (HOUSE/SHOP types). Each floor = 1 household, household size rolled 2-6 at move-in.
@export var commercial_floors: int = 0 # Floors usable as shopfront (SHOP type). Not yet used by gameplay — reserved for the economy system.
