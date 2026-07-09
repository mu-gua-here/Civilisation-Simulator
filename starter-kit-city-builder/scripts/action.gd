extends Resource
class_name Action

## An Action describes "do this thing", dispatched by PolicyEngine.execute().
## `target_query` is how PolicyEngine finds *what to act on* (a building, a
## gatherable node, a construction site) when the action needs a target beyond
## the subject itself -- e.g. ASSIGN_JOB needs to find a workplace.
##
## For manual (UI-driven) actions, the target is already known (the player
## clicked it), so the UI constructs the Action with target_query left unused
## and instead pre-resolves the target itself before calling execute(). See
## PolicyEngine.execute() for how the two paths reconcile.

enum Kind { ASSIGN_JOB, ASSIGN_HOUSING, ASSIGN_GATHER, ASSIGN_BUILD_TASK }

@export var kind: Kind
@export var target_query: Condition  # how to find the building/node to assign *to* (policy path)


static func new_assign_job() -> Action:
	var a := Action.new()
	a.kind = Kind.ASSIGN_JOB
	return a

static func new_assign_housing() -> Action:
	var a := Action.new()
	a.kind = Kind.ASSIGN_HOUSING
	return a

static func new_assign_gather() -> Action:
	var a := Action.new()
	a.kind = Kind.ASSIGN_GATHER
	return a

static func new_assign_build_task() -> Action:
	var a := Action.new()
	a.kind = Kind.ASSIGN_BUILD_TASK
	return a
