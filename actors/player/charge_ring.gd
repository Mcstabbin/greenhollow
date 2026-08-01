class_name ChargeRing
extends MeshInstance3D
## The charged-attack tell, on the ground: one hard-edged ring that closes inward
## onto the player when the charge threshold is crossed, and holds there for as
## long as the charge is held.
##
## Why it exists. A fresh critic shown a charged frame beside its paired idle
## called it the only low-confidence judgement in the set: "the character is
## standing in the exact idle pose; only the blade's colour and a ground glow
## changed. If the glow had been absent I would have called it IDLE with confidence
## 5 and been wrong." Charging happens inside the Idle state, so the pose was the
## idle pose, and a tint on a thirty-pixel blade is not a signal. The answer is a
## shape with edges, and a big one.
##
## Two engine facts shape the implementation, both already paid for in CLAUDE.md:
##
##  * NOT a `Decal`. Decals support no custom shader, are Forward+/Mobile only, and
##    apply through the *lighting* path — so an unshaded ground surface, which is
##    what this world is made of, very likely receives nothing at all. A flat
##    unshaded mesh is the supported way to mark ground here, and
##    art/materials/toon_shadow_blob.tres already does exactly this.
##  * ALPHA_SCISSOR, not ALPHA. The depth and normal-roughness buffers are filled
##    before the transparent pass, so a transparent ring can never be contoured by
##    art/shaders/outline_post — and an un-contoured shape reads as a rendering
##    fault in a world where every object carries a black outline. Scissored, the
##    ring sits in the opaque pass and is outlined like everything else. So there
##    is no opacity animation anywhere in this file: the ring converges, holds, and
##    is switched off.
##
## It CONVERGES rather than appearing. A marker that snaps on at full size reads as
## a HUD element; one that closes onto its target over about 110 ms reads as the
## game doing something, and says so in a single still frame — the same reason the
## lock-on reticle closes instead of popping.

## Radius at the moment the charge completes, and the radius it settles to, in
## metres. Starting wide and closing in is the convergence; the settled radius is
## a little outside the player capsule so the body never covers it.
@export var radius_from: float = 2.7
@export var radius_to: float = 1.35
## Seconds the close takes. REFERENCE.md's converge band is ~110 ms.
@export var converge_time: float = 0.11
## How flat the ring sits. The mesh is a torus; squashing it in Y turns the tube
## into a band lying on the ground.
@export var flatten: float = 0.32

var _time := -1.0


func _ready() -> void:
	visible = false


## Charge threshold crossed. Idempotent, because Player._refresh_blade_look is
## called on more than just the frame the charge completes and must not restart
## the convergence every time.
func begin() -> void:
	if _time >= 0.0:
		return
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
	_apply(clampf(_time / maxf(converge_time, 0.001), 0.0, 1.0))


func _apply(u: float) -> void:
	# Ease out, so the ring decelerates into its resting radius instead of
	# arriving at full speed and stopping dead.
	var eased := 1.0 - pow(1.0 - u, 2.0)
	var r: float = lerpf(radius_from, radius_to, eased)
	# The mesh is authored at radius 1, so scale IS radius. Y is NOT scaled with
	# it — the band has to stay flat on the grass however wide the ring is.
	scale = Vector3(r, flatten, r)
