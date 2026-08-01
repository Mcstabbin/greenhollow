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
## release, opens the Attack state.
func attack_requested() -> bool:
	return attack_state != null and player.has_attack_request()


func next_state(_on_floor: bool) -> PlayerState:
	return null
