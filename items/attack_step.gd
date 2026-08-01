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

## Measured, not chosen: there is a fixed three-frame pipeline between the button
## going down and a method track being observable — one frame for `just_pressed`, two
## more for the AnimationTree, which processes after the Player inside the same physics
## tick. CLAUDE.md records it, twice measured, on two different keys. A key authored at
## frame K is therefore observed at K + 3.
const INPUT_LATENCY_FRAMES := 3

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


## Playback rate for `clip` that makes `ms_windup` come true, and the single reason a
## heavier weapon needs no code.
##
## There are three hand-authored attack clips in the project and their windows are
## method-track keyframes, so a weapon cannot have its own keyframe times without a
## second set of clips. What it CAN have is the same clip played slower: method tracks
## fire on CLIP time, so at 0.625x the wind-up, the live window and the commitment all
## move out together, in proportion. That is what "heavier" means — the axe is a
## playback rate and a damage number, not a branch.
##
## `authored` is where the clip's own `_anim_hitbox_on` key sits, in frames, read off
## the Animation by the caller so no frame number is duplicated here.
##
## Arithmetic in whole FRAMES on purpose. Milliseconds would put the sword at 1.004
## rather than 1.0 (133 ms is 7.98 frames, not 8), and a clip running four parts in a
## thousand off its authored rate can sit a fraction of a microsecond behind its own
## keyframe on the tick that key is due — which opens the window a WHOLE FRAME late and
## moves every measured number in the combat suite. Integers cannot do that.
func clip_scale(authored: int, hz: int = 60) -> float:
	var want := windup_frames(hz) - INPUT_LATENCY_FRAMES
	if want <= 0 or authored <= 0:
		return 1.0
	return float(authored) / float(want)


## Where a clip arms its hitbox, in frames of its own time. Read from the resource
## rather than restated here, so retiming a clip in tools/build_combat_anims.gd cannot
## silently disagree with the weapons that play it.
static func authored_windup_frames(anim: Animation, hz: int = 60) -> int:
	if anim == null:
		return 0
	for track in anim.get_track_count():
		if anim.track_get_type(track) != Animation.TYPE_METHOD:
			continue
		for key in anim.track_get_key_count(track):
			var value: Dictionary = anim.track_get_key_value(track, key)
			if String(value.get("method", "")) == "_anim_hitbox_on":
				return roundi(anim.track_get_key_time(track, key) * hz)
	return 0


## Convenience for the probe and for the generator, which both think in frames.
func windup_frames(hz: int = 60) -> int:
	return roundi(ms_windup * hz / 1000.0)


func active_frames(hz: int = 60) -> int:
	return roundi(ms_active * hz / 1000.0)


func commitment_frames(hz: int = 60) -> int:
	return roundi(ms_commitment * hz / 1000.0)
