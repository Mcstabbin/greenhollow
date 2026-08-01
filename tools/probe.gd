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
		"all":
			await _suite_movement()
		_:
			_fail("unknown suite '%s' — known: movement, all" % suite)
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
