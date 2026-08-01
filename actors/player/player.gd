class_name Player
extends CharacterBody3D
## Player controller: camera-relative movement, and the sword.
##
## Everything that affects how this feels is an @export. Run the game, open the
## remote scene tree (Debugger -> Remote), select Player, and change these live.
##
## Structure, since this file no longer does everything itself:
##
##   Player            — inputs, timers, camera, and every verb the states call
##   StateMachine      — one PlayerState Node per gameplay state
##     Idle / Move / Air   — share PlayerLocomotionState
##     Attack              — the committed sword states
##
## The gameplay state machine and the AnimationTree's state machine are separate
## on purpose. Gameplay decides *what* the player is allowed to do; the clips
## decide *when* inside an action that becomes true, via Call Method Tracks. See
## tools/build_combat_anims.gd and PRIOR-ART.md.

## Emitted once per target per swing, after damage is applied.
signal attack_landed(hurt_box: HurtBox3D)

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

# --- Sword ---------------------------------------------------------------
@export_group("Sword")
## Press attack this early and it still lands once the window opens. The combo
## and the cancel both read this, so one number tunes how forgiving mashing is.
@export var attack_buffer_time: float = 0.18
## Hold attack this long for the spin. REFERENCE.md band is 900-1300 ms.
@export var charge_time: float = 1.05
## Forward drive while the blade is live. Small, but it stops a swing reading as
## a character standing still waving an arm.
@export var attack_lunge_speed: float = 2.6
@export var attack_lunge_accel: float = 42.0
## How hard the lunge is killed during recovery.
@export var attack_recover_friction: float = 26.0
@export var slash_damage: int = 1
@export var spin_damage: int = 2
## Blade look: resting steel, flashed white while the hitbox is live, and the
## charged tell. Assigned in player.tscn.
@export var blade_material: Material
@export var blade_live_material: Material
@export var blade_charged_material: Material

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
## Base field of view, and how much it widens at full speed. A small kick sells
## momentum far more cheaply than any change to the movement itself.
@export var camera_fov: float = 70.0
@export var camera_fov_kick: float = 6.0

@export_group("Animation")
## Horizontal speed above which the character switches from idle to walk. Also
## the Idle <-> Move state threshold, so the two can never disagree.
@export var walk_anim_threshold: float = 0.4
## Speed the walk cycle was authored for. The clip is time-scaled by
## (actual speed / this), which stops the feet skating across the ground.
@export var walk_anim_reference_speed: float = 3.2
@export var walk_anim_scale_min: float = 0.65
@export var walk_anim_scale_max: float = 2.1

@export_group("Audio")
## Seconds between footsteps at the reference walk speed.
@export var footstep_interval: float = 0.42
@export var sfx_swing: AudioStream
@export var sfx_swing_heavy: AudioStream
@export var sfx_charge_ready: AudioStream
@export var sfx_hit: AudioStream

@onready var rig: Node3D = $Rig
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var anim_tree: AnimationTree = $AnimationTree
## Ours, not the .glb's: it loads player_anims.tres, whose tracks are pathed from
## the Player. CLAUDE.md records that property changes on nodes inside an
## instanced .glb get dropped, so the combat clips do not go there.
@onready var anim_player: AnimationPlayer = $AnimPlayer
@onready var interact_field: Area3D = $InteractField
# Quoted, not `$`: the hyphen in `arm-right` is not a valid identifier, so the
# shorthand cannot express this path.
@onready var sword: Node3D = get_node("Rig/Character/character/root/torso/arm-right/SwordGrip")
@onready var sword_hitbox: SwordHitBox = sword.get_node("HitBox")
@onready var blade: MeshInstance3D = sword.get_node("Blade")
@onready var charge_glow: OmniLight3D = sword.get_node("ChargeGlow")
@onready var sword_trail: SwordTrail = $SwordTrail
@onready var sfx_blade_player: AudioStreamPlayer3D = $SfxBlade
@onready var sfx_cue_player: AudioStreamPlayer3D = $SfxCue
# Typed as Node, not PlayerStateMachine: the states are typed against Player, so
# naming the machine's class here would close a script dependency cycle.
@onready var states: Node = $StateMachine

# --- Read by the states. Set by the clips' method tracks. -----------------
## True while the sword hitbox is armed.
var attack_hitbox_active := false
## True once the clip's cancel/combo window has opened.
var attack_can_cancel := false
## True once the clip has run out.
var attack_finished := false

