class_name PlayerAttackState
extends PlayerState
## Committed melee attacks: the equipped weapon's chain, and its charged attack.
##
## The chain is DATA. `MeleeWeapon.steps` is an `Array[AttackStep]` and this state walks
## it, so the sword's two alternating slashes and the axe's slower, harder two are the
## same code path with different numbers — which is the engine's own demo pattern, see
## PRIOR-ART.md. A weapon with three steps, or one, or a different clip per step, needs
## no edit here.
##
## This state deliberately knows almost nothing about timing. Wind-up, the live
## hitbox window, the cancel/combo window and the end of the swing are all Call
## Method Tracks on the clips themselves (see tools/build_combat_anims.gd), which
## is Snaiel's pattern from PRIOR-ART.md. The state only reads the flags those
## keyframes set. Retiming an attack means editing the generator, not this file,
## and the animation can never drift out of sync with the window because they are
## the same resource.
##
## Commitment is the whole point: no steering, no jump, no state change until the
## animation says so. The escape hatch is the cancel window, which the clips open
## in the last ~35% of recovery.

@export var idle_state: PlayerState
@export var move_state: PlayerState
@export var air_state: PlayerState

var _step: AttackStep = null
var _combo: int = 0
var _elapsed: float = 0.0
var _timeout: float = 1.0
## Latched follow-up. The Player's input buffer is deliberately short (180 ms, so
## a stale press never fires a swing you have forgotten about) but the cancel
## window does not open for ~400 ms. Rather than stretch the buffer — which would
## make every attack feel like it has a mind of its own — a press made while
## already committed is latched here for the rest of the swing. That is what makes
## mashing chain instead of being eaten.
var _queued := false
var _queued_spin := false


func enter(_previous: StringName) -> void:
	_combo = 0
	_queued = false
	_queued_spin = false
	player.snap_facing_to_input()
	_start_swing(player.take_attack_request())


func exit() -> void:
	_queued = false
	_queued_spin = false
	player.end_attack()


func physics_update(delta: float, on_floor: bool) -> PlayerState:
	_elapsed += delta

	if player.has_attack_request():
		_queued = true
		if player.take_attack_request():
			_queued_spin = true

	# Chain. The clip opened the window; a latched press uses it instead of
	# waiting out the recovery. The absence of this is exactly what REFERENCE.md
	# means by combat that "feels like glue".
	var done := false
	if player.attack_can_cancel and _queued:
		_start_swing(_queued_spin)
	elif player.attack_finished or _elapsed > _timeout:
		# _timeout is a guard, not the mechanism: if a blend ever swallowed the
		# final method key we recover instead of locking the player out.
		if not player.attack_finished:
			push_warning("attack '%s' timed out without _anim_attack_finished"
				% (_step.clip if _step != null else &"?"))
		done = true

	# The move happens whether or not we are leaving: PlayerState's contract is one
	# move_and_slide per state per tick, and returning early would drop a frame of
	# integration on every single swing.
	player.apply_gravity(delta, on_floor)
	player.tick_landing(on_floor)
	player.apply_attack_drive(delta, on_floor)
	player.move_and_slide()

	return _resolve_exit(on_floor) if done else null


## Pick the next step out of the equipped weapon and swing it. `charged` means the player
## released a held charge, so the weapon's charged step jumps the queue and the chain
## restarts behind it.
func _start_swing(charged: bool) -> void:
	_queued = false
	_queued_spin = false
	var weapon := player.loadout.equipped as MeleeWeapon
	if weapon == null or weapon.steps.is_empty():
		# Nothing swingable in hand. Reachable only if an item is swapped mid-swing, and
		# the honest answer is to end the state rather than to invent a swing.
		_step = null
		player.attack_finished = true
		return
	if charged and weapon.charged != null:
		_step = weapon.charged
		_combo = 0
	else:
		_step = weapon.steps[_combo % weapon.steps.size()]
		_combo += 1
	_elapsed = 0.0
	# The clip's own length divided by the rate this step plays it at, which Player worked
	# out in begin_attack. A guard, not the mechanism — but a guard sized for a sword would
	# fire in the middle of every heavy swing.
	# begin_attack must run before the clip does, so the previous swing's flags
	# cannot survive into this one and end it on frame two.
	player.begin_attack(_step, charged)
	_timeout = player.attack_clip_duration + 0.25


func _resolve_exit(on_floor: bool) -> PlayerState:
	if not on_floor:
		return air_state
	if player.get_horizontal_speed() > player.walk_anim_threshold:
		return move_state
	return idle_state
