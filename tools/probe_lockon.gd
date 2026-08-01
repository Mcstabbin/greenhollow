extends RefCounted
## The lock-on suite of tools/probe.gd, in its own file.
##
## Split out for one measured reason: with it inlined, probe.gd came to 1558 lines
## against `.gdlintrc`'s 1200-line ceiling, and that ceiling exists so no second file
## the size of the level generator gets licensed by accident. Four suites of dense
## declarative measurement plus the reasoning behind each number does not fit in one
## file, and it was never going to — hit feedback and enemies are still to come. So the
## seam is here rather than one suite later.
##
## The harness keeps everything stateful: the level, the player, the frame pump, the
## measurement list. This file reaches through the small public API probe.gd exposes
## for exactly that — `add`, `frames`, `frames_until`, `reset`, `release_all`, `ms`,
## `equip`, `swing_once`, `player`, `level` — so the split costs no duplicated
## plumbing and the suite stays scene-driven, which PRIOR-ART.md is explicit about
## keeping.
##
## Usage, from probe.gd's suite dispatch:
##
##     await LockOnSuite.new(self).run()

## Item resources this suite equips. Duplicated from probe.gd deliberately: a const on
## another script is not reachable through an instance reference, and two paths is a
## smaller price than a getter for each.
const ITEM_SWORD := "res://items/sword.tres"
const ITEM_BOW := "res://items/bow.tres"

## The probe harness. Deliberately typed as Node rather than as the probe's own class:
## the probe has no class_name, and this file has no business knowing more about it
## than the ten methods listed above.
var _p: Node = null


func _init(probe: Node) -> void:
	_p = probe


## Run the suite. The claims under test, in the order they are made:
##
##  1. THE SELECTION RULE IS SCREEN SPACE, NOT 3D DISTANCE. `lockon_picks_screen_centre`
##     is the whole of why Ocarina-style targeting feels like it reads intent: given a
##     target 9 m away dead ahead and one 6 m away well off to the side, the far one is
##     the one you get. If that flips, the feature has been quietly rewritten.
##  2. THE RANGES ARE OURS. Acquire and break are measured by walking a real target out
##     until each fails, so the hysteresis gap is a measurement rather than a subtraction
##     of two exported numbers.
##  3. BOTH PLAYER AND TARGET ARE ON SCREEN IN EVERY LOCKED FRAME. REFERENCE.md calls
##     this non-negotiable and it is the one figure here that is pass/fail rather than a
##     band. Four points are unprojected every locked frame — the target's aim point and
##     the player's feet, chest and head — through strafing, two swings and a target
##     switch, and the smallest margin to any frame edge is reported alongside the
##     percentage so a near miss is visible before it becomes a miss.
##  4. A SWING WITH A TARGET TURNS TO IT. `attack_faces_target` against
##     `attack_faces_ahead_unlocked` is the prop-occlusion answer measured rather than
##     asserted, and `prop_over_arc_*` measures what it actually buys.
func run() -> void:
	await _reset_lockon()
	var lock: Node = _lockon()
	_p.add("lockon_system_present", 1.0 if lock != null else -1.0, "bool",
		"the player carries a LockOnSystem at CameraPivot's level")
	if lock == null:
		return
	_p.add("lockon_dummies_in_level",
		float(_p.get_tree().get_nodes_in_group("target_dummy").size()), "count",
		"2 — the sparring ground, so lock-on is playable and not merely implemented")
	_p.add("lockon_acquire_range_setting", float(lock.get("acquire_range")), "m",
		"REFERENCE.md band 8-14 m, against a play area of ±24 m")
	_p.add("lockon_dummies_in_range_at_spawn", float(lock.call("candidate_count")), "count",
		"both dummies are inside the detection sphere from the spawn without moving,"
		+ " 5.1 and 6.5 m away — though not lockable from there, because they stand"
		+ " behind the camera's default facing")
	# Turned round to face the sparring ground first, and that is the measurement
	# working rather than a fudge: the dummies stand NORTH of the spawn at z 13-15.5,
	# so from the default facing they are behind the camera and the lock refuses them —
	# correctly. This assertion is about the dummy scene being wired, not about whether
	# a target behind you is lockable, which `lockon_acquire_range` covers.
	await _reset_lockon(180.0)
	_p.add("lockon_locks_level_dummy", 1.0 if await _press_target(lock) else -1.0, "bool",
		"the real dummy scene, not just a target this file built: LockOnTarget wired"
		+ " through node_paths, anchored at the chest, health connected")
	lock.call("release")
	await _reset_lockon()

	# Everything below spawns its own targets at controlled distances and bearings, so
	# the level's two dummies have to stand down first. Leaving them in cost a real
	# measurement: `lockon_acquire_range` came back as 20 m, the loop's own ceiling,
	# because once the spawned target passed 12 m a DUMMY 11.8 m away kept satisfying
	# the press and the loop never saw a failure.
	_set_dummies_targetable(false)

	# --- Acquisition, and the rule that decides WHICH target ----------------
	var ahead := _spawn_lock_target(6.0, 0.0, 1.05)
	await _p.frames(8)
	_p.add("lockon_candidates", float(lock.call("candidate_count")), "count",
		"one spawned target in range and visible, the dummies stood down")
	Input.action_press("target")
	var frames: int = await _p.frames_until(
		func() -> bool: return bool(lock.call("is_locked")), 60)
	Input.action_release("target")
	_p.add("lockon_acquire", _p.ms(frames), "ms",
		"press to locked. REFERENCE.md band is 50-150 ms as a CEILING — the state flips"
		+ " on the tick the press is read, and the 110 ms the reticle takes to close"
		+ " (ui/lockon_reticle.gd ACQUIRE_TIME) is what the player actually perceives")
	_p.add("lockon_release_toggles", 1.0 if not await _press_target(lock) else -1.0, "bool",
		"a second press lets go — Z-targeting is a toggle, not a hold")
	ahead.queue_free()
	await _p.frames(4)

	# The load-bearing test. Far and centred beats near and off to the side.
	await _reset_lockon()
	var centred := _spawn_lock_target(9.0, 0.0, 1.05)
	var nearer := _spawn_lock_target(5.0, 3.6, 1.05)
	await _p.frames(8)
	await _press_target(lock)
	var picked: Node = lock.get("target")
	_p.add("lockon_picks_screen_centre",
		1.0 if picked == centred.get_node("LockOnTarget") else -1.0, "bool",
		"the target 9 m away dead ahead wins over the one 6.1 m away 36 degrees off:"
		+ " selection is screen-space distance from the centre of frame, never 3D range")
	_p.add("lockon_switch",
		_p.ms(await _measure_switch(lock, centred.get_node("LockOnTarget"))), "ms",
		"look axis held to the lock moving to the other target. REFERENCE.md band <120 ms")
	centred.queue_free()
	nearer.queue_free()
	await _p.frames(4)
	_p.release_all()

	await _measure_lock_ranges(lock)
	await _measure_lock_framing(lock)
	await _measure_lock_breaks(lock)
	await _measure_attack_facing(lock)
	await _measure_prop_occlusion(lock)
	await _measure_aim_camera()
	_set_dummies_targetable(true)


