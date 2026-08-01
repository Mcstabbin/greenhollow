extends SceneTree
## Generates actors/player/player_anims.tres — the player's whole AnimationLibrary —
## plus the procedural combat SFX under actors/player/audio/.
##
## Run:  godot --headless --path . --script res://tools/build_combat_anims.gd
##
## Why this exists at all: art/models/character.glb ships exactly four clips
## (idle, walk, jump, static) and no attacks. It also has NO Skeleton3D — the rig
## is seven plain Node3D/MeshInstance3D nodes, and the imported clips are ordinary
## POSITION_3D/ROTATION_3D tracks against node paths. So authoring new clips is
## just writing more of the same track type; no skinning involved. These are real
## keyframed clips, not a procedural pose driven from code.
##
## Following tools/build_clearing.gd: this emits a REAL resource. Re-running
## overwrites it, so fold hand edits back in here or stop running it.
##
## Two deliberate structural choices:
##
##  1. The generated library contains COPIES of the four glb clips with every
##     track re-pathed from `character/...` to `Rig/Character/character/...`.
##     That lets player.tscn own its own AnimationPlayer whose root_node is the
##     Player, instead of overriding properties on a node inside an instanced
##     .glb — which CLAUDE.md records as a thing that silently gets dropped.
##     It also bakes LOOP_LINEAR into idle and walk at build time rather than
##     patching it at runtime.
##  2. Attack timing windows are Call Method Tracks on the clips, not timers in
##     code. That is Snaiel's pattern (PRIOR-ART.md): the window lives in the
##     same resource as the animation it has to match, so they cannot drift.
##     Methods are called on the Player itself (track path ".").

const MODEL := "res://art/models/character.glb"
const LIB_PATH := "res://actors/player/player_anims.tres"
const AUDIO_DIR := "res://actors/player/audio"

## Every generated track is relative to the Player, because that is what the
## owned AnimationPlayer's root_node points at.
const P := "Rig/Character/"
const N_ROOT := P + "character/root"
const N_LEG_L := P + "character/root/leg-left"
const N_LEG_R := P + "character/root/leg-right"
const N_TORSO := P + "character/root/torso"
const N_ARM_L := P + "character/root/torso/arm-left"
const N_ARM_R := P + "character/root/torso/arm-right"
const N_ANT := P + "character/root/torso/antenna"
## The sword grip, which player.tscn adds under the right arm. Driven by EVERY
## clip in the library, locomotion included, because a node animated by only some
## clips snaps back to whatever the last one left it at.
const N_GRIP := P + "character/root/torso/arm-right/SwordGrip"

## How the sword sits when nothing is swinging. Measured: the idle clip already
## rotates arm-right 32 degrees down, and blade elevation works out as
## 90 - (grip_z + arm_z), so a grip_z of 90 puts the blade in line with the arm
## and a small grip_z lifts it clear of it. At 14 the resting blade sits about 45
## degrees above the arm instead of jutting straight out sideways.
const GRIP_REST := Vector3(0.0, 25.0, 14.0)
## In line with the arm, so the blade extends the limb through the whole cut and
## the tip traces the widest, most readable arc it can.
const GRIP_CUT := Vector3(0.0, 5.0, 95.0)

## Rest positions, read off the glb's `static` clip.
const REST_ROOT := Vector3(0.0, 0.02375, 0.0)
const REST_LEG_L := Vector3(0.125, 0.17625, -0.02375)
const REST_LEG_R := Vector3(-0.125, 0.17625, -0.02375)

const F := 1.0 / 60.0  ## one 60 Hz frame, so keys land on physics ticks

const MIX_RATE := 22050


func _initialize() -> void:
	var lib := AnimationLibrary.new()

	_copy_glb_clips(lib)

	lib.add_animation(&"slash_a", _build_slash_a())
	lib.add_animation(&"slash_b", _build_slash_b())
	lib.add_animation(&"spin_attack", _build_spin())

	var err := ResourceSaver.save(lib, LIB_PATH)
	if err != OK:
		printerr("could not save %s (error %d)" % [LIB_PATH, err])
		quit(1)
		return
	print("wrote %s" % LIB_PATH)
	for name in lib.get_animation_list():
		var a: Animation = lib.get_animation(name)
		print("  %-12s len=%.4f loop=%d tracks=%d" % [name, a.length, a.loop_mode, a.get_track_count()])

	_build_audio()
	quit(0)


