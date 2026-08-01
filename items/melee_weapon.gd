class_name MeleeWeapon
extends ItemData
## A swung weapon. The difference between the sword and the axe is entirely in
## these numbers — see AttackStep. If either ever needs its own branch in the
## player, this model has failed and should be fixed rather than special-cased.

## The chain, in order. Pressing attack again inside a step's cancel window
## advances to the next; running off the end wraps to the first. Per-step damage
## is what lets a heavy weapon's finisher hit harder than its opener for free.
@export var steps: Array[AttackStep] = []

## The charged attack, if the weapon has one. Null means holding attack does
## nothing, which is the right answer for some weapons.
@export var charged: AttackStep

## Milliseconds of hold before the charged attack is available. REFERENCE.md band:
## 900-1300 ms, and it needs an audible AND visual tell at the threshold — a
## forced-choice critic rated our colour-only charge tell the single weakest frame
## in the set, so a new weapon must not repeat that.
@export var ms_charge: int = 1067

@export_group("Hitbox")
## Sized in world units and applied to the weapon scene's own hitbox, so a long
## axe head does not need a hand-matched capsule in four places.
@export var hitbox_radius: float = 0.13
@export var hitbox_height: float = 0.9

@export_group("Trail")
## The mid band of the trail's three-band ramp. Core stays near-white and the
## outer edge stays near-black whatever this is, because an effect has to carry
## its own contrast rather than borrow the background's — see PRIOR-ART-VISUAL.md.
@export var trail_tint: Color = Color(1.0, 0.36, 0.02)
## Visible duration. Band: 10-18 frames, 0.17-0.30 s. Longer than that and the
## ribbon is still fading during the next input window.
@export var ms_trail: int = 230


func is_melee() -> bool:
	return true


## Total commitment of the whole chain, for the probe and for sanity checks
## against enemy telegraph lengths.
func chain_commitment_ms() -> int:
	var total := 0
	for step in steps:
		total += step.ms_commitment
	return total