## Stand the level's dummies down, or back up. `targetable` is the flag
## components/lockon_target.gd exposes for exactly this — a creature that should not be
## lockable right now without being freed.
func _set_dummies_targetable(on: bool) -> void:
	for node in _p.get_tree().get_nodes_in_group("target_dummy"):
		var marker := node.get_node_or_null("LockOnTarget") as LockOnTarget
		if marker != null:
			marker.targetable = on


## Acquire range, break range and the hysteresis between them, by moving a real target
## out along the player's facing until each one fails. Measured rather than read off the
## exports, because the sphere that finds candidates is sized from `break_range` and a
## mismatch between the two would show up here and nowhere else.
func _measure_lock_ranges(lock: Node) -> void:
	await _reset_lockon()
	var target := _spawn_lock_target(6.0, 0.0, 1.05)
	var marker: Node3D = target.get_node("LockOnTarget")
	var facing := _facing()
	var acquired := -1.0
	var distance := 6.0
	while distance <= 20.0:
		target.global_position = _p.player().global_position + facing * distance + Vector3.UP * 1.05
		await _p.frames(4)
		if await _press_target(lock):
			acquired = distance
			lock.call("release")
		distance += 0.5
	_p.add("lockon_acquire_range", acquired, "m",
		"furthest a lock can be TAKEN, stepped in 0.5 m. REFERENCE.md band 8-14 m")

	# Now hold a lock and walk the target away until it breaks.
	target.global_position = _p.player().global_position + facing * 8.0 + Vector3.UP * 1.05
	await _p.frames(6)
	var broke := -1.0
	if await _press_target(lock):
		distance = 8.0
		while distance <= 22.0:
			target.global_position = (_p.player().global_position + facing * distance
				+ Vector3.UP * 1.05)
			await _p.frames(3)
			if not bool(lock.call("is_locked")):
				broke = distance
				break
			distance += 0.25
	_p.add("lockon_break_range", broke, "m", "distance at which a HELD lock lets go")
	_p.add("lockon_hysteresis", broke - acquired if broke > 0.0 and acquired > 0.0 else -1.0,
		"m", "break minus acquire. REFERENCE.md band 1.5-3 m; equal values flicker")
	target.queue_free()
	await _p.frames(4)
	_p.release_all()


