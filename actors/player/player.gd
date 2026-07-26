extends CharacterBody3D
## M0 player controller: camera-relative movement, tuned for feel.
##
## Everything that affects how this feels is an @export. Run the game, open the
## remote scene tree (Debugger -> Remote), select Player, and change these live.
## That live-tweaking loop IS milestone M0. Nothing else in M0 matters.

# --- Ground movement -----------------------------------------------------
@export_group("Ground Movement")
## Top speed when the stick is fully pushed, in metres/sec.
@export var max_speed: float = 6.0
## How fast we reach max_speed. Higher = snappier, less weighty.
@export var acceleration: float = 60.0
## How fast we stop when input is released. Higher = less slide.
@export var friction: float = 50.0
## How fast the character model swings around to face the move direction.
@export var turn_speed: float = 12.0

# --- Air / jump ----------------------------------------------------------
@export_group("Air & Jump")
## Peak jump height in metres. Solved into an impulse against gravity.
@export var jump_height: float = 1.6
## Gravity multiplier while rising. 1.0 = normal.
@export var gravity_scale_up: float = 1.0
## Gravity multiplier while falling. >1 kills floatiness — the classic fix.
@export var gravity_scale_down: float = 1.6
## Grace period after walking off a ledge where jump still works.
@export var coyote_time: float = 0.12
## Press jump this early before landing and it still fires.
@export var jump_buffer_time: float = 0.12
## Fraction of horizontal control retained mid-air. 1.0 = full air control.
@export_range(0.0, 1.0) var air_control: float = 0.6

# --- Camera --------------------------------------------------------------
@export_group("Camera")
## Mouse look sensitivity.
@export var mouse_sensitivity: float = 0.0032
## Right-stick look speed, radians/sec.
@export var stick_sensitivity: float = 2.6
## How far down (negative) and up the camera can pitch, in degrees.
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 25.0
## Camera positional lag. Higher = tighter/snappier, lower = floatier.
@export var camera_follow_speed: float = 12.0
## Height above the player's origin the camera pivots around.
@export var camera_target_height: float = 1.1

@export_group("Animation")
## Horizontal speed above which the character switches from idle to walk.
@export var walk_anim_threshold: float = 0.4

@onready var rig: Node3D = $Rig
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var anim_player: AnimationPlayer = $Rig/Character/AnimationPlayer

var _state_machine: AnimationNodeStateMachinePlayback

var _base_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0


func _ready() -> void:
	# Detach the camera rig from the body so it can lag behind instead of being
	# welded to the player. This is what makes the camera feel like a camera.
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position + Vector3.UP * camera_target_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# The model faces +Z at yaw 0, which is straight at the camera. Start it
	# facing away instead, the way a third-person character should.
	rig.rotation.y = PI

	# The glTF import brings every clip in as non-looping, so idle and walk
	# would play once and freeze. Force them to loop.
	for clip in ["idle", "walk"]:
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR

	_state_machine = anim_tree["parameters/playback"]

	# Kenney's model imports with standard shading. Switch its materials to toon
	# so the character reads the same way as the rest of the world.
	for node in $Rig/Character.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface) as StandardMaterial3D
			if mat != null:
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				mat.specular_mode = BaseMaterial3D.SPECULAR_TOON


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _rotate_camera(yaw_delta: float, pitch_delta: float) -> void:
	camera_pivot.rotation.y = wrapf(camera_pivot.rotation.y + yaw_delta, -PI, PI)
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x + pitch_delta,
		deg_to_rad(pitch_min_deg),
		deg_to_rad(pitch_max_deg),
	)


func _physics_process(delta: float) -> void:
	_update_camera(delta)

	var on_floor := is_on_floor()

	# Coyote time: keep a jump available briefly after leaving the ground.
	if on_floor:
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	# Jump buffer: remember a too-early press until we land.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# Gravity — heavier on the way down so jumps don't feel floaty.
	if not on_floor:
		var g_scale := gravity_scale_down if velocity.y < 0.0 else gravity_scale_up
		velocity.y -= _base_gravity * g_scale * delta

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = sqrt(2.0 * _base_gravity * gravity_scale_up * jump_height)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	# Variable jump height: releasing the button early cuts the rise short.
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= 0.45

	_apply_movement(delta, on_floor)
	move_and_slide()
	_face_movement_direction(delta)
	_update_animation(on_floor)


func _apply_movement(delta: float, on_floor: bool) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Flatten the camera basis onto the ground plane so "forward" means
	# "away from the camera", not "into the floor".
	var cam_basis := camera_pivot.global_basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var direction := (right * input_dir.x + forward * -input_dir.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var control := 1.0 if on_floor else air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := direction * max_speed

	var rate := (acceleration if direction != Vector3.ZERO else friction) * control
	horizontal = horizontal.move_toward(target, rate * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _face_movement_direction(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.01:
		return
	var target_yaw := atan2(horizontal.x, horizontal.z)
	rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, turn_speed * delta)


func _update_camera(delta: float) -> void:
	# Right-stick look.
	var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if look != Vector2.ZERO:
		_rotate_camera(-look.x * stick_sensitivity * delta, -look.y * stick_sensitivity * delta)

	# Lag the pivot toward the player instead of snapping to them.
	var target := global_position + Vector3.UP * camera_target_height
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		target, 1.0 - exp(-camera_follow_speed * delta)
	)


func _update_animation(on_floor: bool) -> void:
	if _state_machine == null:
		return
	var wanted := "jump"
	if on_floor:
		wanted = "walk" if get_horizontal_speed() > walk_anim_threshold else "idle"
	if _state_machine.get_current_node() != wanted:
		_state_machine.travel(wanted)


## Current horizontal speed, for the debug readout.
func get_horizontal_speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()


## Name of the animation state currently playing, for the debug readout.
func get_anim_state() -> String:
	return String(_state_machine.get_current_node()) if _state_machine else "-"
