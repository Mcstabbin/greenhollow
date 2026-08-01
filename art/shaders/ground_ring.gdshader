shader_type spatial;
// Flat ground ring for the charge tell and the spin's footprint. Two jobs a single
// albedo colour cannot do:
//
//  1. VALUE, not hue. A critic shown the charge frame called the tell quiet: "dark
//     teal ring on mid-green grass is low contrast". PRIOR-ART-VISUAL.md says why
//     nothing mid-value can work here — the tunic and the grass share both value
//     (0.49 / 0.47) and hue, so any effect sitting in that band disappears. The
//     answer from the same document is a bright core with a dark rim, which carries
//     its own contrast instead of borrowing it from the background. That is a ramp
//     ACROSS the band, so it needs the tube's radial coordinate, and a StandardMaterial
//     has no way to express it. Same three-band structure as sword_trail.gd, applied
//     radially rather than along a length.
//  2. BREAKING THE RING. The same critic said the ring "reads as a selection circle
//     or a targeting reticle rather than energy gathering", and an unbroken circle is
//     exactly what a reticle is. `segments` cuts it into arcs.
//  3. POINTING THE ARCS. Breaking the ring was not enough on its own, and the reason
//     is worth writing down: a later critic, asked whether each effect read as motion
//     or as an object, called the broken charge ring "a ring of paving slabs" and
//     "curved paving slabs / a small stone circle you are standing in", and the
//     unbroken spin ring "a tyre lying on the ground ... pale peach interior with a
//     dark brown outer rim — a trail does not have a lit inside face and a shaded rim".
//     Both readings come from the same thing: a constant-width band with square ends
//     is a physical object, whether it is one piece or seven. `arc_taper` pinches each
//     arc to a point at both of its ends, so an arc is a lens rather than a slab, and
//     the core/rim split is taken as a fraction of the LOCAL width so the dark rim
//     thins away with it instead of hooping round a solid shape. Same shape language
//     as sword_trail.gd, which does exactly this along its length.
//  4. ONE ARC, NOT FOUR OR FIVE — and `min_profile`, because a point is not a taper.
//     Note 3 solved "slab" and walked straight into "debris". A critic asked to bucket
//     each effect as SWEEP / FRAGMENT / OBJECT, and told not to split the difference,
//     called the multi-arc rings fragments in three separate frames: "four pale
//     crescents at different scales scattered around the feet ... they sit at ground
//     level while the sword is overhead, so they don't connect to the weapon at all",
//     and of the waterside spin, "the two on the river even look parallel-parked.
//     Direction is not implied — it just looks scattered." Meanwhile the two effects
//     that DID read as sweeps were both single connected shapes: "one broad ribbon that
//     starts at the glowing blade ... the attachment to the sword is what sells it".
//     So `segments` is 1 on both materials now. The charge tell is one near-closed arc,
//     which is a ring with a start and an end rather than a reticle; the spin's is one
//     open arc, aimed at the blade by spin_ring.gd so the ground mark is the sweep's
//     consequence rather than a second unrelated object.
//     `min_profile` is the other half. `arc_taper` narrows an arc to literally zero
//     width, and the last few degrees of that are a sub-pixel hairline which the
//     outline pass still contours — the "detached black ticks, 2-4 px dashes floating
//     on the background" a critic found at the tapered ends. The arc now STOPS while it
//     is still a few pixels wide. A short terminal edge under a black contour reads as
//     a point; a hairline reads as dropped geometry.
//  5. THE BRIGHT BAND SITS ON THE OUTER EDGE, not down the middle. Same critic, same
//     round: "the chest piece is unmistakably a canoe hull seen from inside", and of the
//     ring, "pale peach interior with a dark brown outer rim". Both are the same
//     structure — a light band with dark on BOTH sides is what a lit, curved inside
//     face looks like, so a three-band ramp arranged symmetrically about the centre
//     builds interior volume no matter what the colours are. The radial coordinate is
//     therefore signed now, and the core runs from the outer edge inward with the rim
//     behind it only. sword_trail.gd's BAND_STOPS carry the same change along the width.
//
// Deliberately NOT transparent. art/shaders/outline_post reads the depth and
// normal-roughness buffers, which Godot fills before the transparent pass, so a
// transparent ring can never carry the black contour every other object here has —
// and in this world an un-contoured shape reads as a rendering fault. ALPHA_SCISSOR
// keeps it in the opaque pass, so the arcs write depth and each one is contoured
// individually, including across the gaps.
//
// No emission, no glow: the Environment has no glow pass and Linear tonemapping, so
// anything above 1.0 clips flat and additive over a 0.91-value sky horizon is
// arithmetically invisible. The brightness here is albedo and nothing else.

