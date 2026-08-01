class_name ShieldItem
extends ItemData
## An off-hand defensive item, used with the `shield` action.
##
## Note the consequence of a single equip slot: holding this means holding ONLY
## this, so there is no attack while shielded. That is the chosen behaviour, not an
## oversight — `hand` is already modelled so a second slot is additive.

## Incoming damage is only reduced within this arc of the facing direction, in
## degrees total. A shield that works from behind is not a shield.
@export var block_arc_deg: float = 140.0

## Multiplier applied to damage that lands inside the arc. Expressed as a
## multiplier rather than a subtraction so it composes with the vendored addon's
## HealthModifier, which already speaks in multipliers per damage type.
@export_range(0.0, 1.0) var damage_multiplier: float = 0.25

## A hit landing inside this window after raising the shield is a deflect rather
## than a block — the attacker is staggered instead. Shipped games cluster tight:
## Dark Souls 3 small shields 10 frames, Sekiro 12 decaying to 4 under mashing.
@export var ms_deflect_window: int = 200

## How long after a deflect before another is possible, so mashing is not a
## strategy. Sekiro's decaying window is the more sophisticated answer; a flat
## cooldown is the honest first version.
@export var ms_deflect_cooldown: int = 400

@export_group("Movement")
## Fraction of normal speed while the shield is up. Guarding should cost mobility.
@export_range(0.0, 1.0) var move_scale: float = 0.45


func is_shield() -> bool:
	return true
