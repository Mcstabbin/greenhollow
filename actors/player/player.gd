class_name Player
extends CharacterBody3D
## Player controller: camera-relative movement, and whatever is in your hand.
##
## Everything that affects how this feels is an @export. Run the game, open the
## remote scene tree (Debugger -> Remote), select Player, and change these live.
##
## Structure, since this file no longer does everything itself:
##
##   Player            — inputs, timers, camera, and every verb the states call
##   Loadout           — the one equip slot; the weapon's nodes arrive with the item
##   StateMachine      — one PlayerState Node per gameplay state
##     Idle / Move / Air   — share PlayerLocomotionState
##     Attack              — the committed melee states
##     Block / Aim         — the shield and the bow
##
## NOTHING HERE NAMES A WEAPON. The hitbox, the trail markers, the charge glow and the
## mesh that flashes are all looked up through the Loadout on the frame an item is
## equipped, and the timing, damage, reach and clip of a swing all arrive as an
## AttackStep. That is what makes the axe a `.tres` file and not a branch, and it is the
## property to protect: the moment this file contains `if weapon.id == &"axe"`, the data
## model has failed and the model is what wants fixing.
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

# --- Weapons -------------------------------------------------------------
@export_group("Weapons")
## Press attack this early and it still lands once the window opens. The combo
## and the cancel both read this, so one number tunes how forgiving mashing is.
@export var attack_buffer_time: float = 0.18
## Hold attack this long for the charged attack, when the equipped weapon does not say
## otherwise. MeleeWeapon.ms_charge overrides it, so this is the fallback for a weapon
## that forgot to set one. REFERENCE.md band is 900-1300 ms.
@export var charge_time: float = 1.05
## Forward drive while the blade is live. Small, but it stops a swing reading as
## a character standing still waving an arm.
@export var attack_lunge_speed: float = 2.6
@export var attack_lunge_accel: float = 42.0
## How hard the lunge is killed during recovery.
@export var attack_recover_friction: float = 26.0
## The two STATE tints, applied to whichever mesh the equipped weapon nominates as its
## hot one (MeleeWeapon.hot_mesh). Orange means a blade is live and cyan means charged,
## and those two meanings are fixed across every weapon — the resting look belongs to
## the weapon and is remembered on equip.
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

@export_group("Lock-on Camera")
## How fast the camera swings round behind the player and settles on the framing
## when a lock is taken, as an exponential rate.
##
## MEASURED, and not the number the arithmetic suggested. REFERENCE.md's settle band
## is 250-400 ms; for a plain `1 - exp(-r*t)` the 90% point is `ln(10)/r`, which put
## the answer at 8.0 — and the probe then measured 633 ms. The reason is that pitch
## is not a plain lerp toward a fixed angle: the solve re-derives its target every
## frame from where the eye currently is, and pitching the arm MOVES the eye, so the
## goal retreats as the camera approaches it. A lagging feedback loop settles at
## roughly half its nominal rate. Measured: rate 8 settles in 633 ms, 14 in 417, 18 in
## 350 — and 417 was not good enough for a second reason, the cross-check REFERENCE.md
## puts above every individual band. Total attack commitment measures 417 ms, and
## "camera settle < attack commitment" is what stops you swinging before you can see.
@export var lockon_camera_speed: float = 18.0
## Where the TARGET is framed, as a fraction of the frame height from the top. The
## camera does not aim at the target: it solves for the pitch that puts the target
## HERE, which drops the player low in frame and opens the volume between the two.
## That is Snaiel's trick and Zelda's composition — see PRIOR-ART-VISUAL.md.
@export_range(0.05, 0.5) var lockon_target_screen_height: float = 0.25
## How fast the character turns to keep facing the target while strafing. Fast: a
## locked character that lags behind its own lock reads as broken.
@export var lockon_turn_speed: float = 16.0
## How much higher the camera pivots while locked, in metres. The pivot is what the
## frame is centred on, so lifting it pushes the CHARACTER down the frame while the
## pitch solve keeps the target at a quarter height — which is the "player low,
## target high" half of the Z-target composition. Measured: at 0 the chest sits dead
## centre with 172 px between it and the target; 0.45 opens that to ~218 px without
## bringing the feet anywhere near the bottom edge.
@export var lockon_pivot_lift: float = 0.45
## Mouse travel, in pixels, that counts as a request to switch target. Snaiel uses
## 60; the camera stick has its own threshold on the lock-on component.
@export var lockon_mouse_switch_px: float = 70.0

