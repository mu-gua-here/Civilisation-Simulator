extends Resource
class_name Condition

## A Condition is either:
##  - a LEAF: "subject.field OP value" (e.g. citizen.age >= 16)
##  - an AND/OR/NOT combinator over child Conditions
##
## `field` is deliberately a String, not an enum -- see PolicyEngine's field
## lookup table. New fields should be added there, not here.

enum Kind { LEAF, AND, OR, NOT }

@export var kind: Kind = Kind.LEAF

# --- LEAF fields ---
@export var field: String = ""        # e.g. "age", "energy", "job", "type"
@export var op: String = "=="          # "==", "!=", "<", ">", "<=", ">="
@export var value = null               # typed in by the player (Variant)

# --- AND/OR/NOT fields ---
@export var children: Array[Condition] = []


# --- Convenience constructors (used by manual UI hook-up and tests) ---

static func leaf(p_field: String, p_op: String, p_value) -> Condition:
	var c := Condition.new()
	c.kind = Kind.LEAF
	c.field = p_field
	c.op = p_op
	c.value = p_value
	return c

static func op_and(p_children: Array[Condition]) -> Condition:
	var c := Condition.new()
	c.kind = Kind.AND
	c.children = p_children
	return c

static func op_or(p_children: Array[Condition]) -> Condition:
	var c := Condition.new()
	c.kind = Kind.OR
	c.children = p_children
	return c

static func op_not(p_child: Condition) -> Condition:
	var c := Condition.new()
	c.kind = Kind.NOT
	c.children = [p_child]
	return c

## A Condition that matches every subject. Useful as a default / "any" target_query.
static func always_true() -> Condition:
	return Condition.op_and([])