var _state_machine: AnimationNodeStateMachinePlayback
var _focus: Interactable = null
var _hud: Node = null
var _footstep_timer := 0.0
var _was_on_floor := true

var _base_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

var _attack_started: int = 0
var _attack_buffer_timer: float = 0.0
var _charge_timer: float = 0.0
var _charged := false
var _spin_requested := false


func _ready() -> void:
	# Detach the camera rig from the body so it can lag behind instead of being
	# welded to the player. This is what makes the camera feel like a camera.
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position + Vector3.UP * camera_target_height
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# The model faces +Z at yaw 0, which is straight at the camera. Start it
	# facing away instead, the way a third-person character should.
	rig.rotation.y = PI

	# player_anims.tres already bakes LOOP_LINEAR into idle and walk, unlike the
	# raw glTF import. Belt and braces, because a non-looping walk is a bug that
	# takes ten minutes to spot and one line to prevent.
	for clip in ["idle", "walk"]:
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR

	# The state machine sits inside a blend tree behind a TimeScale node, so the
	# playback path is nested.
	_state_machine = anim_tree["parameters/StateMachine/playback"]

	Toonify.apply($Rig/Character)
	_hud = get_tree().get_first_node_in_group("hud")

	sword_hitbox.amount = slash_damage
	sword_hitbox.landed.connect(_on_sword_landed)
	_refresh_blade_look()

	states.setup(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc is owned by the pause menu, which is also the only thing that releases
	# the mouse — so the player can never get stuck with a captured cursor.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)


func _rotate_camera(yaw_delta: float, pitch_delta: float) -> void:
	camera_pivot.rotation.y = wrapf(camera_pivot.rotation.y + yaw_delta, -PI, PI)
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x + pitch_delta,
		deg_to_rad(pitch_min_deg),
		deg_to_rad(pitch_max_deg),
	)


## Camera, then timers, then whichever state is current, then footsteps. The
## states call back into the verbs below; nothing here decides behaviour.
func _physics_process(delta: float) -> void:
	_update_camera(delta)

	var on_floor := is_on_floor()
	_tick_jump_timers(delta, on_floor)
	_tick_attack_input(delta)

	states.physics_update(delta, on_floor)

	_update_footsteps(delta, on_floor)


# --- Timers ---------------------------------------------------------------

func _tick_jump_timers(delta: float, on_floor: bool) -> void:
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