@export_group("Aim Camera")
## The over-the-shoulder rig for a drawn bow, blended in while PlayerAimState runs.
##
## This exists because of a MEASURED structural failure, not for flavour. From a
## camera directly behind the character the draw axis IS the view axis, so the
## retraction, the string and the nocked arrow all foreshorten to nothing, and a
## bow's silhouette is a 3-5 px line whichever way you look at it. The builder that
## posed the draw said plainly that no pose fixes it and the answer is this camera.
## Two things it buys: the character is 2.3x larger on screen at 2.4 m than at
## 5.5 m, and a 0.95 m lateral offset puts ~21 degrees between the draw axis and
## the view axis, so the pull finally has a component across the frame.
@export var aim_camera_distance: float = 2.4
@export var aim_camera_shoulder: float = 0.95
@export var aim_camera_height: float = 1.45
@export var aim_camera_fov: float = 64.0
## Pitch the camera is lifted to as the shoulder rig blends in, in degrees.
##
## Not cosmetic. At the walking default of -20 degrees a camera 2.4 m behind the
## character is looking at the grass in front of its feet, and the first photographed
## aim frame proved it: the bow read fine and there was nowhere to aim it. Blended in
## ONLY while the rig is arriving, so free look owns the pitch again the moment it has
## settled — the alternative would be a camera that fights the stick for as long as
## the button is held. The side effect is that the camera stays where the draw left it
## after the shot, which one flick of the look axis undoes.
@export var aim_camera_pitch_deg: float = -6.0
## How fast the shoulder rig blends in and out. A cut would read as a glitch; a
## slow slide would mean the first third of a draw is framed for walking.
@export var aim_camera_speed: float = 14.0

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
## The one equip slot. Everything about the held weapon is reached through this.
@onready var loadout: Loadout = $Loadout
## Z-targeting. Typed, unlike `states`, because components/lockon_system.gd is
## deliberately written against a plain Node3D body and a Camera3D — so naming its
## class here closes no dependency cycle.
@onready var lockon: LockOnSystem = $LockOn
@onready var sword_trail: SwordTrail = $SwordTrail
@onready var charge_ring: ChargeRing = $ChargeRing
@onready var sfx_blade_player: AudioStreamPlayer3D = $SfxBlade
@onready var sfx_cue_player: AudioStreamPlayer3D = $SfxCue
# Typed as Node, not PlayerStateMachine: the states are typed against Player, so
# naming the machine's class here would close a script dependency cycle.
@onready var states: Node = $StateMachine

# --- Resolved from the Loadout on every equip. Null is normal. -------------
## The equipped weapon's damage volume. Null for a shield (blocking is a state, not a
## swing) and for a bow (the damage rides on the arrow).
var weapon_hitbox: SwordHitBox = null
## The mesh that takes the live/charged tints, and the material it wears at rest.
var hot_mesh: MeshInstance3D = null
var hot_mesh_rest: Material = null
## The weapon's own light, hidden until a threshold fires. Every weapon scene carries
## one under this name, so no weapon needs a special case.
var charge_glow: OmniLight3D = null

# --- Read by the states. Set by the clips' method tracks. -----------------
## True while the weapon hitbox is armed.
var attack_hitbox_active := false
## True once the clip's cancel/combo window has opened.
var attack_can_cancel := false
## True once the clip has run out.
var attack_finished := false
## How long the swing currently running actually takes, in seconds — the clip's length
## divided by the playback rate its AttackStep asked for. The Attack state reads it as
## its own safety timeout, so a slowed-down heavy swing does not trip a warning that was
## written for a sword.
var attack_clip_duration := 0.5

