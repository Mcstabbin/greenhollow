class_name PlayerMoveState
extends PlayerLocomotionState
## Running on the ground.

@export var idle_state: PlayerState
@export var air_state: PlayerState


func next_state(on_floor: bool) -> PlayerState:
	if not on_floor:
		return air_state
	if block_requested():
		return block_state
	if attack_requested():
		return attack_target()
	if player.get_horizontal_speed() <= player.walk_anim_threshold:
		return idle_state
	return null
