class_name PlayerLocomotionState
extends PlayerState
## Shared parent of Idle / Move / Air — the hierarchy in the hierarchical state
## machine. All three want identical gravity, jump, camera-relative acceleration
## and turn-to-face; only their exit conditions differ.
##
## The body of `physics_update` below is the old flat `_physics_process`, in the
## SAME ORDER, calling the same Player methods. That is not laziness: the probe
## baselines (accel 100 ms, decel 133.3 ms, tapped apex 0.492 m, held apex
## 1.648 m) are sensitive to this ordering, and a refactor that "tidies" it moves
## the numbers. Reordering here is a behaviour change, not a style change.

## Where an attack press sends us. Left unset on states that cannot attack.
@export var attack_state: PlayerState
## Where a bow's draw and a shield's guard send us. Left unset on Air for the same reason
## `attack_state` is: committing to either while falling is worse than not being able to.
@export var aim_state: PlayerState
@export var block_state: PlayerState


## Runs the shared locomotion tick, then asks the subclass where to go next.
func physics_update(delta: float, on_floor: bool) -> PlayerState:
	player.apply_gravity(delta, on_floor)
	player.try_buffered_jump()
	player.tick_landing(on_floor)
	player.apply_jump_cut()
	player.apply_movement(delta, on_floor)
	player.move_and_slide()
	player.face_movement_direction(delta)
	# Locomotion animation is chosen by speed, exactly as before the refactor,
	# so idle/walk/jump selection and the speed-scaled walk cycle are untouched.
	player.update_locomotion_anim(on_floor)
	return next_state(on_floor)


## Grounded states share one attack check: a buffered press, or a charged
## release, opens whichever state the held item calls for.
func attack_requested() -> bool:
	return attack_target() != null and player.has_attack_request()


## Which state an attack press opens, decided by WHAT IS IN YOUR HAND. The question is
## asked of the item — `is_ranged()`, `is_melee()` — rather than of its id, so a fifth
## weapon is a `.tres` file and not an edit here. Null means the press does nothing,
## which is the correct and knowingly-accepted answer while holding the shield.
func attack_target() -> PlayerState:
	var item := player.loadout.equipped
	if item == null:
		return null
	if item.is_ranged():
		return aim_state
	if item.is_melee():
		return attack_state
	return null


## The guard. A held button rather than a buffered press, because a shield goes up for as
## long as you hold it and there is nothing to be forgiving about.
func block_requested() -> bool:
	var item := player.loadout.equipped
	return (block_state != null and item != null and item.is_shield()
		and Input.is_action_pressed("shield"))


func next_state(_on_floor: bool) -> PlayerState:
	return null