# --- The glb's own clips, re-pathed ---------------------------------------

func _copy_glb_clips(lib: AnimationLibrary) -> void:
	var root: Node = (load(MODEL) as PackedScene).instantiate()
	var ap: AnimationPlayer = root.get_node("AnimationPlayer")
	for name in ap.get_animation_list():
		var src: Animation = ap.get_animation(name)
		var copy: Animation = src.duplicate(true)
		for t in copy.get_track_count():
			copy.track_set_path(t, NodePath(P + String(copy.track_get_path(t))))
		# Hold the sword at its rest angle. One key is enough for a constant.
		var grip := copy.add_track(Animation.TYPE_ROTATION_3D)
		copy.track_set_path(grip, NodePath(N_GRIP))
		copy.rotation_track_insert_key(grip, 0.0, _q(GRIP_REST))
		# Locomotion has to loop; glTF imports everything as LOOP_NONE.
		copy.loop_mode = Animation.LOOP_LINEAR if name in ["idle", "walk"] else Animation.LOOP_NONE
		lib.add_animation(StringName(name), copy)
	root.free()


# --- Attack clips ---------------------------------------------------------
#
# Rig geometry, measured: the character faces +Z, its right arm pivots at
# torso-local (-0.3, 0.12, 0) and the limb extends along -X. With Godot's
# default YXZ euler order the rotation decomposes exactly the way an animator
# wants it: Z raises/lowers the arm (negative = up), Y sweeps it forward and
# across the body (positive = across), X rolls the blade.
#
# A pose is one dictionary; keys default to the rest pose when absent:
#   root_y  float   vertical offset of the hips, metres in rig-local units
#   root    Vector3 hip euler, degrees
#   torso   Vector3 chest euler, degrees
#   arm_r   Vector3 sword arm
#   arm_l   Vector3 off arm
#   ant     Vector3 head plume — cheap follow-through, sells the whip
#   leg_l   Vector3
#   leg_r   Vector3

## Keyframe times are chosen against MEASURED latency, not clip-local time. There
## is a fixed three-frame pipeline between a button going down and a method track
## being observable: one frame for the action to register as just-pressed, and two
## for the AnimationTree — which processes after the Player in the same physics
## tick — to advance the clip past the key. Measured with tools/probe.gd, twice,
## on both the hitbox and the cancel key. So a key at frame K reads as K+3.
##
## Slash, as the probe measures it: wind-up 133 ms, hitbox live 100 ms, total
## commitment 400 ms. Recovery runs 11 -> 27 (267 ms) and the cancel key at 21
## leaves 6 of those 16 frames, i.e. the last 37.5%. REFERENCE.md asks for
## 80-150 / 80-130 / 300-500 / last 30-40%.
const SLASH_LEN := 27.0 * F        # 0.450
const SLASH_HIT_ON := 5.0 * F      # 0.08333 -> measures 133 ms
const SLASH_HIT_OFF := 11.0 * F    # 0.18333 -> 100 ms live
const SLASH_CANCEL := 21.0 * F     # 0.35    -> 400 ms commitment

## The spin is deliberately outside the slash bands in both directions: a slower
## tell because it is a 360 degree sweep, a longer live window because the blade
## really is out there for two revolutions, and a much bigger commitment because
## that is the price of the charge. 167 ms wind-up, 300 ms live, 650 ms commit.
const SPIN_LEN := 42.0 * F         # 0.700
const SPIN_HIT_ON := 7.0 * F       # 0.11667 -> measures 167 ms
const SPIN_HIT_OFF := 25.0 * F     # 0.41667 -> 300 ms live
const SPIN_CANCEL := 36.0 * F      # 0.600   -> 650 ms commitment


