extends Node3D

var player: CharacterBody3D = null

# Player global stuff
var player_health: float = 100.0
var player_hunger: float = 0.0
var player_energy: float = 100.0

func register_player(p: CharacterBody3D) -> void:
	player = p

func get_player_position() -> Vector3:
	if player:
		return player.global_position
	return Vector3.ZERO

func set_player_health(v: float) -> void:
	player_health = clamp(v, 0.0, 100.0)

func set_player_hunger(v: float) -> void:
	player_hunger = clamp(v, 0.0, 100.0)
