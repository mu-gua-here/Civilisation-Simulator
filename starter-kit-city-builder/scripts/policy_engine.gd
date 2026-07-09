extends Node

## PolicyEngine -- where players design their own policies to "automate" repetitive actions on citizens
##
##   "given a Condition and an Action, find all Subjects (citizens, buildings,
##    resource nodes) matching the Condition, and perform the Action on them."
##
## A manual player action is this engine invoked once, with the Subject
## already chosen by the click. A policy (Milestone B) is this engine invoked
## on a timer, searching all Subjects for matches. Both paths call evaluate()/
## execute() -- nothing about "what an action does" should ever be written
## twice (once for the click handler, once for the policy runner).
##
## Registered as an autoload singleton so both the manual UI and the future
## PolicyManager can reach it without a node reference.

# --- Field lookup table -----------------------------------------------
#
# Maps a string field name (as typed/selected by the player) to a Callable
# that extracts that field's value from a subject. Kept as a small table
# rather than an enum so new fields (new citizen stats, new building stats)
# can be added in one place without touching Condition itself.
#
# Each getter must be defensive: return null for a subject it doesn't apply
# to (e.g. asking a BuildingInstance for "age"), and evaluate() treats a null
# getter result as "condition fails safely" rather than crashing.

const _CITIZEN_FIELDS := {
	"age": "_get_citizen_age",
	"energy": "_get_citizen_energy",
	"happiness": "_get_citizen_happiness",
	"health": "_get_citizen_health",
	"job": "_get_citizen_job",
	"job_satisfaction": "_get_citizen_job_satisfaction",
	"housing_satisfaction": "_get_citizen_housing_satisfaction",
	"approval": "_get_citizen_approval",
}

const _BUILDING_FIELDS := {
	"type": "_get_building_type",
	"capacity": "_get_building_capacity",
	"worker_count": "_get_building_worker_count",
	"resident_count": "_get_building_resident_count",
	"residential_floors": "_get_building_residential_floors",
}


# --- evaluate / find_matches -------------------------------------------

## Recursively resolves a Condition tree against a single subject.
## Returns false (never crashes) if the field/subject combination is unknown.
func evaluate(condition: Condition, subject) -> bool:
	if condition == null:
		return true # no condition == match everything, used by always_true()

	match condition.kind:
		Condition.Kind.AND:
			for child in condition.children:
				if not evaluate(child, subject):
					return false
			return true

		Condition.Kind.OR:
			if condition.children.is_empty():
				return false
			for child in condition.children:
				if evaluate(child, subject):
					return true
			return false

		Condition.Kind.NOT:
			if condition.children.is_empty():
				return false
			return not evaluate(condition.children[0], subject)

		Condition.Kind.LEAF:
			return _evaluate_leaf(condition, subject)

	return false

func _evaluate_leaf(condition: Condition, subject) -> bool:
	var actual = _get_field(subject, condition.field)
	if actual == null:
		return false # unknown field for this subject type -- fail safely

	return _compare(actual, condition.op, condition.value)

func _compare(actual, op: String, expected) -> bool:
	match op:
		"==":
			return actual == expected
		"!=":
			return actual != expected
		"<":
			return actual < expected
		">":
			return actual > expected
		"<=":
			return actual <= expected
		">=":
			return actual >= expected
	push_warning("PolicyEngine: unknown operator '%s'" % op)
	return false

## Filters a pool of subjects (citizens, BuildingInstances, etc.) down to the
## ones matching condition. `pool` can be any Array -- callers decide what
## population to search (e.g. builder.citizens, builder.buildings.values()).
func find_matches(condition: Condition, pool: Array) -> Array:
	var matches: Array = []
	for subject in pool:
		if evaluate(condition, subject):
			matches.append(subject)
	return matches


# --- field getters -------------------------------------------------------
#
# Subjects in this game are either citizen nodes (CharacterBody3D with a
# `.data: CitizenData`) or BuildingInstance resources. Dispatch on subject
# shape rather than a Subject base class, since citizen.gd and
# BuildingInstance are unrelated types we don't want to touch the
# inheritance of.

func _get_field(subject, field: String):
	if subject == null:
		return null

	if _is_citizen(subject):
		if _CITIZEN_FIELDS.has(field):
			return call(_CITIZEN_FIELDS[field], subject)
		return null

	if subject is BuildingInstance:
		if _BUILDING_FIELDS.has(field):
			return call(_BUILDING_FIELDS[field], subject)
		return null

	return null

func _is_citizen(subject) -> bool:
	return subject is Node and subject.is_in_group("citizen")

func _get_citizen_age(citizen): return citizen.data.age
func _get_citizen_energy(citizen): return citizen.data.energy
func _get_citizen_happiness(citizen): return citizen.data.happiness
func _get_citizen_health(citizen): return citizen.data.health
func _get_citizen_job(citizen): return citizen.data.job
func _get_citizen_job_satisfaction(citizen): return citizen.data.job_satisfaction
func _get_citizen_housing_satisfaction(citizen): return citizen.data.housing_satisfaction
func _get_citizen_approval(citizen): return citizen.data.approval

# BuildingInstance doesn't carry a back-reference to its Structure, so these
# getters need the owning Builder to resolve structure_index -> Structure.
# We resolve it lazily via the "builder" group (Builder already calls
# add_to_group("builder") in _ready) rather than threading a builder
# reference through every BuildingInstance. Cached after first lookup since
# there's exactly one Builder for the lifetime of a game session.
var _builder_cache: Node = null