func _build_slash_a() -> Animation:
	# Overhead-right, then a level sweep across the front. Kept at chest height on
	# purpose: an earlier pass let the arc finish at ankle level, where the blade
	# read as a stick in the grass and half the swing was hidden behind a log. A
	# slash wants sky or trees behind it. Blade elevation works out as
	# 90 - (grip_z + arm_z), so arm_z is what keeps the cut up.
	var keys: Array = [
		[0.0 * F, {"grip": Vector3(0, 20, 40), "torso": Vector3(0, -20, 0), "arm_r": Vector3(0, -25, -70),
			"arm_l": Vector3(0, 10, -25), "ant": Vector3(0, 15, 6)}],
		[2.0 * F, {"grip": GRIP_CUT, "root_y": -0.022, "root": Vector3(-6, 0, 0), "torso": Vector3(4, -36, 0),
			"arm_r": Vector3(0, -55, -112), "arm_l": Vector3(0, 26, -42),
			"ant": Vector3(0, 32, 10), "leg_r": Vector3(-10, 0, 0)}],
		[5.0 * F, {"grip": GRIP_CUT, "root_y": -0.008, "root": Vector3(4, 0, 0), "torso": Vector3(2, -14, 0),
			"arm_r": Vector3(0, -30, -42), "arm_l": Vector3(0, 16, -22),
			"ant": Vector3(0, 14, 4), "leg_l": Vector3(-8, 0, 0)}],
		[8.0 * F, {"grip": GRIP_CUT, "root": Vector3(8, 0, 0), "torso": Vector3(4, 20, 0),
			"arm_r": Vector3(0, 34, -26), "arm_l": Vector3(0, -20, 10),
			"ant": Vector3(0, -24, -8), "leg_l": Vector3(-16, 0, 0)}],
		[11.0 * F, {"grip": GRIP_CUT, "root": Vector3(6, 0, 0), "torso": Vector3(6, 38, 0),
			"arm_r": Vector3(0, 104, -8), "arm_l": Vector3(0, -42, 20),
			"ant": Vector3(0, -42, -14), "leg_l": Vector3(-14, 0, 0),
			"leg_r": Vector3(6, 0, 0)}],
		[16.0 * F, {"grip": Vector3(0, 15, 70), "root": Vector3(2, 0, 0), "torso": Vector3(2, 18, 0),
			"arm_r": Vector3(0, 56, -30), "arm_l": Vector3(0, -20, 6),
			"ant": Vector3(0, -14, -4), "leg_l": Vector3(-8, 0, 0)}],
		[21.0 * F, {"grip": Vector3(0, 20, 35), "torso": Vector3(0, 4, 0), "arm_r": Vector3(0, 16, -46),
			"arm_l": Vector3(0, -4, -14), "ant": Vector3(0, -2, 0),
			"leg_l": Vector3(-3, 0, 0)}],
		[27.0 * F, {"arm_r": Vector3(0, 0, 25)}],
	]
	return _assemble("slash_a", SLASH_LEN, keys,
		SLASH_HIT_ON, SLASH_HIT_OFF, SLASH_CANCEL)


func _build_slash_b() -> Animation:
	# The return stroke: a rising backhand that starts where slash_a finished and
	# sweeps back out to high-right. Sharing that endpoint is what makes the pair
	# read as one continuous combo rather than two copies of the same swing.
	var keys: Array = [
		[0.0 * F, {"grip": GRIP_CUT, "torso": Vector3(4, 30, 0), "arm_r": Vector3(0, 98, -12),
			"arm_l": Vector3(0, -30, 12), "ant": Vector3(0, -28, -8)}],
		[2.0 * F, {"grip": GRIP_CUT, "root_y": -0.016, "root": Vector3(-4, 0, 0), "torso": Vector3(8, 40, 0),
			"arm_r": Vector3(0, 126, -2), "arm_l": Vector3(0, -44, 20),
			"ant": Vector3(0, -38, -12), "leg_l": Vector3(-12, 0, 0)}],
		[5.0 * F, {"grip": GRIP_CUT, "root": Vector3(2, 0, 0), "torso": Vector3(4, 14, 0),
			"arm_r": Vector3(0, 60, -28), "arm_l": Vector3(0, -24, 0),
			"ant": Vector3(0, -12, -4), "leg_r": Vector3(-8, 0, 0)}],
		[8.0 * F, {"grip": GRIP_CUT, "root": Vector3(-2, 0, 0), "torso": Vector3(0, -16, 0),
			"arm_r": Vector3(0, 0, -52), "arm_l": Vector3(0, 14, -18),
			"ant": Vector3(0, 22, 8), "leg_r": Vector3(-14, 0, 0)}],
		[11.0 * F, {"grip": GRIP_CUT, "root": Vector3(-6, 0, 0), "torso": Vector3(-4, -36, 0),
			"arm_r": Vector3(0, -48, -102), "arm_l": Vector3(0, 28, -34),
			"ant": Vector3(0, 38, 14), "leg_r": Vector3(-12, 0, 0),
			"leg_l": Vector3(6, 0, 0)}],
		[16.0 * F, {"grip": Vector3(0, 15, 70), "root": Vector3(-2, 0, 0), "torso": Vector3(-2, -16, 0),
			"arm_r": Vector3(0, -22, -70), "arm_l": Vector3(0, 14, -20),
			"ant": Vector3(0, 16, 6), "leg_r": Vector3(-7, 0, 0)}],
		[21.0 * F, {"grip": Vector3(0, 20, 35), "torso": Vector3(0, -4, 0), "arm_r": Vector3(0, -6, -40),
			"arm_l": Vector3(0, 4, -8), "ant": Vector3(0, 4, 2),
			"leg_r": Vector3(-2, 0, 0)}],
		[27.0 * F, {"arm_r": Vector3(0, 0, 25)}],
	]
	return _assemble("slash_b", SLASH_LEN, keys,
		SLASH_HIT_ON, SLASH_HIT_OFF, SLASH_CANCEL)


