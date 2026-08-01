class_name PlayerState
extends Node
## Base gameplay state. One Node per state, the shape Snaiel's
## Godot4ThirdPersonCombatPrototype uses (PRIOR-ART.md #1).
##
## Two rules this base exists to enforce:
##
##  - `physics_update` RETURNS the next state instead of calling into the machine.
##    A state that cannot reach round and mutate the machine is a state you can
##    unit-test by calling one method and looking at the return value.
##  - Transitions are typed `@export` references to sibling state nodes, so they
##    show up in the inspector and a broken wire is a load-time error rather
##    than the silence PRIOR-ART.md #4 warns about.
##
## No `await`, no timers, nothing framerate-dependent. Gameplay windows come
## from animation method tracks (PRIOR-ART.md #3).

## Set once by the state machine. Typed, so `player.max_speed` actually resolves.
var player: Player = null


func setup(owner_player: Player) -> void:
	player = owner_player


## Called when this state becomes current. `previous` is "" on the first state.
func enter(_previous: StringName) -> void:
	pass


func exit() -> void:
	pass


## The whole per-tick behaviour of the state. Every concrete state must call
## `player.move_and_slide()` exactly once.
##
## Return the state to switch to, or `null`/`self` to stay.
func physics_update(_delta: float, _on_floor: bool) -> PlayerState:
	return null