## The framing, and the census REFERENCE.md calls non-negotiable.
func _measure_lock_framing(lock: Node) -> void:
	await _reset_lockon()
	# Off to one side, so the camera has a real distance to travel and the settle is
	# something other than zero.
	var target := _spawn_lock_target(7.5, 4.5, 1.05)
	var second := _spawn_lock_target(8.5, -3.0, 1.05)
	await _p.frames(8)
	if not await _press_target(lock):
		_p.add("lockon_camera_settle", -1.0, "ms", "never acquired")
		target.queue_free()
		second.queue_free()
		return

	# 90% settle: the frame the residual screen-space error has fallen to a tenth of
	# what it was on the frame the lock was taken. A defined figure rather than an
	# eyeballed one — for `1 - exp(-rate*delta)` it is ln(10)/rate, so it is also the
	# number `lockon_camera_speed` is tuned against.
	var goal := _framing_goal()
	var first := _camera().unproject_position(lock.call("target_point")).distance_to(goal)
	var settled: int = await _p.frames_until(func() -> bool:
		return _camera().unproject_position(lock.call("target_point")).distance_to(goal) \
			<= first * 0.1, 120)
	_p.add("lockon_camera_settle", _p.ms(settled), "ms",
		"acquire to the target being within a tenth of its initial error of"
		+ " (½ width, ¼ height). REFERENCE.md band 250-400 ms")
	var at := _camera().unproject_position(lock.call("target_point"))
	_p.add("lockon_target_frame_x", at.x / _frame().x, "fraction",
		"where the target settles across frame — 0.5 is centred")
	_p.add("lockon_target_frame_y", at.y / _frame().y, "fraction",
		"and down frame. 0.25 is the framing the pitch solve aims for")
	_p.add("lockon_player_frame_y",
		_camera().unproject_position(_p.player().global_position + Vector3.UP * 1.1).y
			/ _frame().y, "fraction",
		"the player's chest. Below the target, with the fight volume between them")

	# The census. Strafe both ways, close, retreat, swing twice, switch target.
	_census_reset()
	await _census(20)
	Input.action_press("move_right")
	await _census(45)
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _census(70)
	Input.action_release("move_left")
	Input.action_press("move_forward")
	await _census(25)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await _census(35)
	Input.action_release("move_back")
	for _swing in 2:
		Input.action_press("attack")
		await _census(2)
		Input.action_release("attack")
		await _census(40)
	# Snapshot before the switch section. REFERENCE.md's "target within the centre 40% of
	# frame" is a claim about STRAFING; a switch deliberately throws the lock at
	# something up to 50 degrees away, and the frames while the camera catches up would
	# otherwise be scored against a band that was never about them.
	var strafe_offcentre := _census_offcentre
	Input.action_press("cam_right")
	await _census(25)
	Input.action_release("cam_right")
	await _census(20)
	_p.add("lockon_locked_frames", float(_census_total), "frames",
		"frames of the census that were actually locked")
	_p.add("lockon_both_on_screen_pct",
		100.0 * float(_census_ok) / maxf(float(_census_total), 1.0), "%",
		"frames where the target's aim point AND the player's feet, chest and head were"
		+ " all inside the frame. REFERENCE.md: 100, non-negotiable")
	_p.add("lockon_screen_margin_min", _census_margin, "px",
		"closest any of those four points came to a frame edge, at 1280x720. Negative"
		+ " means something left the frame")
	_p.add("lockon_target_offcentre_strafing", strafe_offcentre, "fraction",
		"worst horizontal offset of the target from the centre while strafing, closing,"
		+ " retreating and swinging. REFERENCE.md asks for the centre 40% of frame, i.e."
		+ " under 0.2")
	_p.add("lockon_target_offcentre_max", _census_offcentre, "fraction",
		"and including the frames just after a target switch, which is the transient the"
		+ " band above is not about")

	# Strafing has to ORBIT: input is rotated into target space, so holding sideways
	# should sweep an arc at a roughly constant radius rather than sliding away.
	await _reset_lockon()
	target.global_position = _p.player().global_position + _facing() * 6.0 + Vector3.UP * 1.05
	second.global_position = _p.player().global_position + _facing() * 30.0
	await _p.frames(8)
	if await _press_target(lock):
		var pivot: Vector3 = lock.call("target_point")
		var before := _flat_to(pivot)
		Input.action_press("move_right")
		await _p.frames(45)
		Input.action_release("move_right")
		var after := _flat_to(pivot)
		_p.add("lockon_strafe_radius_drift", absf(after.length() - before.length()), "m",
			"change in distance to the target after 45 frames of holding sideways —"
			+ " small means the input was rotated into target space, not camera space")
		_p.add("lockon_strafe_arc", rad_to_deg(before.angle_to(after)), "deg",
			"and how far round the target that carried us")
	target.queue_free()
	second.queue_free()
	await _p.frames(4)
	_p.release_all()


