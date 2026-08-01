extends Node
## Windowed screenshot harness. Godot headless has no renderer at all, so there
## is no headless screenshot — a real window is mandatory.
##
##     GODOT="C:/tools/godot/Godot_v4.7.1-stable_win64_console.exe"
##     "$GODOT" --path . res://tools/capture.tscn -- --shots=clearing
##
## Two things this exists to get right:
##
## 1. `player.gd:89` captures the mouse on boot, so a windowed run hands the real
##    cursor to the camera and quietly rotates it mid-capture. This releases the
##    mouse every frame, and `player.gd:112` only reads motion while captured, so
##    that fully neutralises it.
## 2. The window is forced to 640x480. That is 4:3 to match the reference frames
##    the critic compares against — a 16:9 capture beside a 4:3 one is a tell, and
##    it changes the composition being judged. Camera3D defaults to KEEP_HEIGHT,
##    so vertical FOV is preserved and the horizontal narrows, which is the
##    correct way round.

const LEVEL := "res://world/rooms/greenhollow_clearing.tscn"
const SHOT_DIR := "res://tools/shots/%s.json"
const CAPTURE_SIZE := Vector2i(640, 480)

var _level: Node = null
var _player: Node3D = null
var _pivot: Node3D = null
var _arm: SpringArm3D = null
var _camera: Camera3D = null
var _default_fov := 0.0
var _default_arm_mask := 0
var _out_dir := ""
var _written: Array = []
## Shots whose actual state did not match what the shot list claimed. Any entry
## here fails the run — see _check_expectations().
var _failures: Array = []
## The camera as player.tscn ships it. A shot that omits a camera key gets these
## back, rather than inheriting whatever the previous shot set — which is what
## makes "shoot this from the real gameplay camera" expressible as an ABSENCE of
## overrides instead of a set of numbers that have to be kept in sync by hand.
var _default_pitch := 0.0
var _default_spring := 0.0
## Every node a shot's `hide_effects` switches off. Resolved once, restored after
## each shot, so one hidden shot cannot leak into the next.
var _effect_nodes: Array[Node3D] = []


func _ready() -> void:
	var shots_name := _arg("shots", "clearing")
	_out_dir = _arg("out", ProjectSettings.globalize_path("res://tools/out/%s" % shots_name))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_mark_ignored(ProjectSettings.globalize_path("res://tools/out"))

	var shots := _load_shots(shots_name)
	if shots.is_empty():
		printerr("capture: no shots in %s" % (SHOT_DIR % shots_name))
		get_tree().quit(1)
		return

	DisplayServer.window_set_size(CAPTURE_SIZE)
	get_window().content_scale_size = CAPTURE_SIZE

	_level = load(LEVEL).instantiate()
	add_child(_level)
	await get_tree().process_frame

	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		printerr("capture: no node in group 'player' after loading %s" % LEVEL)
		get_tree().quit(1)
		return
	_pivot = _player.get_node_or_null("CameraPivot") as Node3D
	_arm = _player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	_camera = _player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if _camera != null and _player.get("camera_fov") != null:
		_default_fov = float(_player.get("camera_fov"))
	if _arm != null:
		_default_arm_mask = _arm.collision_mask
	if not _player_is_intact():
		get_tree().quit(1)
		return
	_freeze_pickups()
	_collect_effects()
	if _arm != null:
		_default_pitch = _arm.rotation.x
		_default_spring = _arm.spring_length
		print("capture: gameplay camera defaults — pitch %.1f deg, spring %.2f m"
			% [rad_to_deg(_default_pitch), _default_spring])

	for shot in shots:
		await _run_shot(shot)

	_write_manifest(shots_name)
	_release_all()
	remove_child(_level)
	_level.free()
	await get_tree().process_frame

	if not _failures.is_empty():
		printerr("capture: %d shot(s) were not in the state the shot list claimed:"
			% _failures.size())
		for line in _failures:
			printerr("  %s" % line)
		printerr("capture: the PNGs were still written, but do NOT judge them —"
			+ " a mislabelled frame scores the animation for something it was not doing.")
		get_tree().quit(1)
		return
	get_tree().quit(0)


func _process(_delta: float) -> void:
	# Every frame, not once: the pause menu and the player both touch mouse_mode,
	# and one captured frame is enough to ruin a shot.
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- One shot -------------------------------------------------------------