# --- Camera mode, written by the states, read by _update_camera -------------
## 0 while the camera sits centred behind the character, 1 while it is over the
## shoulder for an aimed shot. PlayerAimState writes it on enter and exit; the
## smoothing lives in `_update_camera` so nothing else has to own a blend.
##
## A plain var rather than a setter pair on purpose: `.gdlintrc` pins this file's
## public method count as a ratchet, and a camera MODE is state, not a verb.
var camera_shoulder := 0.0
## Where the camera pivot is heading this frame, in world space — the ideal
## position before the follow lag is applied. tools/capture.gd reads it so a
## `camera_from_game` shot can snap the pivot onto its mark without having to know
## how the pivot is placed. Assigned every tick, never read by gameplay.
var camera_pivot_target := Vector3.ZERO

var _state_machine: AnimationNodeStateMachinePlayback
var _focus: Interactable = null
var _hud: Node = null
var _footstep_timer := 0.0
var _was_on_floor := true
## Smoothed `camera_shoulder`.
var _shoulder := 0.0
## Smoothed 0-to-1 "is the camera locked on", so the pivot lift eases in and out
## instead of stepping on the frame a lock is taken.
var _lock_blend := 0.0
## `spring_arm.spring_length` as the scene ships it. The aim rig is the only thing
## that writes the spring, and it puts this back when it is done — so a capture shot
## that sets its own `camera_distance` is never overwritten by a rig that is off.
var _spring_rest := 5.5
## Mouse travel accumulated toward a target switch, in pixels.
var _switch_accum := 0.0

var _base_gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

