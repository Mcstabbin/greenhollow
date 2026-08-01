class_name SpinRing
extends MeshInstance3D
## The spin attack's ground read: one flat ring that expands outward across the
## live window and fades.
##
## It replaces a pale OmniLight wash on the grass, which a fresh critic described
## as "so low-contrast against the grass that I checked twice to confirm it was
## intentional". A light cannot win against a bright green unshaded ground; a
## saturated cyan unshaded ring can, and it costs one 24-segment torus.
##
## Fired by the spin clip's `_anim_spin_ring` method track, so its timing lives
## beside the animation it has to match (tools/build_combat_anims.gd), exactly
## like the hitbox and cancel windows.

## Ring radius at the start and end of the flash, in metres. The end radius is
## deliberately a little wider than the blade's own reach — the ring is the
## threat's footprint, not a tracing of the sword.
@export var radius_from: float = 0.5
@export var radius_to: float = 2.9
## Seconds the flash lasts. Matched to the spin's live window, not to the whole
## clip, so it is gone before the recovery pose.
@export var duration: float = 0.34
## How flat the ring sits. The mesh is a torus; squashing it in Y turns the tube
## into a band lying on the ground.
@export var flatten: float = 0.35

var _time := -1.0
var _material: StandardMaterial3D


func _ready() -> void:
	visible = false
	# Its own copy, because the alpha is animated per-instance.
	var source := get_active_material(0)
	if source != null:
		_material = source.duplicate() as StandardMaterial3D
		material_override = _material


func flash() -> void:
	_time = 0.0
	visible = true
	_apply(0.0)


func stop() -> void:
	_time = -1.0
	visible = false


func _process(delta: float) -> void:
	if _time < 0.0:
		return
	_time += delta
	var u := _time / maxf(duration, 0.001)
	if u >= 1.0:
		stop()
		return
	_apply(u)


func _apply(u: float) -> void:
	# Ease out: fast expansion on the first frames is what reads as a shockwave.
	var eased := 1.0 - pow(1.0 - u, 2.2)
	var r: float = lerpf(radius_from, radius_to, eased)
	# The mesh is authored at radius 1, so scale IS radius. Y is NOT scaled with
	# it — the band has to stay flat on the grass as the ring widens.
	scale = Vector3(r, flatten, r)
	if _material != null:
		var c := _material.albedo_color
		# Hold full opacity for the first third, then fall away.
		c.a = clampf(1.0 - maxf(0.0, u - 0.3) / 0.7, 0.0, 1.0)
		_material.albedo_color = c