func _build_spin() -> Animation:
	# Two full revolutions with the blade held out level. The hips carry the
	# rotation, keyed every 120 degrees so quaternion slerp always takes the
	# short way round and the spin never reverses.
	var keys: Array = [
		[0.0 * F, {"grip": Vector3(0, 20, 40), "torso": Vector3(0, 10, 0), "arm_r": Vector3(0, 30, -40),
			"arm_l": Vector3(0, -10, -20), "ant": Vector3(0, 10, 0)}],
		[3.0 * F, {"grip": Vector3(0, 10, 80), "root_y": -0.045, "root": Vector3(-8, 30, 0), "torso": Vector3(10, 24, 0),
			"arm_r": Vector3(0, 60, -78), "arm_l": Vector3(0, -18, -34),
			"ant": Vector3(0, 22, 0), "leg_l": Vector3(-14, 0, 0),
			"leg_r": Vector3(-14, 0, 0)}],
		# Blade snaps out level; from here the arms hold while the hips spin.
		[7.0 * F, {"grip": GRIP_CUT, "root_y": -0.010, "root": Vector3(4, 0, 0), "torso": Vector3(10, 0, 0),
			"arm_r": Vector3(0, 14, -20), "arm_l": Vector3(0, -14, -4),
			"ant": Vector3(0, 0, -26), "leg_l": Vector3(-8, 0, 0)}],
		[10.0 * F, {"grip": GRIP_CUT, "root_y": 0.014, "root": Vector3(4, -120, 0), "torso": Vector3(10, 0, 0),
			"arm_r": Vector3(0, 16, -22), "arm_l": Vector3(0, -16, -2),
			"ant": Vector3(0, 0, -30), "leg_l": Vector3(-6, 0, 0)}],
		[13.0 * F, {"grip": GRIP_CUT, "root_y": 0.020, "root": Vector3(4, -240, 0), "torso": Vector3(10, 0, 0),
			"arm_r": Vector3(0, 14, -20), "arm_l": Vector3(0, -14, -4),
			"ant": Vector3(0, 0, -32), "leg_l": Vector3(-6, 0, 0)}],
		[16.0 * F, {"grip": GRIP_CUT, "root_y": 0.020, "root": Vector3(4, -360, 0), "torso": Vector3(10, 0, 0),
			"arm_r": Vector3(0, 16, -22), "arm_l": Vector3(0, -16, -2),
			"ant": Vector3(0, 0, -32), "leg_l": Vector3(-6, 0, 0)}],
		[19.0 * F, {"grip": GRIP_CUT, "root_y": 0.014, "root": Vector3(4, -480, 0), "torso": Vector3(10, 0, 0),
			"arm_r": Vector3(0, 14, -20), "arm_l": Vector3(0, -14, -4),
			"ant": Vector3(0, 0, -30), "leg_l": Vector3(-6, 0, 0)}],
		[22.0 * F, {"grip": GRIP_CUT, "root_y": 0.006, "root": Vector3(4, -600, 0), "torso": Vector3(8, 0, 0),
			"arm_r": Vector3(0, 16, -18), "arm_l": Vector3(0, -16, -6),
			"ant": Vector3(0, 0, -24), "leg_l": Vector3(-4, 0, 0)}],
		[25.0 * F, {"grip": GRIP_CUT, "root": Vector3(2, -720, 0), "torso": Vector3(6, 0, 0),
			"arm_r": Vector3(0, 20, -10), "arm_l": Vector3(0, -20, -10),
			"ant": Vector3(0, 0, -16)}],
		# Recovery: absorb, then stand up.
		[30.0 * F, {"grip": Vector3(0, 15, 60), "root_y": -0.030, "root": Vector3(-10, -720, 0), "torso": Vector3(12, -8, 0),
			"arm_r": Vector3(0, 26, -34), "arm_l": Vector3(0, -22, -26),
			"ant": Vector3(0, -8, 8), "leg_l": Vector3(-16, 0, 0),
			"leg_r": Vector3(10, 0, 0)}],
		[36.0 * F, {"grip": Vector3(0, 20, 30), "root_y": -0.010, "root": Vector3(-4, -720, 0), "torso": Vector3(4, -4, 0),
			"arm_r": Vector3(0, 10, -14), "arm_l": Vector3(0, -8, -12),
			"ant": Vector3(0, -4, 3), "leg_l": Vector3(-6, 0, 0)}],
		[42.0 * F, {"root": Vector3(0, -720, 0)}],
	]
	return _assemble("spin_attack", SPIN_LEN, keys,
		SPIN_HIT_ON, SPIN_HIT_OFF, SPIN_CANCEL)


