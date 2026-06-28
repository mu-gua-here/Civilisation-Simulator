class_name CitizenData
extends Node

@export var id: String = ""
@export var citizen_name: String = NameGenerator.generate_name()
@export var age: int = randi_range(2, 100)
@export var health: float = 100.0
@export var hunger: float = 100.0
@export var metabolism: float = (100 - age - randf_range(0.1, 1.0)) * 0.01
@export var job: String = ""
@export var job_satisfaction: float = 50.0
@export var happiness: float = 50.0
@export var housing_satisfaction: float = 0.0
@export var approval: float = 50.0
