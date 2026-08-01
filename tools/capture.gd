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
var _out_dir := ""
var _written: Array = []


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

	for shot in shots:
		await _run_shot(shot)

	_write_manifest(shots_name)
	_release_all()
	remove_child(_level)
	_level.free()
	await get_tree().process_frame
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

	if _pivot != null and shot.has("camera_yaw_deg"):
		_pivot.rotation.y = deg_to_rad(float(shot["camera_yaw_deg"]))
	if _arm != null and shot.has("camera_pitch_deg"):
		_arm.rotation.x = deg_to_rad(float(shot["camera_pitch_deg"]))
	if _arm != null and shot.has("camera_distance"):
		_arm.spring_length = float(shot["camera_distance"])

	# Walk the input timeline frame by frame and capture on the nominated frame.
	var timeline: Array = shot.get("inputs", [])
	var capture_at := int(shot.get("capture_at", 1))
	for frame in range(1, capture_at + 1):
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

	await _save(name)
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
	_written.append({"name": name, "path": path, "size": [image.get_width(), image.get_height()]})
	print("capture: wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])


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
