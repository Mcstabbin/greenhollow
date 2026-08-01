class_name PlayerBlockState
extends PlayerState
## Shield up.
##
## With one equip slot, holding the shield means holding ONLY the shield: there is no
## attack from here. That is the accepted consequence of the design, not a gap — see
## items/shield_item.gd.
##
## Why a state rather than a flag on the Player: a guard changes movement, facing,
## animation and how incoming damage is resolved, and all four have to agree. A flag
## would have put four `if _blocking` branches into the locomotion path, which is exactly
## the shape PRIOR-ART.md flags as the thing that makes a component stop being one.
##
## The numbers are all the shield's (`ShieldItem`), so a second shield is a `.tres`.

@export var idle_state: PlayerState
@export var move_state: PlayerState
@export var air_state: PlayerState
## How fast the character turns to face the camera while guarding. Faster than the free
## turn: a guard that lags behind the stick is a guard you cannot aim.
@export var turn_speed: float = 16.0

## Seconds since the shield came up. Read by `is_deflect`.
var _held := 0.0
var _up := false


func enter(_previous: StringName) -> void:
	_held = 0.0
	_up = true
	# Face where the camera looks, immediately. A guard is a directional commitment, and
	# on the frame it goes up it should already be pointing where the player is looking.
	player.rig.rotation.y = player.camera_pivot.rotation.y + PI
	player.play_anim(&"block", 1.0)


func exit() -> void:
	_up = false


func physics_update(delta: float, on_floor: bool) -> PlayerState:
	_held += delta

	# Strafe. Facing follows the camera rather than the direction of travel, which is what
	# makes a guarded step sideways read as backing off rather than as turning away.
	player.rig.rotation.y = lerp_angle(
		player.rig.rotation.y, player.camera_pivot.rotation.y + PI, turn_speed * delta)

	var shield := player.loadout.equipped as ShieldItem
	var scale := shield.move_scale if shield != null else 1.0

	player.apply_gravity(delta, on_floor)
	player.tick_landing(on_floor)
	player.apply_movement(delta, on_floor, scale)
	player.move_and_slide()

	if not on_floor:
		return air_state
	# Dropping the guard, or losing the shield mid-guard.
	if not Input.is_action_pressed("shield") or shield == null:
		return move_state if player.get_horizontal_speed() > player.walk_anim_threshold \
			else idle_state
	return null


## How much of an incoming hit gets through, given where it came from.
##
## Expressed as a multiplier because that is what the vendored addon speaks — a
## `HealthModifier` is a multiplier per damage type — so wiring this into a player
## hurtbox later is an assignment rather than an adapter.
##
## Nothing calls this yet, and that is a stated boundary rather than an omission: the
## player has no `Health` and no `HurtBox3D`, both of which belong to whoever brings
## enemies. tools/probe.gd's `weapons` suite drives it directly against a real `Health`
## component, so the arithmetic is measured rather than asserted by eye.
func damage_multiplier_from(source_position: Vector3) -> float:
	var shield := player.loadout.equipped as ShieldItem
	if not _up or shield == null:
		return 1.0

	var to := source_position - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.000001:
		return 0.0 if is_deflect() else shield.damage_multiplier

	# The rig's forward is +basis.z at yaw 0, the same convention every other facing
	# calculation here uses.
	var facing := player.rig.global_basis.z
	facing.y = 0.0
	var offset := rad_to_deg(facing.normalized().angle_to(to.normalized()))
	if offset > shield.block_arc_deg * 0.5:
		# Outside the arc. A shield that works from behind is not a shield.
		return 1.0
	return 0.0 if is_deflect() else shield.damage_multiplier


## True while a hit would be DEFLECTED rather than blocked: raised into the blow instead
## of already standing behind it. Takes no damage at all.
##
## The other half of a deflect — staggering the attacker — needs an attacker, so it is
## deliberately not invented here. The cooldown that stops mashing being a strategy has
## nothing to reset yet either, and lives on the item until it does.
func is_deflect() -> bool:
	var shield := player.loadout.equipped as ShieldItem
	if shield == null:
		return false
	return _up and _held * 1000.0 <= float(shield.ms_deflect_window)
