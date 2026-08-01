class_name PlayerIdleState
extends PlayerLocomotionState
## Standing still on the ground.

@export var move_state: PlayerState
@export var air_state: PlayerState


func next_state(on_floor: bool) -> PlayerState:
	if not on_floor:
		return air_state
	if attack_requested():
		return attack_state
	# Threshold, not "is there input": matches the pre-refactor animation
	# selector, so the idle -> walk moment lands on the same frame it always did.
	if player.get_horizontal_speed() > player.walk_anim_threshold:
		return move_state
	return null
