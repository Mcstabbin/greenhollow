class_name WaterLine
extends RefCounted
## Where the surface of standing water is, for opaque effects that must not pass
## under it.
##
## This exists because of one measured rendering fault, and the mechanism is worth
## stating in full because it will bite anything else that goes near the river.
##
## A critic looking at a spin-attack frame taken at the water's edge reported "three
## or four thin black concentric arcs on the water surface with nothing inside them"
## and said it read as the water being broken. It was the spin ring, and the cause is
## the interaction of two decisions that are each correct on their own:
##
##  * The ring is OPAQUE (ALPHA_SCISSOR), because art/shaders/outline_post reads the
##    depth and normal-roughness buffers, which Godot fills BEFORE the transparent
##    pass — so a transparent ring could never carry the black contour every other
##    object in this world has. The ring therefore writes depth.
##  * art/shaders/water.gdshader is `blend_mix`, i.e. genuinely transparent, so it
##    does NOT write depth but does paint over whatever is behind it at 72-92%
##    opacity.
##
## Put an opaque effect under the water and you get the worst of both: the water
## erases its fill, while the outline pass — reading the pre-transparent depth
## buffer, where the effect is the nearest surface — still finds its silhouette and
## draws a contour. A contour around nothing. Confirmed by freezing the frame and
## hiding one candidate node at a time: with the ring hidden all four arcs vanish and
## nothing else in the frame changes.
##
## Fixing it at the water does not work, and this was measured too: adding
## `depth_prepass_alpha` to the water shader, which should place the surface in the
## depth buffer ahead of the transparent pass, changed 2,930 pixels of a 640x480
## frame — all of them ripple phase — and left every arc exactly where it was.
##
## So the effect has to stay above the waterline, and the number cannot be a
## constant: the bank at the forced-choice spot sits 0.36 m BELOW the river surface,
## so an effect pinned to the player's feet is submerged while the player is stood on
## dry ground. Hence a query rather than a literal.
##
## Water surfaces announce themselves through the `water_surface` group, so this
## knows nothing about the level and the level knows nothing about the player.

## Group any mesh whose top face is a water surface belongs to.
const GROUP := "water_surface"


## How far `node` must rise for its plane to clear every water surface it overlaps,
## in metres, or 0.0 if it is already clear.
##
## `footprint_radius` is the effect's widest horizontal extent, tested against each
## surface's own AABB — an effect nowhere near the river must not be lifted, and one
## that will grow over it must be lifted before it starts rather than mid-flight.
static func lift_over_water(node: Node3D, footprint_radius: float, clearance: float) -> float:
	if node == null or not node.is_inside_tree():
		return 0.0
	var here := node.global_position
	var lift := 0.0
	for water_v in node.get_tree().get_nodes_in_group(GROUP):
		var water := water_v as VisualInstance3D
		if water == null or not water.is_visible_in_tree():
			continue
		var box := water.global_transform * water.get_aabb()
		if here.x + footprint_radius < box.position.x \
				or here.x - footprint_radius > box.end.x \
				or here.z + footprint_radius < box.position.z \
				or here.z - footprint_radius > box.end.z:
			continue
		lift = maxf(lift, box.end.y + clearance - here.y)
	return lift
