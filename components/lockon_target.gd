class_name LockOnTarget
extends Area3D
## Marks a point on an actor that the player's lock-on can grab.
##
## A point, not a volume: the shape is a 0.1 m sphere that tracks `anchor` every
## frame. Selection is scored in screen space by the lock-on system, so the only
## thing this has to answer is "where on this creature should the camera aim" —
## a big collision volume would make that ambiguous and drag the reticle around
## as the creature animated.
##
## Aim at the chest, not the origin. An origin-anchored reticle on a tall enemy
## sits at its feet, which reads as targeting the ground.
##
## Targets live on collision layer 9; the lock-on system's detection sphere both
## masks and sits on that layer.
##
## Design inherited from Snaiel's Godot4ThirdPersonCombatPrototype (MIT) — see
## .claude/skills/gauntlet/PRIOR-ART.md.

## Emitted when this target stops being valid — killed, freed, or disabled. The
## lock-on system uses this to release the lock and look for the next one.
signal lost(target: LockOnTarget)

const LAYER := 1 << 8  ## Collision layer 9, "lockon_target".
const RADIUS := 0.1

## The creature this target belongs to, which is what gameplay code wants back
## from a lock. Defaults to `owner` so the common case needs no wiring.
@export var actor: Node3D:
	get():
		return actor if actor != null else (owner as Node3D)

## What the reticle and camera aim at. Point this at a chest bone or a marker
## partway up the creature. Falls back to the target's own position.
@export var anchor: Node3D

## Health to watch, if the creature has one. When it hits zero the target drops
## out of contention on its own, so nothing else has to remember to unregister
## it. Optional: scenery and puzzle objects are lockable without being killable.
@export var health: Health

## Clear to make a creature temporarily untargetable — mid-spawn, phasing,
## already dying — without freeing the node.
@export var targetable: bool = true:
	set(value):
		targetable = value
		if not targetable:
			lost.emit(self)


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true

	# Built in code rather than authored per-enemy: every target wants the same
	# 0.1 m sphere, and one that quietly differs would skew screen-space scoring.
	if get_child_count() == 0:
		var shape := SphereShape3D.new()
		shape.radius = RADIUS
		var owner_shape := CollisionShape3D.new()
		owner_shape.shape = shape
		add_child(owner_shape)

	if health != null:
		health.died.connect(_on_died)

	tree_exiting.connect(_on_tree_exiting)


func _process(_delta: float) -> void:
	if anchor != null:
		global_position = anchor.global_position


## Where the camera and reticle should aim.
func aim_point() -> Vector3:
	return anchor.global_position if anchor != null else global_position


func is_valid() -> bool:
	if not targetable or not is_inside_tree():
		return false
	if health != null and health.is_dead():
		return false
	return true


func _on_died(_entity: Node) -> void:
	targetable = false


func _on_tree_exiting() -> void:
	lost.emit(self)