func _run_shot(shot: Dictionary) -> void:
	var name := String(shot.get("name", "unnamed"))
	_release_all()

	# Place the player, if the shot asks for a specific spot.
	if shot.has("player_position"):
		var p: Array = shot["player_position"]
		_player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		_player.set("velocity", Vector3.ZERO)

	# Let gravity settle the capsule and the lagged camera pivot catch up before
	# the camera angle is set, or the pivot chase drags the framing off.
	await _frames(int(shot.get("warmup_frames", 45)))

	# Bleed off anything the PREVIOUS shot left behind. Zeroing velocity before the
	# warmup is not enough: a shot that ended mid-slash leaves the attack's forward
	# drive still being applied, so the player accelerates during warmup and arrives
	# in Move with the walk cycle playing. That produced four "idle" frames of a
	# walking character, and it only became visible once expectations were asserted.
	# No shot here depends on carried momentum, so re-zeroing is always correct.
	if shot.has("player_position"):
		var p2: Array = shot["player_position"]
		_player.global_position = Vector3(float(p2[0]), float(p2[1]), float(p2[2]))
		_player.set("velocity", Vector3.ZERO)
		await _frames(8)

	if _pivot != null:
		_pivot.rotation.y = deg_to_rad(float(shot.get("camera_yaw_deg", 0.0)))
	if _arm != null:
		_arm.rotation.x = (deg_to_rad(float(shot["camera_pitch_deg"]))
			if shot.has("camera_pitch_deg") else _default_pitch)
		_arm.spring_length = (float(shot["camera_distance"])
			if shot.has("camera_distance") else _default_spring)

	# Two things defeated the first version of `lock_camera`, and a critic proved it by
	# template-matching static props between paired frames: 5 of 7 pairs were offset,
	# one by 11 px across and 21 px down, and in one the camera was visibly CLOSER.
	# Neither cause was the pivot.
	#
	#  - The SpringArm SHORTENS on collision, so an action that carries the character
	#    into a bush pulls the camera in. Masking it to 0 fixes the distance.
	#  - player.gd widens the FOV with speed (camera_fov_kick), and an attack drives
	#    the character forward, so an action frame is genuinely zoomed relative to its
	#    idle twin.
	#
	# Both are correct in play and fatal to a comparison. Set here rather than just
	# before the frame, so the arm has ticks to settle before anything is captured.
	if bool(shot.get("lock_camera", false)):
		if _arm != null:
			_arm.collision_mask = 0
		if _camera != null and _default_fov > 0.0:
			_camera.fov = _default_fov

	# Walk the input timeline frame by frame.
	#
	# `capture_at` is a fixed frame number, which is hand-tuned arithmetic: the
	# numbers were fitted to a measured three-frame input latency, and adding an
	# eight-frame settle above silently shifted every action shot off its window.
	# Frame numbers are the wrong contract for "catch the blade mid-swing".
	#
	# So `capture_when` is preferred: advance until the player actually reaches the
	# named clip/state (plus an optional `capture_offset`), and capture there. The
	# shot then says what it wants rather than when it thinks it happens, and stays
	# correct when timing changes. `capture_at` still works, and acts as the
	# fallback and the timeout.
	var timeline: Array = shot.get("inputs", [])
	var capture_at := int(shot.get("capture_at", 1))
	var when: Dictionary = shot.get("capture_when", {})
	var limit := int(shot.get("timeout_frames", 240)) if not when.is_empty() else capture_at
	var offset := int(shot.get("capture_offset", 0))
	var matched := when.is_empty()
	var frame := 0

	while frame < limit:
		frame += 1
		for entry_v in timeline:
			var entry: Dictionary = entry_v
			var action := String(entry.get("action", ""))
			if not InputMap.has_action(action):
				continue
			if int(entry.get("press_at", -1)) == frame:
				Input.action_press(action)
			if int(entry.get("release_at", -1)) == frame:
				Input.action_release(action)
		await get_tree().physics_frame

		if not matched and _matches(when):
			matched = true
			if offset > 0:
				await _frames(offset)
			break
		if matched and frame >= capture_at:
			break

	if not matched:
		_failures.append("%s: never reached %s within %d frames" % [name, when, limit])

	# Immediately before the frame is taken, not after warmup: the action itself is
	# what moves the camera, so locking any earlier does not help.
	_lock_camera(shot)
	var hidden := _hide_effects(shot)
	# PAUSE before the draw. `_save` awaits frame_post_draw, and a physics tick landing
	# in between lets _update_camera lerp the pivot straight back off its mark — which
	# is why locking the pivot alone was not enough. Rendering continues while the tree
	# is paused, so the frame still draws.
	var locked := bool(shot.get("lock_camera", false))
	if locked:
		get_tree().paused = true
	await _save(name)
	if locked:
		get_tree().paused = false
	for node in hidden:
		node.visible = true
		node.process_mode = Node.PROCESS_MODE_INHERIT
	_check_expectations(shot, name)
	# Restore, so a locked shot cannot leak a disabled spring arm into the next one.
	if _arm != null:
		_arm.collision_mask = _default_arm_mask
	_release_all()