## Turn a pose list into the same ten transform tracks the glb clips use — same
## track set, so the AnimationTree can cross-fade between locomotion and attacks
## without a limb popping back to rest mid-blend — plus the method tracks.
func _assemble(name: String, length: float, keys: Array,
		hit_on: float, hit_off: float, cancel: float) -> Animation:
	var a := Animation.new()
	a.resource_name = name
	a.length = length
	a.loop_mode = Animation.LOOP_NONE  # an attack that loops is a bug

	var root_pos := _track(a, Animation.TYPE_POSITION_3D, N_ROOT)
	var root_rot := _track(a, Animation.TYPE_ROTATION_3D, N_ROOT)
	var leg_l_pos := _track(a, Animation.TYPE_POSITION_3D, N_LEG_L)
	var leg_l_rot := _track(a, Animation.TYPE_ROTATION_3D, N_LEG_L)
	var leg_r_pos := _track(a, Animation.TYPE_POSITION_3D, N_LEG_R)
	var leg_r_rot := _track(a, Animation.TYPE_ROTATION_3D, N_LEG_R)
	var torso_rot := _track(a, Animation.TYPE_ROTATION_3D, N_TORSO)
	var arm_l_rot := _track(a, Animation.TYPE_ROTATION_3D, N_ARM_L)
	var arm_r_rot := _track(a, Animation.TYPE_ROTATION_3D, N_ARM_R)
	var ant_rot := _track(a, Animation.TYPE_ROTATION_3D, N_ANT)
	var grip_rot := _track(a, Animation.TYPE_ROTATION_3D, N_GRIP)

	# The legs never translate in these clips, but the tracks have to exist or
	# blending out of `walk` (which does translate them) leaves them displaced.
	a.position_track_insert_key(leg_l_pos, 0.0, REST_LEG_L)
	a.position_track_insert_key(leg_r_pos, 0.0, REST_LEG_R)

	for entry_v: Array in keys:
		var t: float = entry_v[0]
		var pose: Dictionary = entry_v[1]
		a.position_track_insert_key(root_pos, t,
			REST_ROOT + Vector3(0.0, float(pose.get("root_y", 0.0)), 0.0))
		a.rotation_track_insert_key(root_rot, t, _q(pose.get("root", Vector3.ZERO)))
		a.rotation_track_insert_key(leg_l_rot, t, _q(pose.get("leg_l", Vector3.ZERO)))
		a.rotation_track_insert_key(leg_r_rot, t, _q(pose.get("leg_r", Vector3.ZERO)))
		a.rotation_track_insert_key(torso_rot, t, _q(pose.get("torso", Vector3.ZERO)))
		a.rotation_track_insert_key(arm_l_rot, t, _q(pose.get("arm_l", Vector3.ZERO)))
		a.rotation_track_insert_key(arm_r_rot, t, _q(pose.get("arm_r", Vector3.ZERO)))
		a.rotation_track_insert_key(ant_rot, t, _q(pose.get("ant", Vector3.ZERO)))
		a.rotation_track_insert_key(grip_rot, t, _q(pose.get("grip", GRIP_REST)))

	# --- The windows. PRIOR-ART.md: these belong beside the animation. -------
	var m := _track(a, Animation.TYPE_METHOD, ".")
	_call(a, m, hit_on, "_anim_hitbox_on")
	_call(a, m, hit_off, "_anim_hitbox_off")
	_call(a, m, cancel, "_anim_allow_cancel")
	# One frame inside the clip: a key exactly at `length` is not guaranteed to
	# fire on a non-looping clip that stops at its own end.
	_call(a, m, length - F, "_anim_attack_finished")
	return a