render_mode unshaded, cull_disabled, shadows_disabled, ambient_light_disabled,
	depth_draw_opaque, fog_disabled;

/// The bright middle of the band. Keep it well clear of grass (0.47 luminance) —
/// this is the half of the tell that carries the value contrast.
uniform vec4 core_colour : source_color = vec4(0.86, 1.0, 1.0, 1.0);
/// The dark edges. Riot's guide: "adding a dark background manually can help to
/// promote the effect", and avoid 0% and 100%.
uniform vec4 rim_colour : source_color = vec4(0.03, 0.16, 0.22, 1.0);
/// Geometry of the TorusMesh this is painted on, in the mesh's own units: the radius
/// of the tube's centre circle, i.e. (inner_radius + outer_radius) / 2, and the tube
/// radius, (outer_radius - inner_radius) / 2. Object space, so the script's scale
/// does not enter into it.
uniform float ring_radius = 0.84;
uniform float tube_radius = 0.16;
/// Fraction of the band's LOCAL width that is core, taken from the OUTER edge inward.
/// The remainder is rim, and all of it sits behind the core rather than wrapping round
/// it — see note 5. 0.5 puts the boundary on the tube's centre circle.
uniform float core_width : hint_range(0.0, 1.0) = 0.5;
/// How many arcs the ring is cut into. 1 leaves it whole. Keep it at 1: see note 4.
uniform float segments = 1.0;
/// How much of each arc's slot is filled. 1.0 leaves no gaps whatever `segments` is.
uniform float segment_fill : hint_range(0.05, 1.0) = 1.0;
/// How strongly each arc narrows toward its own two ends. 0 is the old square-ended
/// band; 1 is a lens that reaches full width only at its middle. See note 3.
uniform float arc_taper : hint_range(0.0, 1.0) = 1.0;
/// The width, as a fraction of the tube, at which an arc stops instead of carrying on
/// to a sub-pixel point. See note 4 — this is the fix for detached black ticks at the
/// tapered ends, and it only does anything while `arc_taper` is above 0.
uniform float min_profile : hint_range(0.0, 0.9) = 0.0;

/// Object space, because `VERTEX` in fragment() is view space and both the radial
/// ramp and the arc gaps have to be fixed to the mesh.
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	// Gaps. `segments` integral keeps the atan seam at ±PI on an arc boundary, so the
	// wrap never shows up as one odd-sized arc.
	float slot = fract((atan(obj.z, obj.x) / TAU + 0.5) * segments);

	// Radial position across the band, SIGNED: -1 at the inner edge, 0 on the tube's
	// centre circle, +1 at the outer edge. Signed rather than absolute because the
	// colour ramp below is one-sided — see note 5.
	float across = (length(obj.xz) - ring_radius) / tube_radius;

	// How wide this arc is allowed to be HERE. `along` runs 0 to 1 across the filled
	// part of one slot, so the profile pinches both of the arc's ends to a point. The
	// geometry is still a full torus; the scissor is what carves the lens out of it,
	// which keeps the whole thing in the opaque pass and therefore outlined.
	float along = clamp(slot / max(segment_fill, 0.001), 0.0, 1.0);
	float profile = mix(1.0, sin(PI * along), arc_taper);
	ALPHA = step(abs(across), profile)
		* step(min_profile, profile)
		* step(slot, segment_fill);
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// Core/rim split taken against the LOCAL width, so the rim stays a constant
	// fraction of whatever is left and thins away with the arc's points instead of
	// hooping round them as a hard outer shell. One-sided: core out to the outer edge,
	// rim behind it. A bright middle between two dark rims is an interior face.
	ALBEDO = mix(rim_colour.rgb, core_colour.rgb,
		step(profile * (1.0 - 2.0 * core_width), across));
}
