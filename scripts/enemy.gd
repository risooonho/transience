extends "res://scripts/entity.gd"

# Base script for all enemy types.

# The distance that the char has to be from the enemy in order to trigger battle.
export (int) var TRIGGER_DISTANCE = 100
var TRIGGER_DISTANCE_SQUARED

func _ready():
	# Cache the square since sqrt() operations are slow.
	TRIGGER_DISTANCE_SQUARED = TRIGGER_DISTANCE * TRIGGER_DISTANCE
	add_to_group("enemies")

# Initiates a battle with an enemy.
# TODO: Handle AI here.
func start_battle():
	pass