## The two ways a lock ends other than by choice: the target hides, and the target dies.
func _measure_lock_breaks(lock: Node) -> void:
	await _reset_lockon()
	var target := _spawn_lock_target(7.0, 0.0, 1.05)
	await _p.frames(8)
	if not await _press_target(lock):
		_p.add("lockon_los_grace", -1.0, "ms", "never acquired")
		target.queue_free()
		return
	# A wall on the world layer, dropped across the sight-line from the CAMERA — which
	# is where the check is made from, and not from the player.
	var eye := _camera().global_position
	var aim: Vector3 = lock.call("target_point")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	_p.level().add_child(wall)
	wall.global_position = eye.lerp(aim, 0.5)
	wall.look_at(aim, Vector3.UP)
	var broke: int = await _p.frames_until(
		func() -> bool: return not bool(lock.call("is_locked")), 120)
	_p.add("lockon_los_grace", _p.ms(broke), "ms",
		"target hidden from the camera to the lock letting go. REFERENCE.md band"
		+ " 200-500 ms — instant means you cannot walk behind your own scenery")
	wall.queue_free()
	# The first target goes too, and before the second one arrives rather than after:
	# two markers at 6 and 7 m dead ahead are within a few pixels of each other in
	# screen space, so which one got locked would be a coin toss.
	target.queue_free()
	await _p.frames(10)

	var lethal := _spawn_lock_target(6.0, 0.0, 1.05)
	await _p.frames(8)
	var released := -1
	if await _press_target(lock):
		var health: Node = lethal.get_node("Health")
		health.call("kill")
		released = await _p.frames_until(
			func() -> bool: return not bool(lock.call("is_locked")), 30)
	_p.add("lockon_release_on_death", _p.ms(released), "ms",
		"health to zero to the lock letting go, through LockOnTarget's own `lost`"
		+ " signal — nothing has to remember to unregister a corpse")
	lethal.queue_free()
	await _p.frames(4)
	_p.release_all()


## Attack facing: the prop-occlusion answer, measured. God of War 2018 rotates every
## attack to the target when there is one; this is that, and the unlocked figure beside
## it is what it replaces.
func _measure_attack_facing(lock: Node) -> void:
	await _reset_lockon()
	# 45 degrees to the character's LEFT, and the side is measured rather than chosen:
	# from the spawn, the sight-line to the same bearing on the right runs straight
	# through House3's collision body at (7.97, 1.50, 7.49), so the lock correctly
	# refuses it. An earlier version of this measurement scored 0 degrees anyway,
	# because a level dummy 11.8 m away satisfied the press instead and the character
	# dutifully turned to face THAT.
	var target := _spawn_lock_target(6.0, -6.0, 1.05)
	await _p.frames(8)
	_p.add("lockon_target_bearing",
		rad_to_deg(_facing().angle_to(_flat_to(target.global_position).normalized())),
		"deg", "how far off the character's facing the target is before the swing")

	# Unlocked control: no stick input, so the swing goes wherever the body already
	# pointed — which is the behaviour this change replaces. Measured on the live frame
	# in both cases, because the lunge moves the character and therefore the bearing.
	Input.action_press("attack")
	await _p.frames(2)
	Input.action_release("attack")
	await _p.frames_until(func() -> bool: return _p.player().is_attack_hitbox_active(), 40)
	_p.add("attack_faces_ahead_unlocked",
		rad_to_deg(_facing().angle_to(_flat_to(target.global_position).normalized())),
		"deg", "unlocked, a swing with no stick input keeps the facing it had, so the arc"
		+ " misses the target by the whole bearing")
	await _p.frames(40)

	await _reset_lockon()
	target.global_position = _p.player().global_position + _facing() * 6.0 \
		- _right() * 6.0 + Vector3.UP * 1.05
	await _p.frames(8)
	var facing_error := -1.0
	if await _press_target(lock):
		Input.action_press("attack")
		await _p.frames(2)
		Input.action_release("attack")
		await _p.frames_until(func() -> bool: return _p.player().is_attack_hitbox_active(), 40)
		facing_error = rad_to_deg(
			_facing().angle_to(_flat_to(lock.call("target_point")).normalized()))
		await _p.frames(40)
	_p.add("attack_faces_target", facing_error, "deg",
		"locked, the swing is rotated onto the target on the frame it is committed."
		+ " Near zero; the camera is looking down the same line, so the arc is presented"
		+ " the same way every time instead of wherever the stick happened to point")
	target.queue_free()
	await _p.frames(4)
	_p.release_all()