func _builder():
	if _builder_cache != null and is_instance_valid(_builder_cache):
		return _builder_cache
	var tree = get_tree()
	if tree == null:
		return null
	_builder_cache = tree.get_first_node_in_group("builder")
	return _builder_cache

func _get_building_type(instance: BuildingInstance):
	var b = _builder()
	if b == null or instance.structure_index < 0 or instance.structure_index >= b.structures.size():
		return null
	return b.structures[instance.structure_index].type

func _get_building_capacity(instance: BuildingInstance):
	var b = _builder()
	if b == null or instance.structure_index < 0 or instance.structure_index >= b.structures.size():
		return null
	return b.structures[instance.structure_index].capacity

func _get_building_worker_count(instance: BuildingInstance):
	return instance.workers.size()

func _get_building_resident_count(instance: BuildingInstance):
	return instance.residents.size()

func _get_building_residential_floors(instance: BuildingInstance):
	var b = _builder()
	if b == null or instance.structure_index < 0 or instance.structure_index >= b.structures.size():
		return null
	return b.structures[instance.structure_index].residential_floors


# --- execute --------------------------------------------------------------

## Dispatches an Action against a subject. This routes through the EXISTING
## builder methods (has_housing_for, request_job, etc.) per the plan -- this
## milestone does not rewrite those, it's the single place both manual clicks
## and (later) policies funnel through.
##
## `resolved_target` is optional: when the UI already knows the target
## (e.g. the player clicked a specific building), pass it here and execute()
## uses it directly instead of searching via action.target_query. Policies
## (Milestone B) leave this null and let execute() search.
func execute(action: Action, subject, resolved_target = null) -> bool:
	if action == null or subject == null:
		return false

	var b = _builder()
	if b == null:
		push_warning("PolicyEngine.execute: no Builder found in scene tree")
		return false

	match action.kind:
		Action.Kind.ASSIGN_JOB:
			return _execute_assign_job(b, subject, resolved_target)

		Action.Kind.ASSIGN_HOUSING:
			return _execute_assign_housing(b, subject, resolved_target)

		Action.Kind.ASSIGN_GATHER:
			return _execute_assign_gather(b, subject, resolved_target)

		Action.Kind.ASSIGN_BUILD_TASK:
			return _execute_assign_build_task(b, subject, resolved_target)

	push_warning("PolicyEngine.execute: unhandled Action.Kind %s" % action.kind)
	return false

## resolved_target, when given, is a specific BuildingInstance the caller
## already picked (the manual click path -- A.3). With no resolved_target,
## falls back to the builder's existing "first available slot" search
## (request_job), which is what a Milestone B policy with no specific
## target_query will use.
func _execute_assign_job(b, citizen, resolved_target = null) -> bool:
	if not _is_citizen(citizen):
		return false
	
	if resolved_target is BuildingInstance:
		var structure: Structure = b.structures[resolved_target.structure_index]
		if structure.type != Structure.Type.WORKPLACE:
			return false
		if resolved_target.workers.size() >= structure.capacity:
			return false # no free slot at this specific building
		if citizen.data.id in resolved_target.workers:
			return true # already assigned here
		resolved_target.workers.append(citizen.data.id)
		citizen.data.job = structure.model.resource_path.get_file().get_basename()
		return true
	
	var job_name: String = b.request_job(citizen)
	if job_name != "":
		citizen.data.job = job_name
		return true
	return false

## See _execute_assign_job for the resolved_target / search-fallback split.
func _execute_assign_housing(b, citizen, resolved_target = null) -> bool:
	if not _is_citizen(citizen):
		return false
	
	if resolved_target is BuildingInstance:
		var structure: Structure = b.structures[resolved_target.structure_index]
		if structure.residential_floors <= 0:
			return false
		if resolved_target.residents.size() >= structure.residential_floors:
			return false # no free slot at this specific building
		if citizen.data.id in resolved_target.residents:
			return true # already housed here
		resolved_target.residents.append(citizen.data.id)
		return true
	
	return b.has_housing_for(citizen)

func _execute_assign_gather(b, citizen, resolved_target) -> bool:
	if not _is_citizen(citizen):
		return false
	# Manual path: resolved_target is the specific Vector3i cell the player
	# clicked. Pass it directly to the citizen so they walk to that exact tree,
	# not whatever happens to be nearest. Policy path (no resolved_target) falls
	# back to the citizen finding the nearest gatherable themselves.
	if resolved_target is Vector3i:
		if citizen.has_method("_start_gathering_at"):
			citizen._start_gathering_at(resolved_target)
			return true
		return false
	if citizen.has_method("_start_gathering"):
		citizen._start_gathering()
		return true
	return false

## resolved_target, when given, is a specific Vector3i cell the caller
## already picked (manual click on a construction site -- A.3). With no
## resolved_target, searches via b.get_nearest_construction_site() from the
## citizen's current position, which is what a Milestone B policy with no
## specific target_query will use.
func _execute_assign_build_task(b, citizen, resolved_target = null) -> bool:
	if not _is_citizen(citizen):
		return false
	
	var cell: Vector3i
	if resolved_target is Vector3i:
		cell = resolved_target
	else:
		cell = b.get_nearest_construction_site(citizen.global_position)
		if cell == b.NO_GATHERABLE_CELL:
			return false # nothing under construction right now
	
	if not b.assign_builder_to_site(citizen.data.id, cell):
		return false
	
	if citizen.has_method("_start_building"):
		citizen._start_building(cell)
	return true