var _attack_started: int = 0
## Which clip the current swing is. Read by _anim_attack_finished to tell its own
## end keyframe from the previous clip's, still firing as it cross-fades out.
var _attack_clip: StringName = &""
var _attack_buffer_timer: float = 0.0
var _charge_timer: float = 0.0
var _charged := false
var _spin_requested := false
## Purely cosmetic, and deliberately not `attack_hitbox_active`: the blade's glow
## follows the trail's window, which is wider than the damage window.
var _blade_hot := false


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

	_spring_rest = spring_arm.spring_length
	camera_pivot_target = camera_pivot.global_position
	# The component is written against a body and a camera, so the player wires
	# itself in rather than the component reaching out for a parent it assumes.
	lockon.body = self
	lockon.camera = camera
	lockon.locked.connect(_on_lock_acquired)
	lockon.released.connect(_on_lock_released)

	Toonify.apply($Rig/Character)
	_hud = get_tree().get_first_node_in_group("hud")
	if _hud != null and _hud.has_method("bind_loadout"):
		_hud.bind_loadout(loadout)
	if _hud != null and _hud.has_method("bind_lockon"):
		_hud.bind_lockon(lockon)

	# Connected AND called by hand, in that order. Child `_ready` runs before the
	# parent's, so the Loadout has already equipped the starting item and its
	# `equipped_changed` has already been emitted into nothing by the time we get here.
	loadout.equipped_changed.connect(_on_equipped_changed)
	_on_equipped_changed(loadout.equipped)

	states.setup(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc is owned by the pause menu, which is also the only thing that releases
	# the mouse — so the player can never get stuck with a captured cursor.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# While locked, the camera belongs to the lock and sideways mouse travel
		# means "switch target" instead. Steering the camera by hand and having it
		# dragged straight back onto the target is the version of this that feels
		# broken, so free look is not merely overridden — it is off.
		if lockon.is_locked():
			_switch_accum += event.relative.x
			if absf(_switch_accum) >= lockon_mouse_switch_px:
				lockon.try_switch(signf(_switch_accum))
				_switch_accum = 0.0
			return
		_switch_accum = 0.0
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
	# Lock-on first, and in this order: the press is read, then the lock is re-tested
	# for range and sight-line, and only then is the camera framed. A lock that broke
	# this tick therefore never gets a frame of locked framing, and a lock taken this
	# tick is framed on the frame it was taken.
	_tick_lockon_input()
	lockon.tick(delta)
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


## Attack buffering and the charge. Runs every tick regardless of state, so
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

	var threshold := _charge_seconds()
	if threshold <= 0.0:
		# Nothing equipped that can be charged. A bow's hold is PlayerAimState's draw and
		# a shield has no attack at all, so the charge timer must not run: it would arm a
		# spin that fires by itself the moment a sword comes back into your hand.
		_charge_timer = 0.0
		if _charged:
			_charged = false
			_refresh_blade_look()
		return

	if Input.is_action_pressed("attack"):
		_charge_timer += delta
		if not _charged and _charge_timer >= threshold:
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


## The target button, and target switching. Read here rather than inside the lock-on
## component for the same reason every other input is: this file owns what the player
## pressed, and the component owns what it means.
func _tick_lockon_input() -> void:
	if Input.is_action_just_pressed("target"):
		lockon.press()
	if lockon.is_locked():
		# The camera stick has nothing else to do while locked, so it flicks between
		# targets. `try_switch` owns the threshold and the debounce.
		lockon.try_switch(Input.get_axis("cam_left", "cam_right"))


## Acquire and release both get a sound, and it is deliberately the charge chime at
## two different pitches rather than a new asset: up for "held", down for "let go".
## A state this consequential needs an ear as well as an eye, and REFERENCE.md is
## explicit that a threshold with only one of the two is a guess.
func _on_lock_acquired(_target: LockOnTarget) -> void:
	_play_lock_cue(1.4)


func _on_lock_released() -> void:
	_switch_accum = 0.0
	_play_lock_cue(0.78)


func _play_lock_cue(pitch: float) -> void:
	# `is_inside_tree` is not caution: tearing a level down makes every target leave
	# the detection sphere, which breaks the lock, which lands here after the audio
	# player has already left the tree. Godot's answer to that is an error per lock.
	if sfx_charge_ready == null or not is_inside_tree():
		return
	sfx_cue_player.stream = sfx_charge_ready
	sfx_cue_player.volume_db = -13.0
	sfx_cue_player.pitch_scale = pitch
	sfx_cue_player.play()


## Seconds of hold before the charged attack is available, or 0 when the equipped item
## has no charged attack at all — which is a legitimate answer for some weapons, and the
## answer for both the bow and the shield.
func _charge_seconds() -> float:
	var melee := loadout.equipped as MeleeWeapon
	if melee == null or melee.charged == null:
		return 0.0
	return melee.ms_charge / 1000.0 if melee.ms_charge > 0 else charge_time


# --- Equipping ------------------------------------------------------------

## Rebind everything that belongs to the held weapon: its hitbox, the markers the ribbon
## samples between, its light, and the mesh that carries the live and charged tints.
##
## Called on every swap including the first, and every lookup is allowed to come back
## null. That is not defensive habit — a shield genuinely has no hitbox, a bow has no
## trail markers, and an empty hand has none of it. The nodes of the PREVIOUS weapon are
## already freed by the time this runs, so nothing is disconnected here: the connections
## went with them.
func _on_equipped_changed(item: ItemData) -> void:
	weapon_hitbox = loadout.find_in_weapon("SwordHitBox") as SwordHitBox
	if weapon_hitbox != null:
		weapon_hitbox.landed.connect(_on_sword_landed)
	charge_glow = loadout.part(&"ChargeGlow") as OmniLight3D

	sword_trail.blade_base = loadout.part(&"BladeBase") as Node3D
	sword_trail.blade_tip = loadout.part(&"BladeTip") as Node3D

	var melee := item as MeleeWeapon
	hot_mesh = loadout.part(melee.hot_mesh) as MeshInstance3D if melee != null else null
	hot_mesh_rest = hot_mesh.material_override if hot_mesh != null else null
	if melee != null:
		# The ribbon's hue and length are the weapon's, not the trail's. Both stay inside
		# the one hue this world leaves free: orange means a blade is live, whatever the
		# blade is.
		sword_trail.tint_mid = melee.trail_tint
		sword_trail.history_ticks = maxf(
			1.0, melee.ms_trail * Engine.physics_ticks_per_second / 1000.0)

	_blade_hot = false
	_refresh_blade_look()


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


## `scale` caps the top speed without touching acceleration or friction, which is what a
## guard or a draw wants: you can still reposition at the same responsiveness, you just
## cannot get anywhere. Defaulted, so the locomotion states' call is unchanged and the
## movement baseline cannot move.
func apply_movement(delta: float, on_floor: bool, scale: float = 1.0) -> void:
	var direction := camera_relative_input()

	var control := 1.0 if on_floor else air_control
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := direction * max_speed * scale

	var rate := (acceleration if direction != Vector3.ZERO else friction) * control
	horizontal = horizontal.move_toward(target, rate * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Flatten the camera basis onto the ground plane so "forward" means "away from
## the camera", not "into the floor".
##
## While locked on, the basis is the TARGET's rather than the camera's, and that one
## substitution is the whole of strafing: pushing sideways then orbits the target
## instead of sliding across the frame, and pushing back retreats from it rather
## than toward the lens. It is also why locked movement needs no second code path —
## `apply_movement` is unchanged and does not know a lock exists.
##
## The unlocked branch below is character-for-character what it always was. Both
## `right` expressions are mathematically the same vector for a yaw-only pivot, but
## the movement baseline is pinned to a physics frame, and re-deriving one from the
## other would be a floating-point change for no reason.
func camera_relative_input() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var cam_basis := camera_pivot.global_basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	if lockon.is_locked():
		forward = lockon.target_point() - global_position
		right = Vector3(-forward.z, 0.0, forward.x)
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var direction := (right * input_dir.x + forward * -input_dir.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	return direction


func _update_camera(delta: float) -> void:
	var locked := lockon.is_locked()

	# Right-stick look, unless the lock owns the camera — in which case the same
	# axis switches target instead. See `_tick_lockon_input`.
	if not locked:
		var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
		if look != Vector2.ZERO:
			_rotate_camera(-look.x * stick_sensitivity * delta, -look.y * stick_sensitivity * delta)

	var was_aiming := _shoulder > 0.001
	_shoulder = lerpf(_shoulder, camera_shoulder, 1.0 - exp(-aim_camera_speed * delta))
	_lock_blend = lerpf(
		_lock_blend, 1.0 if locked else 0.0, 1.0 - exp(-lockon_camera_speed * delta))

	# Lag the pivot toward the player instead of snapping to them. A lock lifts the
	# pivot and the aim rig raises it further and slides it sideways; with neither
	# engaged every added term is exactly zero (`lerpf(a, b, 0)` is `a`), so this is
	# the line it has always been and the movement baseline cannot move.
	var height := camera_target_height + lockon_pivot_lift * _lock_blend
	var offset := Vector3.UP * lerpf(height, aim_camera_height, _shoulder)
	if _shoulder > 0.001:
		var side := camera_pivot.global_basis.x
		side.y = 0.0
		offset += side.normalized() * (aim_camera_shoulder * _shoulder)
	camera_pivot_target = global_position + offset
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		camera_pivot_target, 1.0 - exp(-camera_follow_speed * delta)
	)

	if locked:
		_frame_lock_target(delta)
	elif camera_shoulder > 0.5 and _shoulder < 0.995:
		# Lift the lens as the shoulder rig arrives, then let go of it. See
		# `aim_camera_pitch_deg`. `elif`, because a lock already owns the pitch and
		# aiming at something you have Z-targeted should keep the target framed.
		spring_arm.rotation.x = lerpf(spring_arm.rotation.x,
			deg_to_rad(aim_camera_pitch_deg), 1.0 - exp(-aim_camera_speed * delta))

	# The spring is written ONLY while the aim rig is engaged, and put back once on
	# the way out. Writing it every frame would silently overwrite the
	# `camera_distance` a capture shot had set for itself.
	if _shoulder > 0.001:
		spring_arm.spring_length = lerpf(_spring_rest, aim_camera_distance, _shoulder)
	elif was_aiming:
		spring_arm.spring_length = _spring_rest

	# Widen the lens slightly with speed. Eases in faster than it eases out, so
	# starting to run feels punchy but stopping doesn't snap. Aiming narrows it
	# instead, which is the other half of getting a bow onto the screen.
	var ratio := clampf(get_horizontal_speed() / maxf(max_speed, 0.01), 0.0, 1.0)
	var wanted := lerpf(camera_fov + camera_fov_kick * ratio, aim_camera_fov, _shoulder)
	var rate := 4.0 if wanted > camera.fov else 2.5
	camera.fov = lerpf(camera.fov, wanted, 1.0 - exp(-rate * delta))


## The locked framing: yaw round behind the player onto the target, then solve the
## pitch that lands the target at (½ width, ¼ height).
##
## The pitch is the good idea here and it is worth being explicit about why it is
## not simply "point at the target". Pointing at the target centres it, which puts
## the player directly underneath it and the two overlap. Projecting the DESIRED
## SCREEN POSITION back into the world at the target's depth and solving for the
## pitch that would put it there leaves the target high and the player low, with the
## volume between them — the volume a fight happens in — open. Zelda's Z-target
## composition, and Snaiel's implementation of it; PRIOR-ART-VISUAL.md quotes the
## original.
##
## Both channels use `1 - exp(-rate * delta)` rather than a bare weight. Every
## reference project uses the bare version and every one of them is framerate
## dependent (PRIOR-ART.md, "what to avoid" #1).
func _frame_lock_target(delta: float) -> void:
	var aim := lockon.target_point()
	var weight := 1.0 - exp(-lockon_camera_speed * delta)

	var flat := aim - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.0001:
		# The pivot looks down -basis.z, so a yaw of atan2(-x, -z) points it along
		# the player-to-target line. Wrapped, because lerp_angle can walk outside
		# ±PI and `_rotate_camera` assumes it does not.
		var wanted_yaw := atan2(-flat.x, -flat.z)
		camera_pivot.rotation.y = wrapf(
			lerp_angle(camera_pivot.rotation.y, wanted_yaw, weight), -PI, PI)

	var frame := Vector2(camera.get_viewport().get_visible_rect().size)
	var depth := camera.global_position.distance_to(aim)
	var desired := camera.project_position(
		Vector2(frame.x * 0.5, frame.y * lockon_target_screen_height), depth)
	# Increasing the arm's rotation.x tilts the view UP, which moves the image DOWN
	# the frame; so a target sitting above the desired point needs a positive
	# correction. Clamped to the same limits free look has, which is also the safety
	# net: a clamp can only ever move the target back toward the centre of frame.
	var wanted_pitch := clampf(
		spring_arm.rotation.x + atan2(aim.y - desired.y, maxf(depth, 0.01)),
		deg_to_rad(pitch_min_deg),
		deg_to_rad(pitch_max_deg))
	spring_arm.rotation.x = lerpf(spring_arm.rotation.x, wanted_pitch, weight)


func face_movement_direction(delta: float) -> void:
	# Locked, the character faces the TARGET however it is travelling — which is what
	# makes a sidestep read as circling rather than as walking away. Handled here
	# rather than in the locomotion states so all three of Idle, Move and Air inherit
	# it without a branch each.
	if lockon.is_locked():
		var to := lockon.target_point() - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			rig.rotation.y = lerp_angle(
				rig.rotation.y, atan2(to.x, to.z), lockon_turn_speed * delta)
		return

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.01:
		return
	var target_yaw := atan2(horizontal.x, horizontal.z)
	rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, turn_speed * delta)


# --- Verbs the attack state calls ----------------------------------------

## A swing commits your facing. Snapping to the stick on frame one reads as
## decisive; turning through the swing reads as mush.
##
## WITH A TARGET, the swing turns to the target instead — even with no stick input
## at all, which the unlocked version could not do. That is God of War 2018's
## systemic answer to actions the camera cannot see, quoted in PRIOR-ART-VISUAL.md:
## *"if Kratos has a target, all of his attacks are automatically rotated to face
## them"*. It matters here because the camera, while locked, is also looking down
## the player-to-target line — so the arc is presented the same way every time
## instead of wherever the stick happened to be pointing, and the volume it sweeps
## through is the one the framing has deliberately left open.
func snap_facing_to_input() -> void:
	if lockon.is_locked():
		var to := lockon.target_point() - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			rig.rotation.y = atan2(to.x, to.z)
			return

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


## Start one swing: clear the previous swing's windows, arm the step's damage, and play
## its clip from the first frame at whatever rate makes the step's timing true.
##
## The rate is the whole of how a heavy weapon works. Windows are method-track keyframes
## and method tracks fire on clip time, so playing `slash_a` at 0.625x moves the wind-up,
## the live window and the commitment out together in proportion — see
## items/attack_step.gd. Nothing here knows which weapon it is; it knows a step.
func begin_attack(step: AttackStep, heavy: bool) -> void:
	_attack_started += 1
	_attack_clip = step.clip
	attack_can_cancel = false
	attack_finished = false
	attack_hitbox_active = false
	var scale := 1.0
	var anim := anim_player.get_animation(step.clip)
	if anim != null:
		scale = step.clip_scale(AttackStep.authored_windup_frames(anim))
		attack_clip_duration = anim.length / maxf(scale, 0.01)
	if weapon_hitbox != null:
		weapon_hitbox.end_swing()
		# The STEP's actions, not the weapon's, which is what lets a chain's finisher hit
		# harder than its opener with no code to say so.
		weapon_hitbox.actions = step.actions
	# The ribbon and the hot blade open HERE, on the frame the swing is committed,
	# and not on the clip's `_anim_trail_on` key three frames later. A critic could
	# only find the wind-up frame by comparing it against its paired idle — "a
	# forearm raised one body-width with no flash, no trail, no ground mark and no
	# change in stance is not enough at speed" — and no method track can help,
	# because the earliest one can fire is a frame after the clip starts. The trail
	# opens narrow (SwordTrail.bloom_from) so the wind-up carries an outlined shape
	# attached to the blade rather than a band that says the swing already happened.
	# SwordTrail.start() is guarded, so the clip's key is now a harmless no-op.
	sword_trail.start()
	_blade_hot = true
	_refresh_blade_look()
	play_anim(step.clip, scale, true)
	_play_blade(sfx_swing_heavy if heavy else sfx_swing, -5.0)


func end_attack() -> void:
	attack_hitbox_active = false
	attack_can_cancel = false
	attack_finished = false
	_blade_hot = false
	if weapon_hitbox != null:
		weapon_hitbox.end_swing()
	# Stopped, not cleared: leaving the attack state lets the arc fade out on its
	# own, exactly as finishing a swing does. Yanking the ribbon here would make
	# every cancel look like a rendering glitch.
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
	if weapon_hitbox != null:
		weapon_hitbox.begin_swing()
	_refresh_blade_look()


func _anim_hitbox_off() -> void:
	attack_hitbox_active = false
	if weapon_hitbox != null:
		weapon_hitbox.end_swing()
	_refresh_blade_look()


## The ribbon is deliberately NOT tied to the hitbox window. The live window is
## 100 ms, but the readable part of a swing is the whole arc either side of it, so
## the clip closes the trail several frames after the hitbox. Keeping them separate
## means the arc can be made more legible without touching a measured gameplay
## number.
##
## Opening it, though, is no longer this key's job — begin_attack does it on the
## frame the swing is committed, because the earliest a method track can fire is
## already a frame too late for the wind-up. SwordTrail.start() is guarded against
## restarting, so this remains harmless and the clip keeps documenting the window.
func _anim_trail_on() -> void:
	sword_trail.start()
	_blade_hot = true
	_refresh_blade_look()


func _anim_trail_off() -> void:
	sword_trail.stop()
	_blade_hot = false
	_refresh_blade_look()


func _anim_allow_cancel() -> void:
	attack_can_cancel = true


## `clip` is the clip that owns the keyframe, and the check is not defensive
## paranoia. Chaining the combo cross-fades the previous clip out over 0.06 s, and
## a fading clip still advances and still fires its method keys — so slash_a's end
## key arrived two frames into slash_b and ended the follow-up on the spot. The
## clip then played out anyway, arming and disarming the hitbox from inside Idle,
## with no commitment and no cancel window. Every probe number still passed; only
## capture.gd printing the live state caught it.
func _anim_attack_finished(clip: String = "") -> void:
	if clip != "" and StringName(clip) != _attack_clip:
		return
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
		# The charge's POSE. Charging runs inside the Idle state, so before this the
		# charged pose WAS the idle pose and the only difference between "about to
		# unleash a spin" and "standing there" was a tint on a thirty-pixel blade.
		# Gated on standing still, not merely on being charged: a coiled
		# anticipation pose sliding across the ground on a walk cycle's feet is a
		# worse read than no pose change at all.
		if _charged and speed <= walk_anim_threshold:
			wanted = "charge"
		elif _spin_requested and _state_machine.get_current_node() == &"charge":
			# The charge has just been released and the Attack state will accept it in
			# this same tick, travelling to the spin's own clip. Travelling to `idle`
			# first is two travel() calls in one frame, and the AnimationTree pays for
			# that with two extra frames before the new clip's first method key fires:
			# measured, it moved spin_windup from 167 ms to 200 ms. Leave the machine
			# where it is and let begin_attack take it from `charge`.
			return
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
	# `hot_mesh` is whichever mesh the equipped weapon nominates — the sword's blade, the
	# axe's head edge — and it is null for a shield, which has no hot part at all.
	if hot_mesh != null:
		if _charged:
			hot_mesh.material_override = blade_charged_material
		elif _blade_hot or attack_hitbox_active:
			hot_mesh.material_override = blade_live_material
		else:
			hot_mesh.material_override = hot_mesh_rest
	if charge_glow != null:
		charge_glow.visible = _charged
	# The ring is the half of the charge tell that has EDGES. The light wash and the
	# cyan blade are both value-only cues, and a critic reading a charged frame
	# beside its idle said that without the wash it would have called the frame IDLE
	# with full confidence and been wrong. See charge_ring.gd.
	if charge_ring != null:
		if _charged:
			charge_ring.begin()
		else:
			charge_ring.stop()


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
	# F4 cycles the loadout, and it is not just a convenience. tools/capture.tscn can only
	# reach the game through InputMap actions, so without an input that changes what is in
	# your hand there is no way to photograph the axe, the bow or the shield at the
	# gameplay camera — and Rule 3 says a look is judged by looking at it.
	if Input.is_action_just_pressed("cycle_item"):
		loadout.cycle()


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
	return weapon_hitbox != null and weapon_hitbox.monitoring


## Increments the moment a swing is accepted and its clip starts. The probe reads
## this to time commitment, rather than inferring it from elapsed time.
func get_attack_start_count() -> int:
	return _attack_started


## Increments once per armed hitbox window — the per-swing instance counter the
## multi-hit guard keys off.
func get_attack_swing_id() -> int:
	return weapon_hitbox.get_swing_id() if weapon_hitbox != null else 0


func is_attack_charged() -> bool:
	return _charged


## 0 to 1 across the charge, for a HUD tell later.
func get_charge_ratio() -> float:
	return clampf(_charge_timer / maxf(charge_time, 0.001), 0.0, 1.0)