## Does turning to the target actually get the arc off a prop?
##
## THE CRITIC'S OWN CASE DOES NOT REPRODUCE, and that is worth stating before the
## measurement that replaces it. `Sign_village` stands 1.005 m behind the spawn, which
## is as squarely between camera and blade as this level gets, and at the live frame of
## a slash its screen-space box is 102 x 142 px spanning y 388-530 while the blade
## sweeps y 272-356 — no overlap at all. Two physics answers were worse than useless
## first: a ray masked to world geometry reported every blade sample clear, because
## signs are `Interactable` Area3Ds on layer 3 and a world-masked ray cannot see them;
## adding layer 3 reported every sample BLOCKED in both cases, because an
## Interactable's shape is a 2.6 m interaction trigger the player is standing inside.
##
## So the case is CONSTRUCTED, once, from the unlocked geometry: a post-sized box is
## placed on the sight-line between the eye and the middle of the blade at the live
## frame, which is the worst case for the unlocked swing by definition. The number that
## means anything is the second one — the same object, unmoved, measured against a
## locked swing. It has no collision, so it cannot break the lock's sight-line or
## shorten the spring arm and thereby flatter its own result.
func _measure_prop_occlusion(lock: Node) -> void:
	await _reset_lockon()
	Input.action_press("attack")
	await _p.frames(2)
	Input.action_release("attack")
	await _p.frames_until(func() -> bool: return _p.player().is_attack_hitbox_active(), 40)
	var prop := _place_prop_over_blade()
	_p.add("prop_over_arc_unlocked", _blade_over_prop(prop), "fraction",
		"of nine points along the blade, how many land inside a signpost-sized prop"
		+ " placed on the sight-line by construction. ~1 by design; it is the baseline")
	await _p.frames(40)

	await _reset_lockon()
	# 40 degrees, and to the character's LEFT: to the right the sight-line runs through
	# a village house, which correctly refuses the lock.
	var target := _spawn_lock_target(6.0, -5.03, 1.05)
	await _p.frames(8)
	var locked_overlap := -1.0
	if await _press_target(lock):
		await _p.frames(45)   # let the camera finish swinging onto the target
		Input.action_press("attack")
		await _p.frames(2)
		Input.action_release("attack")
		await _p.frames_until(func() -> bool: return _p.player().is_attack_hitbox_active(), 40)
		locked_overlap = _blade_over_prop(prop)
		await _p.frames(40)
	_p.add("prop_over_arc_locked", locked_overlap, "fraction",
		"the same prop against a swing with a target 40 degrees away: the character turns"
		+ " to it and the camera turns with it, so the arc is no longer drawn over it")
	prop.queue_free()
	target.queue_free()
	await _p.frames(4)
	_p.release_all()


## A signpost-sized visual obstacle, dropped on the line from the camera eye to the
## middle of the blade as it is RIGHT NOW. No collision body: it must not be able to
## break the lock's sight-line or shorten the spring arm, or it would improve the locked
## number by moving the camera rather than by moving the arc.
func _place_prop_over_blade() -> Node3D:
	var loadout := _p.player().get_node("Loadout") as Loadout
	var base := loadout.part(&"BladeBase") as Node3D
	var tip := loadout.part(&"BladeTip") as Node3D
	var middle := base.global_position.lerp(tip.global_position, 0.5)
	var eye := _camera().global_position

	var prop := MeshInstance3D.new()
	prop.name = "ProbeProp"
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 2.2, 0.34)
	prop.mesh = box
	_p.level().add_child(prop)
	prop.global_position = eye.lerp(middle, 0.6)
	return prop


