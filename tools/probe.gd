extends Node
## Headless measurement harness. Feel gets measured here, not argued about.
##
## Run as a SCENE, never with --script: GameState and Audio are autoloads, and
## autoloads are not instantiated when a bare script is the main loop.
##
##     GODOT="C:/tools/godot/Godot_v4.7.1-stable_win64_console.exe"
##     "$GODOT" --headless --fixed-fps 60 --path . res://tools/probe.tscn -- --suite=movement
##
## --fixed-fps decouples the physics step from wall time, so a run is both fast
## and deterministic. Without it the numbers drift with machine load.
##
## Output is a single JSON object between markers, so a critic can be handed the
## measurements without the engine's boot noise.

const LEVEL := "res://world/rooms/greenhollow_clearing.tscn"
const BEGIN := "##PROBE-BEGIN##"
const END := "##PROBE-END##"

## Every action the harness might hold. Released between measurements so one
## test can never leak a stuck input into the next.
const ALL_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "interact", "attack", "target", "shield", "roll",
]

var _measurements: Array = []
var _level: Node = null
var _player: CharacterBody3D = null
var _spawn: Transform3D


func _ready() -> void:
	var suite := _arg("suite", "movement")

	_level = load(LEVEL).instantiate()
	add_child(_level)
	await get_tree().physics_frame

	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		_fail("no node in group 'player' after loading %s" % LEVEL)
		return
	_spawn = _player.global_transform

	# Let gravity settle the capsule onto the ground and the camera pivot catch up.
	await _frames(40)

	match suite:
		"movement":
			await _suite_movement()
		"combat":
			await _suite_combat()
		"all":
			await _suite_movement()
			await _suite_combat()
		_:
			_fail("unknown suite '%s' — known: movement, combat, all" % suite)
			return

	_emit(suite)

	# Tear the level down before quitting, or the engine prints leaked-instance
	# warnings that end up pasted into a critic's input as if they were findings.
	_release_all()
	remove_child(_level)
	_level.free()
	await get_tree().process_frame
	get_tree().quit(0)


# --- Suites ---------------------------------------------------------------

func _suite_movement() -> void:
	await _reset()

	# Time to reach top speed from a standstill. Explicit types throughout: the
	# player's @export properties are not visible to the static analyser through
	# a CharacterBody3D reference, so `:=` cannot infer them.
	var max_speed: float = _player.max_speed
	Input.action_press("move_forward")
	var target: float = max_speed * 0.99
	var frames: int = await _frames_until(
		func() -> bool: return _speed() >= target, 240)
	_add("accel_to_max_speed", _ms(frames), "ms",
		"press to 99%% of max_speed (%.1f m/s)" % max_speed)

	# Top speed actually achieved, which is not always the exported number.
	await _frames(30)
	_add("max_speed_actual", _speed(), "m/s",
		"sustained horizontal speed while holding forward")

	# Time to stop once input is released.
	_release_all()
	frames = await _frames_until(func() -> bool: return _speed() < 0.05, 240)
	_add("decel_to_stop", _ms(frames), "ms", "release to under 0.05 m/s")

	# Jump arc, from a standstill.
	await _reset()
	var floor_y := _player.global_position.y
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	var apex := floor_y
	var airborne := 0
	while airborne < 240:
		await get_tree().physics_frame
		airborne += 1
		apex = maxf(apex, _player.global_position.y)
		if airborne > 4 and _player.is_on_floor():
			break
	_add("jump_apex_height", apex - floor_y, "m", "peak rise above the takeoff plane")
	_add("jump_airtime", _ms(airborne), "ms", "takeoff to landing, jump tapped")

	# The same jump with the button held, which should go measurably higher —
	# if these two match, variable jump height is broken.
	await _reset()
	floor_y = _player.global_position.y
	Input.action_press("jump")
	apex = floor_y
	airborne = 0
	while airborne < 240:
		await get_tree().physics_frame
		airborne += 1
		apex = maxf(apex, _player.global_position.y)
		if airborne > 4 and _player.is_on_floor():
			break
	_release_all()
	_add("jump_apex_height_held", apex - floor_y, "m", "peak rise with jump held")
	_add("jump_airtime_held", _ms(airborne), "ms", "takeoff to landing, jump held")

	_release_all()