func _save(name: String) -> void:
	# frame_post_draw is the only point at which the viewport texture holds a
	# complete frame. Reading it earlier gives a blank or half-drawn image.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	var err := image.save_png(path)
	if err != OK:
		printerr("capture: could not write %s (error %d)" % [path, err])
		return
	# What the player was actually doing. Without this a shot list is a set of frame
	# numbers arrived at by guesswork — "capture_at 37 is slash_b's follow-through"
	# was wrong by a whole clip, and the only way to tell from the PNG was that the
	# pose looked wrong.
	var state := _player_state()
	_written.append({
		"name": name, "path": path,
		"size": [image.get_width(), image.get_height()],
		"state": state,
	})
	print("capture: wrote %s (%dx%d) %s" % [path, image.get_width(), image.get_height(), state])


## Refuse to run if the character is not actually there.
##
## A null check on the player node is not enough, and this cost a real conclusion.
## While a refactor left `player.tscn` pointing at scripts that did not exist, the
## Player node still entered the tree and still group-registered — so the harness
## happily wrote fourteen frames, complete with a `state=` readout, of a level with
## no visible character in it. A measurement taken from those frames produced the
## OPPOSITE of the truth and was acted on before being caught.
##
## Believable output from a broken scene is worse than a crash, so this asserts
## there is renderable geometry with real extent, not merely a node.
func _player_is_intact() -> bool:
	var meshes := 0
	var extent := AABB()
	for node in _player.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		# Skip anything under the camera rig. The outline pass rides a fullscreen quad
		# parented to the Camera3D with a huge extra_cull_margin, and counting it put
		# this character's reported height at 4.07 m. A guard that prints a wrong
		# number is the kind of thing this guard exists to catch.
		if _pivot != null and _pivot.is_ancestor_of(mi):
			continue
		meshes += 1
		var box := mi.get_aabb()
		box.position += mi.global_position - _player.global_position
		extent = box if meshes == 1 else extent.merge(box)

	# 0.5 m is generous: the character stands 2.2 m and even a lone limb clears it.
	# The failure being guarded against produced zero meshes, not a small one.
	if meshes == 0 or extent.get_longest_axis_size() < 0.5:
		printerr("capture: the player has %d visible mesh(es) spanning %.2f m —"
			% [meshes, extent.get_longest_axis_size()]
			+ " it is broken or failed to instantiate. Refusing to write frames,"
			+ " because plausible frames of an absent character are worse than none.")
		return false
	print("capture: player intact — %d visible mesh(es), %.2f m tall"
		% [meshes, extent.size.y])
	return true


## Stop pickups from triggering, without hiding them.
##
## Shots teleport the player around the level, and anything they land on gets
## collected — so a rupee present in one frame of a matched pair was gone by the
## other. A blind critic caught it: "the green gem pickups differ, four versus
## two. Something was collected or despawned between takes." That is fatal to a
## forced-choice test whose entire premise is that the action is the only variable.
##
## `monitoring = false` rather than freeing or hiding them: they must still be in
## frame, because the clutter is part of what an effect has to read against.
func _freeze_pickups() -> void:
	var frozen := 0
	for node in _level.find_children("*", "Area3D", true, false):
		var area := node as Area3D
		# Leave the player's own areas alone — that is where the sword hitbox and
		# the interact field live, and disabling those changes behaviour under test.
		if _player.is_ancestor_of(area):
			continue
		if area.monitoring:
			area.monitoring = false
			frozen += 1
	print("capture: froze %d world Area3D(s) so pickups cannot change between shots" % frozen)


