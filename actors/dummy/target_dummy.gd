class_name TargetDummy
extends StaticBody3D
## A straw practice dummy: the first thing in this world that can be locked onto and
## hit. Not an enemy — it has no AI, no attack and no aggro — but deliberately the
## same SHAPE as one, so whoever brings enemies has a pattern rather than a blank
## page: a body on the enemy layer, a `Health`, a `HurtBox3D` on the enemy hurtbox
## layer, and a `LockOnTarget` anchored at chest height with its health wired in.
##
## Every one of those four is a vendored or existing component. The only thing this
## script adds is what happens when you hit it, and that is the part an enemy will
## replace: the dummy flinches, falls over when its health runs out, and stands back
## up after a few seconds so it is a permanent practice target rather than a
## one-shot prop.
##
## Layer 4 ("enemy_body"), NOT layer 1. Two consequences and both are wanted:
## `LockOnSystem`'s sight-line ray masks layer 1, so a dummy can never occlude its
## own chest and never hides another target behind it either; and the player's
## SpringArm masks layer 1, so standing next to one does not shove the camera into
## the player's head. The player's own mask includes layer 4, so you still bump into
## it.

## Health it stands back up with, and the shape of the read: five sword hits, two
## axe chains. Small enough that the death path is reachable in a probe run.
@export var max_health: int = 5
## Seconds spent lying over before it rights itself. Long enough to register that
## something happened, short enough that a practice target stays available.
@export var reset_seconds: float = 4.0
## Degrees the body tips on a hit, and how long the tip takes there and back. The
## flinch has to be a SHAPE change: a tint on a straw sack is invisible at 640 px.
@export var flinch_degrees: float = 15.0
@export var flinch_time: float = 0.16
## Degrees it lies over at when its health runs out.
@export var topple_degrees: float = 74.0
## Drop the dummy onto whatever ground is under it on load, rather than trusting a
## hand-authored Y. The level is a hand-edited mesh with a river trench and a raised
## village in it, so an authored height is a guess and a raycast is a measurement.
@export var snap_to_ground: bool = true

@onready var health: Health = $Health
@onready var lock_target: LockOnTarget = $LockOnTarget
## Everything that visibly tips. A child node rather than the root, because the root
## carries the collision shape and the hurtbox and neither should rotate with a
## flinch — a hitbox that swings away from the blade would make the second hit of a
## chain miss for reasons no player could see.
@onready var visuals: Node3D = $Visuals

var _reset_timer := 0.0
var _down := false
var _tween: Tween = null


func _ready() -> void:
	collision_layer = 8   # layer 4, enemy_body
	collision_mask = 0
	health.max = max_health
	health.current = max_health
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	if snap_to_ground:
		_drop_to_ground()


func _physics_process(delta: float) -> void:
	if not _down:
		return
	_reset_timer -= delta
	if _reset_timer <= 0.0:
		_stand_up()


## Where the lock-on reticle sits, for anything that wants to know without reaching
## through the child node.
func chest_height() -> float:
	return lock_target.aim_point().y - global_position.y


func _drop_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 6.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 24.0)
	query.collision_mask = 1
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		push_warning("%s: no ground under %s, leaving it where it was" % [name, global_position])
		return
	global_position.y = (hit["position"] as Vector3).y


func _on_damaged(_entity: Node, _type: int, _amount: int, _inc: int, _mult: float,
		applied: int) -> void:
	if applied <= 0 or _down:
		return
	Audio.play("break", -14.0, 0.18)
	_tip(deg_to_rad(flinch_degrees), flinch_time, true)


func _on_died(_entity: Node) -> void:
	_down = true
	_reset_timer = reset_seconds
	Audio.play("break", -6.0, 0.1)
	_tip(deg_to_rad(topple_degrees), 0.28, false)


func _stand_up() -> void:
	_down = false
	# `fill` rather than assigning `current`: it goes through the addon's own path, so
	# the `revived` signal fires and anything listening hears about it.
	health.fill()
	lock_target.targetable = true
	_tip(0.0, 0.3, false)


## Tip the visuals about their own X axis. `back` returns to upright afterwards,
## which is the difference between a flinch and falling over.
func _tip(radians: float, seconds: float, back: bool) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(visuals, "rotation:x", radians, seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if back:
		_tween.tween_property(visuals, "rotation:x", 0.0, seconds * 1.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
