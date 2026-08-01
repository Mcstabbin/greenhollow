class_name PlayerStateMachine
extends Node
## Drives one PlayerState child per tick. Deliberately tiny — about the size of
## Snaiel's, which is the point: a 60-line machine needs no GDExtension and no
## editor plugin, and every line of it is readable at review time.
##
## The machine does NOT own a `_physics_process`. Player calls into it, so the
## order of camera / timers / state / footsteps stays visible in one function
## instead of being spread across node process order.

signal state_changed(from: StringName, to: StringName)

## The state entered on load.
@export var initial_state: PlayerState

var current: PlayerState = null

var _player: Player = null


func setup(owner_player: Player) -> void:
	_player = owner_player
	for child in get_children():
		var state := child as PlayerState
		if state == null:
			push_warning("%s: child %s is not a PlayerState" % [name, child.name])
			continue
		state.setup(owner_player)

	current = initial_state if initial_state != null else get_child(0) as PlayerState
	if current == null:
		push_error("%s: no initial state" % name)
		return
	current.enter(&"")


func physics_update(delta: float, on_floor: bool) -> void:
	if current == null:
		return
	var next := current.physics_update(delta, on_floor)
	if next != null and next != current:
		_transition_to(next)


## Force a state change from outside. Used by nothing in wave A; it exists so a
## later feature (a hit reaction, a cutscene) has a sanctioned entry point rather
## than reaching into `current`.
func force(next: PlayerState) -> void:
	if next != null and next != current:
		_transition_to(next)


func get_state_name() -> StringName:
	return current.name if current != null else &"-"


func _transition_to(next: PlayerState) -> void:
	var from: StringName = current.name
	current.exit()
	current = next
	current.enter(from)
	state_changed.emit(from, next.name)
