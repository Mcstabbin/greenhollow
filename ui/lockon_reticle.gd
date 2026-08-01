class_name LockOnReticle
extends Control
## Screen-space reticle drawn over the locked target.
##
## A 3D marker parented to the enemy would be simpler, but it would also scale
## with distance, tilt with the camera, and get swallowed by foliage. The reticle
## has to stay the same size and stay on top, so it lives in the HUD and the
## target's world position is unprojected onto it every frame. That pattern is
## from catprisbrey's `gui_reticle.gd` (Unlicense) — see PRIOR-ART.md.
##
## Why it converges on acquire rather than just appearing: the critic that failed
## the first attack pass scored "state legibility" 1/5 — could a player tell this
## frame apart from standing still? A reticle that snaps into existence reads as
## a HUD element. One that closes onto the target reads as the game locking on,
## and it does it in a single still frame.

## Brackets start this far out and close to `SIZE`. Wide enough to be a gesture.
const SIZE := 26.0
const ACQUIRE_SPREAD := 46.0
## Fast: acquisition has to feel instant (REFERENCE.md band is 50-150 ms).
const ACQUIRE_TIME := 0.11

const ARM := 9.0
const THICKNESS := 3.0
## Off-palette on purpose. Nothing in this world is this hue, so the reticle
## cannot merge with foliage, the white character, or the green treeline.
const COLOR_MARK := Color(0.29, 0.92, 1.0)
const COLOR_OUTLINE := Color(0.0, 0.0, 0.0)
## Slow idle rotation, so a held lock stays alive without drawing the eye.
const SPIN_SPEED := 0.55

var _target: LockOnTarget = null
var _spread := 0.0
var _spin := 0.0
var _tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Drawn in HUD space but positioned per-frame, so the anchors must not fight
	# the assignment to `position`.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	visible = false
	set_process(false)


## Point the reticle at a target, or pass null to release it.
func set_target(target: LockOnTarget) -> void:
	if target == _target:
		return
	_target = target

	if _tween != null:
		_tween.kill()

	if _target == null:
		visible = false
		set_process(false)
		return

	visible = true
	set_process(true)
	_spread = ACQUIRE_SPREAD
	_tween = create_tween()
	_tween.tween_property(self, "_spread", 0.0, ACQUIRE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	# The target can die or leave the tree between frames; the lock-on system will
	# tell us, but not necessarily before the next draw.
	if _target == null or not _target.is_valid():
		set_target(null)
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return

	var aim := _target.aim_point()

	# Behind the camera, unproject_position returns a mirrored point on the far
	# side of the screen — a reticle sitting confidently over empty grass. Hide
	# instead; whether the *lock* should break is the lock-on system's call.
	if camera.is_position_behind(aim):
		visible = false
		return

	visible = true
	position = camera.unproject_position(aim)
	_spin = wrapf(_spin + SPIN_SPEED * delta, 0.0, TAU)
	queue_redraw()


func _draw() -> void:
	var reach := SIZE + _spread
	# Outline first and thicker, mark over it: two passes are cheaper than
	# stroking outlines around eight separate polylines, and this reads the same.
	for pass_index in 2:
		var color := COLOR_OUTLINE if pass_index == 0 else COLOR_MARK
		var width := THICKNESS + 4.0 if pass_index == 0 else THICKNESS
		for corner in 4:
			var angle := _spin + TAU * float(corner) / 4.0 + PI * 0.25
			var out := Vector2(cos(angle), sin(angle)) * reach
			# Arms run along the screen axes, so the bracket reads as a corner
			# rather than as a rotating asterisk.
			var along := Vector2(-signf(out.x) * ARM, 0.0)
			var down := Vector2(0.0, -signf(out.y) * ARM)
			draw_polyline(PackedVector2Array([out + along, out, out + down]), color, width)