## Sword attacks: the wind-up, the live window, commitment, the combo/cancel
## window, the charge threshold, and whether damage actually lands exactly once
## per target per swing.
##
## Everything here reads an observable the game itself uses — `monitoring` on the
## real hitbox, the swing counter the multi-hit guard keys off, the health of a
## real hurtbox — rather than a number the player script reports about itself.
func _suite_combat() -> void:
	await _reset()

	# Wiring first, so a missing sword reads as a failure rather than as a
	# plausible-looking zero further down.
	var hitbox: Node = _player.get_node_or_null(
		"Rig/Character/character/root/torso/arm-right/SwordGrip/HitBox")
	_add("sword_hitbox_wired", 1.0 if hitbox != null else -1.0, "bool",
		"SwordGrip/HitBox exists under the right arm")
	if hitbox == null:
		return
	var layer: int = hitbox.collision_layer
	var mask: int = hitbox.collision_mask
	_add("hitbox_layer", float(layer), "bitmask", "expect 16 (layer 5 player_hitbox)")
	_add("hitbox_mask", float(mask), "bitmask", "expect 32 (layer 6 enemy_hurtbox)")

	# --- Swing one: wind-up and the live window ---------------------------
	var on_at := -1
	var off_at := -1
	var released := false
	Input.action_press("attack")
	var elapsed := 0
	while elapsed < 180:
		await get_tree().physics_frame
		elapsed += 1
		# Let go quickly: holding past charge_time turns this into a spin.
		if elapsed >= 2 and not released:
			Input.action_release("attack")
			released = true
		var live: bool = _player.is_attack_hitbox_active()
		if on_at < 0:
			if live:
				on_at = elapsed
		elif off_at < 0 and not live:
			off_at = elapsed
			break
	_add("attack_windup", _ms(on_at), "ms", "attack press to sword hitbox monitoring")
	_add("attack_hitbox_active", _ms(off_at - on_at if off_at > 0 else -1), "ms",
		"hitbox monitoring true to false")
	_add("attack_clip", 1.0 if String(_player.get_anim_state()) == "slash_a" else -1.0,
		"bool", "first swing plays slash_a")

	# --- Commitment and the combo link ------------------------------------
	# One press, then a second press well inside the swing. The follow-up is
	# buffered and can only start when the clip's cancel keyframe opens the
	# window, so the frame it starts IS the total commitment.
	await _reset()
	# +2, not +1: the first press starts a swing of its own, so the counter has to
	# clear TWO starts before the follow-up has actually been accepted.
	var want_starts: int = int(_player.get_attack_start_count()) + 2
	var commit := -1
	Input.action_press("attack")
	elapsed = 0
	while elapsed < 240:
		await get_tree().physics_frame
		elapsed += 1
		if elapsed == 2:
			Input.action_release("attack")
		if elapsed == 6:
			Input.action_press("attack")   # follow-up, pressed early on purpose
		if elapsed == 8:
			Input.action_release("attack")
		if int(_player.get_attack_start_count()) >= want_starts:
			commit = elapsed
			break
	_add("attack_commitment", _ms(commit), "ms",
		"first press to the second swing being accepted, follow-up pressed at frame 6")
	# One frame later, because the anim state machine travels after the Player's
	# physics tick. Checked so the combo is proven to alternate, not repeat.
	await _frames(2)
	var second_clip := String(_player.get_anim_state())
	_add("combo_alternates", 1.0 if second_clip == "slash_b" else -1.0, "bool",
		"second swing plays slash_b, not slash_a again (got '%s')" % second_clip)
	_release_all()

	# --- Charge threshold and the spin ------------------------------------
	await _reset()
	Input.action_press("attack")
	var charged_at := await _frames_until(
		func() -> bool: return bool(_player.is_attack_charged()), 180)
	_add("charge_threshold", _ms(charged_at), "ms",
		"attack held to the charged tell firing")

	var starts: int = _player.get_attack_start_count()
	Input.action_release("attack")
	on_at = -1
	off_at = -1
	var spin_at := -1
	elapsed = 0
	while elapsed < 180:
		await get_tree().physics_frame
		elapsed += 1
		if spin_at < 0 and int(_player.get_attack_start_count()) > starts:
			spin_at = elapsed
		var live: bool = _player.is_attack_hitbox_active()
		if on_at < 0:
			if live:
				on_at = elapsed
		elif off_at < 0 and not live:
			off_at = elapsed
			break
	_add("spin_release_to_start", _ms(spin_at), "ms",
		"charged release to the spin clip starting")
	_add("spin_windup", _ms(on_at), "ms", "charged release to hitbox monitoring")
	_add("spin_hitbox_active", _ms(off_at - on_at if off_at > 0 else -1), "ms",
		"spin hitbox monitoring true to false — deliberately longer than a slash")
	_add("spin_clip", 1.0 if String(_player.get_anim_state()) == "spin_attack" else -1.0,
		"bool", "the charged release plays spin_attack")
	_release_all()
	await _frames(60)

	# --- Attacking out of a run -------------------------------------------
	# The Move state has its own wiring to Attack, and a null export there would
	# fail silently in exactly the situation a player is most likely to be in.
	await _reset()
	Input.action_press("move_forward")
	await _frames(20)
	var running: float = _speed()
	starts = _player.get_attack_start_count()
	Input.action_press("attack")
	var from_run := await _frames_until(
		func() -> bool: return int(_player.get_attack_start_count()) > starts, 60)
	Input.action_release("attack")
	_add("run_speed_before_attack", running, "m/s", "speed when the attack was pressed")
	_add("attack_from_run", _ms(from_run), "ms", "press to swing accepted while running")
	_release_all()
	await _frames(45)

	# --- Damage, and the multi-hit guard ----------------------------------
	await _reset()
	var target := _spawn_target(1.25, 1.0)
	await _frames(4)
	var health: Node = target.get_node("Health")
	var start_hp: int = health.current

	await _swing_once()
	var after_one: int = health.current
	_add("damage_one_swing", float(start_hp - after_one), "hp",
		"health lost across a whole single swing — slash_damage is 1, so more than 1 means the arc double-dipped")

	await _frames(40)
	await _swing_once()
	_add("damage_two_swings", float(start_hp - int(health.current)), "hp",
		"cumulative after a second swing — proves the guard resets per swing")
	_add("swing_ids_used", float(_player.get_attack_swing_id()), "count",
		"per-swing instance counter after two swings")

	target.queue_free()
	await _frames(4)
	_release_all()