func _track(a: Animation, type: Animation.TrackType, path: String) -> int:
	var idx := a.add_track(type)
	a.track_set_path(idx, NodePath(path))
	if type == Animation.TYPE_ROTATION_3D or type == Animation.TYPE_POSITION_3D:
		a.track_set_interpolation_type(idx, Animation.INTERPOLATION_LINEAR)
	return idx


func _call(a: Animation, track: int, time: float, method: String) -> void:
	a.track_insert_key(track, time, {"method": StringName(method), "args": []})


func _q(euler_deg: Variant) -> Quaternion:
	var e: Vector3 = euler_deg
	return Quaternion.from_euler(Vector3(
		deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))


# --- Procedural SFX ------------------------------------------------------
#
# audio/sfx/ has no combat sounds and this generator must not invent copyrighted
# ones. These are synthesised from noise and sines and saved as AudioStreamWAV
# .tres resources — .tres rather than .wav so there is no import step to get
# wrong, and under actors/player/ because that is what owns them.

func _build_audio() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIO_DIR))
	_save_wav("swing", _synth_swing(0.20, 1500.0, 380.0))
	_save_wav("swing_heavy", _synth_swing(0.42, 900.0, 180.0))
	_save_wav("charge_ready", _synth_chime())
	_save_wav("hit", _synth_hit())


## A blade swoosh: white noise through a one-pole low-pass whose cutoff sweeps
## down, which is what gives a whoosh its sense of direction.
func _synth_swing(dur: float, cut_start: float, cut_end: float) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91117
	var lp := 0.0
	for i in n:
		var u := float(i) / float(n)
		var cut: float = lerpf(cut_start, cut_end, u * u)
		var alpha: float = clampf(1.0 - exp(-TAU * cut / float(MIX_RATE)), 0.0, 1.0)
		lp += alpha * (rng.randf_range(-1.0, 1.0) - lp)
		# Swell in, fall away — a swing is loudest at the middle of the arc.
		var env: float = sin(PI * pow(u, 0.7))
		out[i] = lp * env * 2.6
	return out


## The charge tell. Two clean tones a fifth apart, short and bell-like, so it
## cuts through footsteps and reads as "ready" rather than as an impact.
func _synth_chime() -> PackedFloat32Array:
	var dur := 0.34
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var u := t / dur
		var env: float = exp(-5.5 * u) * minf(1.0, u * 240.0)
		var s := sin(TAU * 784.0 * t) * 0.55
		s += sin(TAU * 1176.0 * t) * 0.35
		s += sin(TAU * 2352.0 * t) * 0.12
		out[i] = s * env * 0.8
	return out


## Impact: a short noise crack over a pitched-down thump.
func _synth_hit() -> PackedFloat32Array:
	var dur := 0.16
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp := 0.0
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var u := t / dur
		lp += 0.35 * (rng.randf_range(-1.0, 1.0) - lp)
		var crack: float = lp * exp(-22.0 * u)
		var thump: float = sin(TAU * lerpf(240.0, 70.0, u) * t) * exp(-11.0 * u)
		out[i] = clampf(crack * 1.4 + thump * 0.9, -1.0, 1.0)
	return out


func _save_wav(name: String, samples: PackedFloat32Array) -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	stream.data = bytes
	var path := "%s/%s.tres" % [AUDIO_DIR, name]
	var err := ResourceSaver.save(stream, path)
	if err != OK:
		printerr("could not save %s (error %d)" % [path, err])
		return
	print("wrote %s (%.2fs, %d samples)" % [path, samples.size() / float(MIX_RATE), samples.size()])
