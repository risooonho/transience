extends KinematicBody2D

# Common entity (player, enemy) management.
# Expects the following child nodes (with the given name):
# - Hitbox (Area2D)
# - Sprite
# - AnimationPlayer
# - SamplePlayer
# - CollisionShape2D
#
# For the animation player, expects the following animations to be defined:
# - *_idle
# - *_move
# - *_attack
# - take_damage
# - die

signal health_changed
signal damaged
signal healed
signal died

export (int) var MAX_HEALTH = 100
export (int) var SPEED = 120 # Pixels/second
export (int) var ATTACK_SLIDE_SPEED = 10 # Pixels/second
export (int) var ATTACK_DAMAGE = 15
onready var health = MAX_HEALTH

# TODO: Pull this out into an SFX controller.
const SAMPLES = {
	"slice": preload("res://assets/sfx/slice.wav"),
	"throwback": preload("res://assets/sfx/throwback.wav"),
	"damaged": preload("res://assets/sfx/damaged.wav"),
}

const DIRECTIONS = ["up", "down", "left", "right"]
const DIR_TO_MOTION = {
	"left": Vector2(-1, 0),
	"up": Vector2(0, -1),
	"right": Vector2(1, 0),
	"down": Vector2(0, 1)
}

onready var cutscene = get_node("/root/cutscene")
onready var camera_controller = get_node("/root/camera_controller")

# Nodes common to all entities.
onready var sprite = get_node("Sprite")
onready var hitbox = get_node("Hitbox")
onready var animation_player = get_node("AnimationPlayer")
onready var sample_player = get_node("SamplePlayer")
onready var collision_shape = get_node("CollisionShape2D")
onready var bleed_particles = get_node("BleedParticles")
var previous_animation = null

const STATE_IDLE = "IDLE"
const STATE_MOVE = "MOVE"
const STATE_THROWBACK = "THROWBACK"
const STATE_ATTACK = "ATTACK"
const STATE_STAGGER = "STAGGER"
const STATE_DYING = "DYING"
const STATE_DEAD = "DEAD"

var current_state = STATE_IDLE
var previous_state = STATE_IDLE
var next_state = null

var next_action = null

# Valid dirs are "up", "down", "left", "right", and null, denoting idleness.
var current_dir = null
var previous_dir = null
# Keeps track of the last non-null dir. To get a non-null dir for the entity, use
# `get_dir()`, which handles default states as well.
var facing_dir = null

const MOTION_EPSILON = 0.001

func _ready():
	connect("damaged", self, "on_damaged")
	connect("damaged", self, "on_damaged_bleed")
	connect("healed", self, "on_healed")
	connect("died", self, "on_died")
	animation_player.connect("animation_finished", self, "on_animation_finished")
	
	# Copy the material, blegh.
	var material = sprite.get_material()
	if material:
		sprite.set_material(material.duplicate())

func on_animation_finished(animation):
	if next_state:
		change_state(next_state)
		next_state = null

	if previous_animation.ends_with("attack"):
		on_attack_finished()
	elif previous_animation == "die":
		on_die_finished()

	handle_next_action_if_needed()

func handle_next_action_if_needed():
	if next_action:
		handle_next_action(next_action)
		next_action = null

func set_next_action_if_unset(action):
	if not next_action:
		next_action = action

# Override in subscripts.
func handle_next_action(action):
	pass

func change_dir(dir):
	if dir != current_dir:
		previous_dir = current_dir
		current_dir = dir
		if dir != null:
			facing_dir = dir

func play_dir_animation(dir, animation):
	change_dir(dir)
	play_animation(dir + "_" + animation)

func play_animation(animation):
	previous_animation = animation
	animation_player.play(animation)

func play_sample(sample):
	var stream = SAMPLES[sample]
	sample_player.stream = stream
	sample_player.play()

func change_state(new_state):
	if new_state == current_state:
		return false
	previous_state = current_state
	current_state = new_state
	return true

func can_accept_input():
	return current_state == STATE_IDLE or current_state == STATE_MOVE