## Attack buffering and the spin charge. Runs every tick regardless of state, so
## the charge survives the slash it started with — which is what makes "tap to
## slash, hold to spin" one gesture instead of two.
func _tick_attack_input(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		_attack_buffer_timer = attack_buffer_time
		_spin_requested = false
		_charge_timer = 0.0
		_charged = false
		_refresh_blade_look()
	else:
		_attack_buffer_timer = maxf(_attack_buffer_timer - delta, 0.0)
		if _attack_buffer_timer <= 0.0:
			_spin_requested = false

	if Input.is_action_pressed("attack"):
		_charge_timer += delta
		if not _charged and _charge_timer >= charge_time:
			_charged = true
			# The tell. REFERENCE.md is explicit that the threshold needs to be
			# both audible and visible, or the charge is a guess.
			_play_cue(sfx_charge_ready, -6.0)
			_refresh_blade_look()
	elif _charged:
		# Released while charged: the spin jumps the queue.
		_charged = false
		_spin_requested = true
		_attack_buffer_timer = attack_buffer_time
		_refresh_blade_look()
	else:
		_charge_timer = 0.0


# --- Verbs the locomotion states call, in this order ---------------------

func apply_gravity(delta: float, on_floor: bool) -> void:
	# Heavier on the way down so jumps don't feel floaty.
	if not on_floor:
		var g_scale := gravity_scale_down if velocity.y < 0.0 else gravity_scale_up
		velocity.y -= _base_gravity * g_scale * delta


func try_buffered_jump() -> bool:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = sqrt(2.0 * _base_gravity * gravity_scale_up * jump_height)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		Audio.play("jump", -8.0)
		return true
	return false


func tick_landing(on_floor: bool) -> void:
	if on_floor and not _was_on_floor:
		Audio.play("land", -9.0)
	_was_on_floor = on_floor


## Variable jump height: releasing the button early cuts the rise short.
func apply_jump_cut() -> void:
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= 0.45


func apply_movement(delta: float, on_floor: bool) -> void:
	var direction := camera_relative_input()

	var control := 1.0 if on_floor else air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := direction * max_speed

	var rate := (acceleration if direction != Vector3.ZERO else friction) * control
	horizontal = horizontal.move_toward(target, rate * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Flatten the camera basis onto the ground plane so "forward" means "away from
## the camera", not "into the floor".
func camera_relative_input() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

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
	return direction


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

	# Widen the lens slightly with speed. Eases in faster than it eases out, so
	# starting to run feels punchy but stopping doesn't snap.
	var ratio := clampf(get_horizontal_speed() / maxf(max_speed, 0.01), 0.0, 1.0)
	var wanted := camera_fov + camera_fov_kick * ratio
	var rate := 4.0 if wanted > camera.fov else 2.5
	camera.fov = lerpf(camera.fov, wanted, 1.0 - exp(-rate * delta))


func face_movement_direction(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.01:
		return
	var target_yaw := atan2(horizontal.x, horizontal.z)
	rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, turn_speed * delta)


# --- Verbs the attack state calls ----------------------------------------

## A swing commits your facing. Snapping to the stick on frame one reads as
## decisive; turning through the swing reads as mush.
func snap_facing_to_input() -> void:
	var direction := camera_relative_input()
	if direction != Vector3.ZERO:
		rig.rotation.y = atan2(direction.x, direction.z)


## Drive forward while the blade is live, then kill it during recovery.
func apply_attack_drive(delta: float, on_floor: bool) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := Vector3.ZERO
	var rate := attack_recover_friction
	if attack_hitbox_active and on_floor:
		# The rig's forward is +Z at yaw 0, so its facing is +basis.z.
		var facing := rig.global_basis.z
		facing.y = 0.0
		target = facing.normalized() * attack_lunge_speed
		rate = attack_lunge_accel
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Start one swing: clear the previous swing's windows, arm the right damage, and
## play the clip from its first frame.
func begin_attack(clip: StringName, spin: bool) -> void:
	_attack_started += 1
	attack_can_cancel = false
	attack_finished = false
	attack_hitbox_active = false
	sword_hitbox.end_swing()
	sword_hitbox.amount = spin_damage if spin else slash_damage
	_refresh_blade_look()
	play_anim(clip, 1.0, true)
	_play_blade(sfx_swing_heavy if spin else sfx_swing, -5.0)


func end_attack() -> void:
	attack_hitbox_active = false
	attack_can_cancel = false
	attack_finished = false
	sword_hitbox.end_swing()
	sword_trail.stop()
	_refresh_blade_look()


func has_attack_request() -> bool:
	return _attack_buffer_timer > 0.0


## Consume the pending request. Returns true if it was a charged release, i.e.
## this swing should be the spin.
func take_attack_request() -> bool:
	var spin := _spin_requested
	_attack_buffer_timer = 0.0
	_spin_requested = false
	return spin


func get_clip_length(clip: StringName) -> float:
	if not anim_player.has_animation(clip):
		return 0.5
	return anim_player.get_animation(clip).length


# --- Called by the clips' method tracks, never from GDScript --------------
#
# The names are the contract between tools/build_combat_anims.gd and this file.
# Retiming a swing means moving these keyframes in the generator; nothing here
# knows how long anything takes.

func _anim_hitbox_on() -> void:
	attack_hitbox_active = true
	sword_hitbox.begin_swing()
	sword_trail.start()
	_refresh_blade_look()


func _anim_hitbox_off() -> void:
	attack_hitbox_active = false
	sword_hitbox.end_swing()
	sword_trail.stop()
	_refresh_blade_look()


func _anim_allow_cancel() -> void:
	attack_can_cancel = true


func _anim_attack_finished() -> void:
	attack_finished = true


# --- Animation -----------------------------------------------------------

## Travel to `clip`. `force_restart` covers the case PRIOR-ART.md #8 warns about:
## neither travel() nor a transition will replay a node that is already current,
## which would silently swallow a repeated spin attack. start() re-enters it.
## Chosen over Snaiel's duplicated-transition-node scheme because one call site
## beats maintaining two copies of every attack node in the graph.
func play_anim(clip: StringName, scale: float, force_restart := false) -> void:
	if _state_machine == null:
		return
	if _state_machine.get_current_node() != clip:
		_state_machine.travel(clip)
	elif force_restart:
		_state_machine.start(clip, true)
	anim_tree.set("parameters/TimeScale/scale", scale)


## Locomotion clip selection, unchanged from before the state machine existed:
## chosen by measured speed after move_and_slide, and time-scaled to the ground
## speed so the feet do not skate.
func update_locomotion_anim(on_floor: bool) -> void:
	if _state_machine == null:
		return
	var speed := get_horizontal_speed()
	var wanted := "jump"
	if on_floor:
		wanted = "walk" if speed > walk_anim_threshold else "idle"
	if _state_machine.get_current_node() != wanted:
		_state_machine.travel(wanted)

	# Match the clip's playback rate to how fast we're actually travelling.
	var scale := 1.0
	if wanted == "walk":
		scale = clampf(
			speed / maxf(walk_anim_reference_speed, 0.01),
			walk_anim_scale_min,
			walk_anim_scale_max,
		)
	anim_tree.set("parameters/TimeScale/scale", scale)


# --- Blade look and sound -------------------------------------------------

func _refresh_blade_look() -> void:
	if blade == null:
		return
	if _charged:
		blade.material_override = blade_charged_material
	elif attack_hitbox_active:
		blade.material_override = blade_live_material
	else:
		blade.material_override = blade_material
	if charge_glow != null:
		charge_glow.visible = _charged


func _on_sword_landed(hurt_box: HurtBox3D) -> void:
	_play_cue(sfx_hit, -3.0)
	attack_landed.emit(hurt_box)


func _play_blade(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	sfx_blade_player.stream = stream
	sfx_blade_player.volume_db = volume_db
	sfx_blade_player.pitch_scale = randf_range(0.94, 1.06)
	sfx_blade_player.play()


func _play_cue(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	sfx_cue_player.stream = stream
	sfx_cue_player.volume_db = volume_db
	sfx_cue_player.pitch_scale = randf_range(0.97, 1.03)
	sfx_cue_player.play()


# --- Interaction ----------------------------------------------------------

func _process(_delta: float) -> void:
	_update_focus()
	if _focus != null and Input.is_action_just_pressed("interact"):
		_focus.interact(self)


## Pick what the player would interact with: nearest thing they're facing.
## Proximity + facing rather than a camera raycast, because there's no
## crosshair in a third-person adventure.
func _update_focus() -> void:
	var best: Interactable = null
	var best_score := -INF
	# The model's forward is +Z at yaw 0, so the rig's facing is +basis.z.
	var facing := rig.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()

	for area in interact_field.get_overlapping_areas():
		var target := area as Interactable
		if target == null or not target.can_interact():
			continue
		var to := target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		var aim := 1.0 if dist < 0.01 else facing.dot(to / dist)
		if aim < -0.25:
			continue  # behind us
		var score := aim - dist * 0.18
		if score > best_score:
			best_score = score
			best = target

	if best != _focus:
		_focus = best
		if _hud and _hud.has_method("set_prompt"):
			_hud.set_prompt(_focus)


func _update_footsteps(delta: float, on_floor: bool) -> void:
	var speed := get_horizontal_speed()
	if not on_floor or speed < walk_anim_threshold:
		# Land the next step immediately on resuming, rather than mid-stride.
		_footstep_timer = footstep_interval * 0.4
		return
	_footstep_timer -= delta * (speed / maxf(walk_anim_reference_speed, 0.01))
	if _footstep_timer <= 0.0:
		_footstep_timer = footstep_interval
		Audio.play("walking", -18.0, 0.14)


# --- Readouts, for the debug overlay and tools/probe.gd -------------------

## Current horizontal speed.
func get_horizontal_speed() -> float:
	return Vector3(velocity.x, 0.0, velocity.z).length()


## Name of the animation state currently playing.
func get_anim_state() -> String:
	return String(_state_machine.get_current_node()) if _state_machine else "-"


## Name of the gameplay state currently running — Idle, Move, Air, Attack.
func get_state_name() -> String:
	return String(states.get_state_name())


func is_attack_hitbox_active() -> bool:
	return sword_hitbox.monitoring


## Increments the moment a swing is accepted and its clip starts. The probe reads
## this to time commitment, rather than inferring it from elapsed time.
func get_attack_start_count() -> int:
	return _attack_started


## Increments once per armed hitbox window — the per-swing instance counter the
## multi-hit guard keys off.
func get_attack_swing_id() -> int:
	return sword_hitbox.get_swing_id()


func is_attack_charged() -> bool:
	return _charged


## 0 to 1 across the charge, for a HUD tell later.
func get_charge_ratio() -> float:
	return clampf(_charge_timer / maxf(charge_time, 0.001), 0.0, 1.0)
