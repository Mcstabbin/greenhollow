class_name SpinRing
extends MeshInstance3D
## The spin attack's ground read: one flat ring that expands outward across the
## live window, then vanishes.
##
## It replaces a pale OmniLight wash on the grass, which a fresh critic described
## as "so low-contrast against the grass that I checked twice to confirm it was
## intentional". A light cannot win against a bright green unshaded ground; a
## saturated unshaded ring can, and it costs one 32-segment torus.
##
## Fired by the spin clip's `_anim_spin_ring` method track, so its timing lives
## beside the animation it has to match (tools/build_combat_anims.gd), exactly
## like the hitbox and cancel windows.
##
## The material is ALPHA_SCISSOR rather than ALPHA, and that is the whole reason
## this script no longer animates opacity. Godot fills the depth and
## normal-roughness buffers before the transparent pass, so a transparent ring can
## never be picked up by art/shaders/outline_post — and an un-contoured shape in a
## world where everything else carries a 1.3 px black contour reads as a rendering
## fault, not as an effect. Scissored, the ring is in the opaque pass and gets the
## same outline as the grass it sits on. The price is that opacity is now binary,
## so the ring holds full strength and then goes: which is what the reference
## material recommends anyway — trails and slash shapes read as punchy *because*
## they vanish rather than trailing off.
##
## The other price is that an opaque ring under TRANSPARENT water is a rendering
## fault, and that was found in a capture rather than reasoned about: the river erases
## the ring's fill while the outline pass still contours its depth, so the ring drew
## as black arcs around nothing on the water. `water_clearance` is the fix and
## water_line.gd carries the full diagnosis.

## Ring radius at the start and end of the flash, in metres. The end radius is
## deliberately a little wider than the blade's own reach — the ring is the
## threat's footprint, not a tracing of the sword.
@export var radius_from: float = 0.5
## 2.45 rather than 2.9. On the riverbank spin a critic found the effect "hangs in the
## air over the water, below the level of the bank, in contact with nothing", and a
## footprint wider than the ground the character is standing on is how that happens. The
## spin's blade tip reaches 2.1 m, so 2.45 still reads as wider than the sword.
@export var radius_to: float = 2.45
## Seconds the flash lasts. Matched to the spin's 300 ms live window plus the two
## frames of latency between the key and the hitbox, not to the whole clip, so it is
## gone before the recovery pose. Shortening this to 0.30 put the ring *just* outside
## the frame the capture set judges the spin on, which is how the number got checked.
@export var duration: float = 0.34
## How flat the ring sits. The mesh is a torus; squashing it in Y turns the tube
## into a band lying on the ground.
@export var flatten: float = 0.35
## Ease-out exponent. Fast expansion on the first frames is what reads as a
## shockwave rather than as a circle being scaled up.
@export var ease_power: float = 2.2
## How far above a water surface the ring is held when it would otherwise sweep
## underneath one. See water_line.gd for what goes wrong if it does not: an opaque
## ring under transparent water loses its fill to the water and keeps its outline,
## so it draws as black arcs around nothing and reads as the water being broken.
@export var water_clearance: float = 0.06

var _time := -1.0
## Resting height above the player's origin, so the water lift is applied on top of
## the authored offset rather than replacing it.
var _base_height := 0.0


func _ready() -> void:
	_base_height = position.y
	visible = false


func flash() -> void:
	_time = 0.0
	visible = true
	# Resolved once per flash, not per frame: the ring is a fixed 0.34 s and the
	# player barely moves inside it, and a height that changed mid-expansion would
	# read as the ring climbing. `radius_to` rather than the current radius, because
	# the ring must already be clear before it grows over the river.
	position.y = _base_height
	position.y += WaterLine.lift_over_water(self, radius_to, water_clearance)
	_apply(0.0)


func stop() -> void:
	_time = -1.0
	visible = false
	position.y = _base_height


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
	var eased := 1.0 - pow(1.0 - u, ease_power)
	var r: float = lerpf(radius_from, radius_to, eased)
	# The mesh is authored at radius 1, so scale IS radius. Y is NOT scaled with
	# it — the band has to stay flat on the grass as the ring widens.
	scale = Vector3(r, flatten, r)
