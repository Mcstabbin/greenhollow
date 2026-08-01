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
/// Fraction of the band's half-width that stays core. The remainder is rim, split
/// between the inner and outer edge.
uniform float core_width : hint_range(0.0, 1.0) = 0.5;
/// How many arcs the ring is cut into. 1 leaves it whole.
uniform float segments = 1.0;
/// How much of each arc's slot is filled. 1.0 leaves no gaps whatever `segments` is.
uniform float segment_fill : hint_range(0.05, 1.0) = 1.0;

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
	ALPHA = step(slot, segment_fill);
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// Radial position across the band: 0 at the tube's centre circle, 1 at either
	// edge. Hard step, not a gradient — a soft ramp beside a 1.3 px hard contour
	// reads as a rendering error.
	float across = abs(length(obj.xz) - ring_radius) / tube_radius;
	ALBEDO = mix(core_colour.rgb, rim_colour.rgb, step(core_width, across));
}