## Find the VFX nodes a `hide_effects` shot switches off.
##
## Located by script class rather than by node name, so renaming a node in
## player.tscn cannot silently turn the pose test back into a normal capture — a
## failure mode this harness has already been bitten by twice.
func _collect_effects() -> void:
	for node in _player.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var script: Script = mesh.get_script()
		if script == null:
			continue
		if script.get_global_name() in [&"SwordTrail", &"SpinRing", &"ChargeRing"]:
			_effect_nodes.append(mesh)
	# Found by type, not by path. The glow used to live at a fixed path under SwordGrip;
	# it moved inside the equipped weapon scene when weapons became items, and the stale
	# path failed SILENTLY — `get_node_or_null` returned null, the count printed 2 instead
	# of 3, and every `poseonly` frame kept its charge glow. A hardcoded path into another
	# node's internals is exactly the coupling that rots; an OmniLight under the player is
	# an effect whatever it is parented to.
	for node in _player.find_children("*", "OmniLight3D", true, false):
		_effect_nodes.append(node as Node3D)
	if _effect_nodes.is_empty():
		printerr("capture: found NO effect nodes — hide_effects shots will be identical"
			+ " to their effects-on twins, which silently invalidates a pose-only test")
	print("capture: %d effect node(s) available to hide_effects shots" % _effect_nodes.size())


## The "hide the body, keep only the weapon" test from PRIOR-ART-VISUAL.md, run the
## other way round: hide every EFFECT and keep the pose. If an action frame is
## indistinguishable from its idle with the ribbon and the rings switched off, then
## the VFX is carrying the whole read and the animation is carrying none — which is
## the diagnosis a blind critic reached from the other direction, saying six of seven
## effects read as props and the one frame that worked was carried by the pose.
##
## Returns the nodes it switched off so the caller can put them back.
##
## `process_mode` as well as `visible`, and that is not belt-and-braces: SwordTrail
## rebuilds its ImmediateMesh in `_physics_process` and sets `visible = true` at the
## end of it, so hiding it alone does nothing at all — a physics tick runs between
## here and `frame_post_draw` and puts the ribbon straight back. The first run of
## this test produced seven frames with the ribbon fully drawn and nothing to say
## it had failed.
func _hide_effects(shot: Dictionary) -> Array[Node3D]:
	var hidden: Array[Node3D] = []
	if not bool(shot.get("hide_effects", false)):
		return hidden
	for node in _effect_nodes:
		if node.visible:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.visible = false
			hidden.append(node)
	return hidden


## Snap the camera to exactly where it belongs, killing the lag.
##
## The pivot is `top_level` and chases the player with a lerp, so an action that
## moves the character leaves the camera somewhere different from where an idle
## frame leaves it. A critic caught that too: "the camera is not the same, it sits
## lower and closer." For a comparison test identical framing matters more than
## authentic camera lag, so a shot can ask for the lag to be removed.
##
## Deliberately opt-in: `combat.json` wants the real lagging camera, because that
## is what a player sees. `legibility.json` wants determinism.
func _lock_camera(shot: Dictionary) -> void:
	if not bool(shot.get("lock_camera", false)) or _pivot == null:
		return

	# Pin the character back to the shot's spot first. Locking the camera alone still
	# left 1-3 px of shift between paired frames, and the cause was not the camera: an
	# attack drives the character forward a few centimetres, so the camera correctly
	# followed a player who had genuinely moved. Horizontal only — Y stays wherever
	# physics put it, or the capsule would hover or sink.
	if shot.has("player_position"):
		var want: Array = shot["player_position"]
		var here := _player.global_position
		_player.global_position = Vector3(float(want[0]), here.y, float(want[2]))
	var height := 1.1
	if _player.get("camera_target_height") != null:
		height = float(_player.get("camera_target_height"))
	_pivot.global_position = _player.global_position + Vector3.UP * height
	_pivot.rotation.y = deg_to_rad(float(shot.get("camera_yaw_deg", 0.0)))
	if _arm != null:
		_arm.rotation.x = (deg_to_rad(float(shot["camera_pitch_deg"]))
			if shot.has("camera_pitch_deg") else _default_pitch)