## Tap attack and wait out the whole swing.
func _swing_once() -> void:
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(34)


## A minimal enemy stand-in: Health plus a BasicHurtBox3D on layer 6, built in
## code so the combat suite does not depend on an enemy scene that another
## builder owns. Placed `ahead` metres along the player's facing.
func _spawn_target(ahead: float, height: float) -> Node3D:
	var rig: Node3D = _player.get_node("Rig")
	var facing := rig.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()

	var root := Node3D.new()
	root.name = "ProbeTarget"

	var health := Health.new()
	health.name = "Health"
	health.max = 99
	health.current = 99
	root.add_child(health)

	var hurt := BasicHurtBox3D.new()
	hurt.name = "HurtBox"
	hurt.health = health
	hurt.collision_layer = 32   # layer 6, enemy_hurtbox
	hurt.collision_mask = 0
	hurt.monitoring = false     # it only needs to BE found
	hurt.monitorable = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	hurt.add_child(shape)
	root.add_child(hurt)

	_level.add_child(root)
	root.global_position = _player.global_position + facing * ahead + Vector3.UP * height
	return root


# --- Plumbing -------------------------------------------------------------

## Park the player back at spawn with no velocity and no held inputs.
func _reset() -> void:
	_release_all()
	_player.velocity = Vector3.ZERO
	_player.global_transform = _spawn
	await _frames(30)


## The player's horizontal speed as a real float, not a Variant.
func _speed() -> float:
	return Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()


func _release_all() -> void:
	for action in ALL_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## Advance until `test` returns true. Returns the frame count, or -1 on timeout
## so a missing feature reads as a failure rather than as a plausible number.
func _frames_until(test: Callable, timeout_frames: int) -> int:
	var elapsed := 0
	while elapsed < timeout_frames:
		await get_tree().physics_frame
		elapsed += 1
		if test.call():
			return elapsed
	return -1


func _ms(frames: int) -> float:
	if frames < 0:
		return -1.0
	return frames * 1000.0 / float(Engine.physics_ticks_per_second)


func _add(name: String, value: float, unit: String, note: String) -> void:
	_measurements.append({
		"name": name,
		"value": snappedf(value, 0.001),
		"unit": unit,
		"note": note,
		"timed_out": value < 0.0,
	})


func _emit(suite: String) -> void:
	print(BEGIN)
	print(JSON.stringify({
		"suite": suite,
		"physics_hz": Engine.physics_ticks_per_second,
		"measurements": _measurements,
	}, "  "))
	print(END)


func _fail(reason: String) -> void:
	printerr("probe: %s" % reason)
	print(BEGIN)
	print(JSON.stringify({"error": reason}, "  "))
	print(END)
	get_tree().quit(1)


## Read `--key=value` out of the args after the `--` separator.
func _arg(key: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--%s=" % key):
			return raw.split("=", true, 1)[1]
	return fallback