## The over-the-shoulder aim camera, and the one number it exists for: how much of the
## draw is foreshortened. `bow_draw_axis_deg` is the angle between the direction the
## arrow will leave in and the direction the camera looks at the bow from — 0 means the
## draw happens entirely along the view axis, which is the measured reason a bow draw
## cannot be made legible from a camera sitting directly behind the character.
func _measure_aim_camera() -> void:
	await _reset_lockon()
	var loadout := _p.player().get_node("Loadout") as Loadout
	await _p.equip(loadout, ITEM_BOW)
	await _p.frames(6)
	var camera := _camera()

	Input.action_press("attack")
	await _p.frames_until(
		func() -> bool: return String(_p.player().get_anim_state()) == "bow_draw", 60)

	# A/B WITH THE CAMERA AS THE ONLY VARIABLE. `camera_shoulder` is a plain var that
	# PlayerAimState writes once on enter, so overwriting it here holds the same full
	# draw, the same weapon and the same pose in front of the OLD centred-behind rig
	# for as long as it takes to measure — which is the honest control. Pairing a
	# drawn-and-aimed frame against an idle one would be measuring two changes.
	var pull: float = (_p.player().get_node("StateMachine/Aim") as PlayerAimState).nock_pull
	_p.player().set("camera_shoulder", 0.0)
	await _p.frames(60)
	_p.add("bow_nock_travel_px_default", _nock_travel_px(pull), "px",
		("how far across the screen the nocked arrow moves over a full %.2f m draw, from"
		+ " the walking camera. This is the cue that carries the draw's PROGRESS, and it"
		+ " is the one the view axis destroys") % pull)
	_p.add("bow_draw_axis_deg_default", _draw_axis_angle(), "deg",
		"full draw, camera centred behind as it is for walking: the angle between the"
		+ " direction the arrow leaves in and the direction the camera sees the bow"
		+ " from. Near zero means the whole draw happens along the view axis, which is"
		+ " the measured reason a bow draw could not be made legible from that camera")
	var span_before := _weapon_screen_span(loadout)
	_p.player().set("camera_shoulder", 1.0)
	await _p.frames(60)
	_p.add("bow_nock_travel_px_aimed", _nock_travel_px(pull), "px",
		"and from the shoulder rig. The whole point of the camera change")
	_p.add("bow_draw_axis_deg_aimed", _draw_axis_angle(), "deg",
		"the same frame of the same draw with the shoulder rig settled. Bigger is"
		+ " better: it is the angle the retraction, the string and the nocked arrow are"
		+ " finally seen across")
	_p.add("aim_camera_distance", camera.global_position.distance_to(
		_p.player().global_position + Vector3.UP * 1.1), "m",
		"eye to chest while aiming, against 5.9 m walking around")
	var lateral := _right().dot(camera.global_position - _p.player().global_position)
	_p.add("aim_camera_lateral", lateral, "m",
		"how far the eye sits to the character's right. Positive means over the RIGHT"
		+ " shoulder, which is the side the grip hangs off")
	_p.add("aim_camera_fov", camera.fov, "deg", "narrowed from 70 to frame the shot")
	var span := _weapon_screen_span(loadout)
	_p.add("bow_screen_width", span.x, "px",
		"the bow's own meshes, unprojected, at 1280x720 — multiply by 0.667 for the"
		+ " 640x480 capture size CLAUDE.md's 53 x 108 px figure was measured at")
	_p.add("bow_screen_height", span.y, "px", "and its height")
	_p.add("bow_screen_growth", span.length() / maxf(span_before.length(), 0.01), "x",
		"how much bigger the bow is on screen once the aim camera has settled")
	Input.action_release("attack")
	await _p.frames(40)
	await _p.equip(loadout, ITEM_SWORD)
	_p.release_all()


# --- Lock-on helpers ------------------------------------------------------

var _census_total := 0
var _census_ok := 0
var _census_margin := INF
var _census_offcentre := 0.0


func _lockon() -> Node:
	return _p.player().get_node_or_null("LockOn")


func _camera() -> Camera3D:
	return _p.player().get_node("CameraPivot/SpringArm3D/Camera3D") as Camera3D