## Is the player in the state a `capture_when` block is waiting for?
## Keys are the same three the expectations use: state, clip, live.
func _matches(when: Dictionary) -> bool:
	var probes := {
		"state": "get_state_name",
		"clip": "get_anim_state",
		"live": "is_attack_hitbox_active",
		"charged": "is_attack_charged",
	}
	for key in when:
		if not probes.has(key) or not _player.has_method(probes[key]):
			return false
		if str(_player.call(probes[key])).to_lower() != str(when[key]).to_lower():
			return false
	return true


## Assert that the frame is what the shot list says it is.
##
## This exists because a forced-choice legibility test (CRITIC.md Mode 4) is only
## as good as its labels, and mine were wrong: six frames listed as idle came out
## with the player mid-walk and mid-fall, which would have scored the animation
## for something the animation was not doing. The failure was silent — the PNGs
## looked plausible.
##
## `expect_state`, `expect_clip` and `expect_live` are all optional. Any shot that
## declares one and misses it is recorded as a failure and the run exits non-zero,
## so a mislabelled set can never reach a critic.
func _check_expectations(shot: Dictionary, name: String) -> void:
	var checks := {
		"expect_state": ["get_state_name", "state"],
		"expect_clip": ["get_anim_state", "clip"],
		"expect_live": ["is_attack_hitbox_active", "live"],
	}
	for key in checks:
		if not shot.has(key):
			continue
		var method: String = checks[key][0]
		var label: String = checks[key][1]
		if not _player.has_method(method):
			_failures.append("%s: cannot check %s, player has no %s()" % [name, label, method])
			continue
		var actual: Variant = _player.call(method)
		var wanted: Variant = shot[key]
		# `str()`, not `String()`: the String constructor rejects a bool outright,
		# so expect_live crashed the check it was meant to perform. Comparing as
		# lowercase strings also makes JSON's bool agree with the engine's, and
		# stops "Attack" and &"Attack" (StringName) reading as different.
		if str(actual).to_lower() != str(wanted).to_lower():
			_failures.append("%s: expected %s=%s but got %s" % [name, label, wanted, actual])


func _player_state() -> String:
	if _player == null:
		return ""
	var parts: PackedStringArray = []
	if _player.has_method("get_state_name"):
		parts.append("state=%s" % _player.call("get_state_name"))
	if _player.has_method("get_anim_state"):
		parts.append("clip=%s" % _player.call("get_anim_state"))
	if _player.has_method("is_attack_hitbox_active"):
		parts.append("live=%s" % _player.call("is_attack_hitbox_active"))
	if _player.has_method("is_attack_charged"):
		parts.append("charged=%s" % _player.call("is_attack_charged"))
	var tree := _player.get_node_or_null("AnimationTree") as AnimationTree
	if tree != null:
		var playback: Variant = tree.get("parameters/StateMachine/playback")
		if playback is AnimationNodeStateMachinePlayback:
			parts.append("t=%.3f" % (playback as AnimationNodeStateMachinePlayback).get_current_play_position())
	return "[%s]" % " ".join(parts)


# --- Plumbing -------------------------------------------------------------

func _load_shots(shots_name: String) -> Array:
	var path := SHOT_DIR % shots_name
	if not FileAccess.file_exists(path):
		printerr("capture: no shot list at %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Array:
		return parsed
	if parsed is Dictionary and (parsed as Dictionary).has("shots"):
		return (parsed as Dictionary)["shots"]
	printerr("capture: %s is neither an array of shots nor {\"shots\": [...]}" % path)
	return []


func _write_manifest(shots_name: String) -> void:
	var path := "%s/manifest.json" % _out_dir
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("capture: could not write manifest to %s" % path)
		return
	file.store_string(JSON.stringify({
		"shots": shots_name,
		"viewport": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"written": _written,
	}, "  "))
	file.close()
	print("capture: %d shot(s) in %s" % [_written.size(), _out_dir])


## Drop a .gdignore next to the output so the engine stops importing our own
## screenshots as game textures on every --import.
func _mark_ignored(dir: String) -> void:
	var marker := "%s/.gdignore" % dir
	if FileAccess.file_exists(marker):
		return
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file != null:
		file.close()


func _release_all() -> void:
	for action in InputMap.get_actions():
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _arg(key: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--%s=" % key):
			return raw.split("=", true, 1)[1]
	return fallback
