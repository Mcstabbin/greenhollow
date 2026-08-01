class_name PlayerAirState
extends PlayerLocomotionState
## Rising or falling. Covers the whole airborne arc, including coyote time — the
## timers live on the Player so leaving the ground never resets them.
##
## `attack_state` is intentionally left unwired on this node: there is no jump
## attack in wave A, and an attack that commits you for 450 ms while falling is
## worse than no air attack at all.

@export var idle_state: PlayerState
@export var move_state: PlayerState


func next_state(on_floor: bool) -> PlayerState:
	if not on_floor:
		return null
	if player.get_horizontal_speed() > player.walk_anim_threshold:
		return move_state
	return idle_state