## The viewport the camera unprojects against. `get_visible_rect()`, NOT `size`:
## headless reports a 64x64 window, while the root viewport — and therefore every
## unprojection — is the project's 1280x720. Reading `size` here would have made every
## screen-space measurement in this suite silently wrong by a factor of 20.
func _frame() -> Vector2:
	return Vector2(_camera().get_viewport().get_visible_rect().size)


func _framing_goal() -> Vector2:
	var frame := _frame()
	var wanted: float = _p.player().lockon_target_screen_height
	return Vector2(frame.x * 0.5, frame.y * wanted)


## Press and release the target button, and report whether a lock is held afterwards.
func _press_target(lock: Node) -> bool:
	Input.action_press("target")
	await _p.get_tree().physics_frame
	Input.action_release("target")
	await _p.get_tree().physics_frame
	return bool(lock.call("is_locked"))


func _measure_switch(lock: Node, first: Node) -> int:
	Input.action_press("cam_right")
	var frames: int = await _p.frames_until(func() -> bool: return lock.get("target") != first, 60)
	Input.action_release("cam_right")
	return frames


## The character's flat facing. The rig's forward is +basis.z at yaw 0, the same
## convention every other facing calculation in this project uses.
func _facing() -> Vector3:
	var rig: Node3D = _p.player().get_node("Rig")
	var facing := rig.global_basis.z
	facing.y = 0.0
	return facing.normalized()


func _right() -> Vector3:
	var facing := _facing()
	return Vector3(-facing.z, 0.0, facing.x)


func _flat_to(point: Vector3) -> Vector3:
	var to: Vector3 = point - _p.player().global_position
	to.y = 0.0
	return to


## How far a world point sits inside the frame, in pixels — the smallest distance to any
## edge. Negative means outside; a point behind the camera is reported as far outside,
## because `unproject_position` mirrors it to a confident-looking position on the wrong
## side of the screen.
func _screen_margin(point: Vector3) -> float:
	var camera := _camera()
	if camera.is_position_behind(point):
		return -9999.0
	var at := camera.unproject_position(point)
	var frame := _frame()
	return minf(minf(at.x, at.y), minf(frame.x - at.x, frame.y - at.y))


func _census_reset() -> void:
	_census_total = 0
	_census_ok = 0
	_census_margin = INF
	_census_offcentre = 0.0


## Advance `count` frames, checking every locked one against the on-screen contract.
func _census(count: int) -> void:
	var lock: Node = _lockon()
	for _i in count:
		await _p.get_tree().physics_frame
		if not bool(lock.call("is_locked")):
			continue
		_census_total += 1
		var aim: Vector3 = lock.call("target_point")
		var points: Array[Vector3] = [
			aim,
			_p.player().global_position + Vector3.UP * 0.05,
			_p.player().global_position + Vector3.UP * 1.1,
			_p.player().global_position + Vector3.UP * 2.1,
		]
		var worst := INF
		for point in points:
			worst = minf(worst, _screen_margin(point))
		_census_margin = minf(_census_margin, worst)
		if worst >= 0.0:
			_census_ok += 1
		var frame := _frame()
		_census_offcentre = maxf(_census_offcentre,
			absf(_camera().unproject_position(aim).x - frame.x * 0.5) / frame.x)


## Fraction of nine points along the held blade that land inside a prop's screen-space
## bounding box. The visible mesh, not the prop's collision volume — see the write-up at
## `_measure_prop_occlusion` for why the physics answer was worthless twice over.
func _blade_over_prop(prop: Node3D) -> float:
	var loadout := _p.player().get_node("Loadout") as Loadout
	var base := loadout.part(&"BladeBase") as Node3D
	var tip := loadout.part(&"BladeTip") as Node3D
	if base == null or tip == null or prop == null:
		return -1.0
	var box := _screen_box(prop)
	if box.size == Vector2.ZERO:
		return -1.0
	var camera := _camera()
	var over := 0
	for i in 9:
		var point := base.global_position.lerp(tip.global_position, float(i) / 8.0)
		if camera.is_position_behind(point):
			continue
		if box.has_point(camera.unproject_position(point)):
			over += 1
	return float(over) / 9.0


