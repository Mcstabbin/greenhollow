class_name AttackStep
extends Resource
## One swing in a weapon's chain: which clip plays, what it does on contact, and
## how long the player is committed to it.
##
## This is the engine's own pattern. `godot-demo-projects`
## (2d/finite_state_machine/player/weapon/sword.gd, MIT) holds a combo as an array
## of `{damage, animation, effect}` dictionaries and drives its commitment windows
## from AnimationPlayer method tracks — see PRIOR-ART.md. Typed here rather than
## dictionaries, because a misspelled key in a dictionary is silence.
##
## Timing lives here AND in the clip. The numbers below are what
## tools/build_combat_anims.gd reads to place the method-track keyframes, so the
## clip and the data can never disagree: one is generated from the other.
##
## The point of this resource is that a heavy weapon is a set of NUMBERS, not a
## code path. If the axe ever needs its own branch in the player, this model is
## wrong and should be fixed rather than special-cased.

## Clip to travel to in the AnimationTree's state machine.
@export var clip: StringName = &"slash_a"

## What contact does. `HealthAction` comes from the vendored addon
## (cluttered-code/godot-health-hitbox-hurtbox, MIT), so damage type, amount and
## affect are all expressible without this resource knowing about health at all.
## An array because one hit can carry several effects.
@export var actions: Array[HealthAction] = []

@export_group("Timing", "ms_")
## Press to the hitbox arming. REFERENCE.md band: 80-150 ms for a light attack.
## Long enough to read as a wind-up, short enough to feel responsive.
@export var ms_windup: int = 133
## How long the hitbox stays armed. Band: 80-130 ms.
@export var ms_active: int = 100
## Press to the next input being accepted. Band: 300-500 ms. Below 300 it mashes
## into noise; above 500 it feels stuck.
@export var ms_commitment: int = 417

@export_group("Feel")
## Fraction of recovery in which a defensive action may interrupt. Band: the last
## 30-40%. Its absence is what makes hand-rolled combat feel like glue.
@export_range(0.0, 1.0) var cancel_window: float = 0.375
## Metres the victim is pushed. Applied from the hitbox's position, not the
## attacker's origin, so a glancing hit shoves sideways.
@export var knockback: float = 0.6
## Freeze applied to both parties on contact, in milliseconds. The single
## highest-value number in combat feel. Never via Engine.time_scale — that is
## ignored by AudioStreamPlayer; scale the participating AnimationTrees.
@export var ms_hitstop: int = 80


## Convenience for the probe and for the generator, which both think in frames.
func windup_frames(hz: int = 60) -> int:
	return roundi(ms_windup * hz / 1000.0)


func active_frames(hz: int = 60) -> int:
	return roundi(ms_active * hz / 1000.0)


func commitment_frames(hz: int = 60) -> int:
	return roundi(ms_commitment * hz / 1000.0)