# Moves the entity in a given direction, and returns how much motion
# occurred before collision (if motion was completely successful, returns `motion`).
#   motion: A Vector2() containing x/y motion.
#   dir: One of "up", "down", "left", "right", used for animation.
#        Can also be null to designate no direction (idle)
#   delta: The delta time.
func move_entity(motion, dir, delta):
	change_dir(dir)

	if dir:
		var successful = change_state(STATE_MOVE)
		if successful or dir != previous_dir:
			# TODO: Change this to *_move.
			play_dir_animation(dir, "idle")
	else:
		var successful = change_state(STATE_IDLE)
		if successful:
			play_dir_animation(previous_dir, "idle")

	return move_and_slide(motion, Vector2(0, 0), 1)

# Returns the most recent direction that the entity is facing.
# This is guaranteed to return an actual direction, not null.
func get_dir():
	if facing_dir != null:
		return facing_dir

	# Facing dir is null; must be a newly created entity that hasn't changed dirs yet.
	var animation = animation_player.current_animation
	var separator = animation.find("_")
	if separator != -1:
		var dir = animation.left(separator)
		if dir in DIRECTIONS:
			return dir

	# Default.
	return "down"

func get_dir_from_motion(motion):
	if abs(motion.x) > MOTION_EPSILON:
		if motion.x < 0:
			return "left"
		else:
			return "right"
	if abs(motion.y) > MOTION_EPSILON:
		if motion.y < 0:
			return "up"
		else:
			return "down"
	return null

func attack():
	change_state(STATE_ATTACK)
	next_state = STATE_IDLE
	play_dir_animation(get_dir(), "attack")

func slide_in_dir(dir):
	var motion = DIR_TO_MOTION[dir]
	motion = motion.normalized() * ATTACK_SLIDE_SPEED
	move_and_slide(motion)

# Triggered by AnimationPlayer on the appropriate "attack" frame.
# Subscripts can override this to have specific collision detection for hitboxes.
func on_attack_triggered():
	pass

# Detects attack collisions and deals damage to entities in range.
# Can be called from the `on_attack_triggered` of subscripts.
# Expects the node to contain the following children:
# - *_attack_area - Area2D nodes that are used for the attack surfaces
func detect_directional_area_attack_collisions(opposing_group="enemies"):
	var dir = get_dir()
	var area = get_node(dir + "_attack_area")
	var areas = area.get_overlapping_areas()
	
	var total_damage = 0
	for area in areas:
		var body = area.get_parent()
		if body != null and body.is_in_group(opposing_group):
			# Found an opposer!
			body.take_damage(ATTACK_DAMAGE, dir)
			total_damage += ATTACK_DAMAGE
	return total_damage

func on_attack_finished():
	play_dir_animation(get_dir(), "idle")

func take_damage(damage, attacked_direction):
	if not can_take_damage_or_heal():
		return false

	health -= damage
	emit_signal("damaged", damage, attacked_direction)
	if health <= 0:
		health = 0
		emit_signal("died")
	emit_signal("health_changed", health_ratio())
	return true

func on_damaged(damage, attacked_direction):
	change_state(STATE_STAGGER)
	next_state = STATE_IDLE
	play_animation("take_damage")

func on_damaged_bleed(damage, attacked_direction):
	if current_state == STATE_DYING or current_state == STATE_DEAD:
		return
	
	bleed(attacked_direction)

# Emits particle effects simulating bleeding based on direction the entity is facing
func bleed(attack_dir):
	# TODO: Figure out how to angle the particles based on the attack direction
	bleed_particles.set_emitting(true)

func on_died():
	var successful = change_state(STATE_DYING)
	if successful:
		# Disable the collisions.
		collision_shape.disabled = true
		play_animation("die")

func on_die_finished(free=true):
	change_state(STATE_DEAD)
	if free:
		queue_free()

func heal(amount):
	if not can_take_damage_or_heal():
		return false
	var previous_health = health
	health = min(health + amount, MAX_HEALTH)
	
	var successful = health != previous_health
	if successful:
		emit_signal("health_changed", health_ratio())
		emit_signal("healed", amount)
	return successful

func on_healed(amount):
	# TODO: Play some animation?
	pass

func can_take_damage_or_heal():
	return current_state in [STATE_IDLE, STATE_MOVE, STATE_ATTACK, STATE_STAGGER]

func health_ratio():
	return float(health) / MAX_HEALTH