## Screen-space bounding box of `root` and every visible mesh under it, in pixels.
##
## The root itself counts, and that is not a flourish: `find_children` searches
## descendants only, so a bare `MeshInstance3D` handed to an earlier version of this
## found nothing, returned an empty box, and reported -1 for both halves of the
## prop-occlusion comparison.
func _screen_box(root: Node3D) -> Rect2:
	var camera := _camera()
	var low := Vector2.INF
	var high := -Vector2.INF
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.visible:
			continue
		var aabb := mesh.get_aabb()
		for corner in 8:
			var world := mesh.global_transform * aabb.get_endpoint(corner)
			if camera.is_position_behind(world):
				continue
			var at := camera.unproject_position(world)
			low = Vector2(minf(low.x, at.x), minf(low.y, at.y))
			high = Vector2(maxf(high.x, at.x), maxf(high.y, at.y))
	if low.x > high.x:
		return Rect2()
	return Rect2(low, high - low)


## Angle between the direction a shot will leave in and the direction the camera sees
## the bow from. Small means the draw is foreshortened into nothing.
func _draw_axis_angle() -> float:
	var loadout := _p.player().get_node("Loadout") as Loadout
	var spawn := loadout.part(&"ArrowSpawn") as Node3D
	var muzzle: Vector3 = spawn.global_position if spawn != null \
		else _p.player().global_position + Vector3.UP * 1.2
	var view: Vector3 = muzzle - _camera().global_position
	if view.length_squared() < 0.0001:
		return -1.0
	return rad_to_deg(_facing().angle_to(view))


## Screen-space span of every mesh in the equipped weapon, in pixels. The honest measure
## of "can you see what I am holding", and directly comparable to the 38 x 103 and
## 53 x 108 px figures CLAUDE.md records for the bow at the default camera.
func _weapon_screen_span(loadout: Loadout) -> Vector2:
	var weapon := loadout.instance() as Node3D
	if weapon == null:
		return Vector2.ZERO
	return _screen_box(weapon).size


## How far across the screen the nocked arrow travels over a full draw, in pixels. THE
## payoff number for the aim camera: the retraction is the cue that carries the draw's
## progress, and from a camera directly behind the character it happens along the view
## axis and therefore covers no pixels at all.
func _nock_travel_px(pull: float) -> float:
	var loadout := _p.player().get_node("Loadout") as Loadout
	var spawn := loadout.part(&"ArrowSpawn") as Node3D
	if spawn == null:
		return -1.0
	var camera := _camera()
	var nocked := spawn.global_position
	var drawn := nocked - _facing() * pull
	if camera.is_position_behind(nocked) or camera.is_position_behind(drawn):
		return -1.0
	return camera.unproject_position(nocked).distance_to(camera.unproject_position(drawn))


## `_reset`, plus everything a lock-on measurement needs to be repeatable: no lock, the
## character facing away from the camera, the camera behind it at its authored pitch, and
## the aim rig off. Without this each section inherits wherever the previous one left the
## camera, and a screen-space measurement taken from an inherited angle is a fiction.
func _reset_lockon(yaw_deg: float = 0.0) -> void:
	var lock: Node = _lockon()
	if lock != null:
		lock.call("release")
	_p.player().set("camera_shoulder", 0.0)
	await _p.reset()
	var pivot: Node3D = _p.player().get_node("CameraPivot")
	var arm: SpringArm3D = _p.player().get_node("CameraPivot/SpringArm3D")
	pivot.rotation.y = deg_to_rad(yaw_deg)
	arm.rotation.x = deg_to_rad(-20.0)
	arm.spring_length = 5.5
	# The character faces away from the camera, which is the pivot's yaw plus half a turn.
	(_p.player().get_node("Rig") as Node3D).rotation.y = deg_to_rad(yaw_deg) + PI
	await _p.frames(30)


## A stand-in creature: `Health`, a `HurtBox3D` on the enemy layer and a `LockOnTarget`,
## built in code so this suite does not depend on the dummy scene another builder owns —
## the same reason `_spawn_target` exists. Placed `ahead` metres along the player's
## facing and `side` metres to its right.
func _spawn_lock_target(ahead: float, side: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ProbeLockTarget"

	var health := Health.new()
	health.name = "Health"
	health.max = 9
	health.current = 9
	root.add_child(health)

	var marker := LockOnTarget.new()
	marker.name = "LockOnTarget"
	marker.health = health
	root.add_child(marker)

	var hurt := BasicHurtBox3D.new()
	hurt.name = "HurtBox"
	hurt.health = health
	hurt.collision_layer = 32
	hurt.collision_mask = 0
	hurt.monitoring = false
	hurt.monitorable = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	hurt.add_child(shape)
	root.add_child(hurt)

	_p.level().add_child(root)
	root.global_position = (_p.player().global_position + _facing() * ahead
		+ _right() * side + Vector3.UP * height)
	return root
