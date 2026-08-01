shader_type spatial;
// Wind sway for leaves and grass.
//
// Applied only to foliage surfaces, never bark, so trunks stay planted while
// their canopies move. Sway scales with local height, so the base of a grass
// tuft stays rooted and the tips travel furthest.
//
// Phase is derived from world position, so neighbouring plants are out of sync
// instead of the whole forest breathing as one organism.
//
// It also carries the VALUE RECESSION, which is the reason this shader is worth
// having on 509 materials. Measured across every `shader_parameter/albedo` in
// `greenhollow_clearing.tscn`: authored Rec.709 luminance median **0.691**, max
// 0.804, and **100%** of them brighter than the grass at 0.474. Every canopy in
// the game was lighter than the ground the fight happens on, so the background
// held the frame's top of value while the play field sat mid — the inversion of
// the rule that the focal point holds the contrast and the background recedes.
// Fixing it per-material would mean editing 509 colours in a hand-edited scene;
// three uniforms and a depth ramp here do it in one place, at a GPU cost measured
// inside run-to-run noise (10.37 ms either way over 3x600 frames at 640x480 —
// the scene is bound by its 1,591 draw calls, not by fragment maths).
//
// Dark depth fog was tried first and is the reason the ramp exists rather than a
// flat scale: fog only reaches the treeline on the angles where it happens to be
// far away. Measured, `spawn_north`'s treeline fell 0.694 -> 0.596 while
// `spawn_south`'s moved 0.701 -> 0.691, because on that angle the trees are
// inside 20 m. An intrinsic albedo problem needs an intrinsic term, so
// `value_near` applies everywhere and `value_far` is what depth adds on top.

render_mode diffuse_lambert_wrap, specular_disabled, cull_back;

uniform vec4 albedo : source_color = vec4(0.45, 0.76, 0.40, 1.0);
uniform float sway_strength : hint_range(0.0, 0.3) = 0.055;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.15;
/// Secondary faster, smaller motion so it doesn't read as a single sine.
uniform float flutter_strength : hint_range(0.0, 0.1) = 0.018;
uniform float flutter_speed : hint_range(0.0, 12.0) = 4.6;

// --- Value recession -------------------------------------------------------
// Linear multipliers on albedo, so a displayed (sRGB) factor is roughly
// value^(1/2.2). These are NOT `source_color`: they are scalars, and tagging
// them would put a second sRGB->linear conversion on numbers that are already
// linear.
//
// `value_near` is the flat term every foliage surface gets, including the tufts
// and bushes standing in the play field. Measured effect on the nearest canopies
// (`spawn_south`, the worst angle): rendered median 0.847 -> 0.541 against a lawn
// at 0.62, so in-field foliage sits just under the grass and reads as darker
// clumps on a lighter stage rather than as light-on-light.
uniform float value_near : hint_range(0.15, 1.0) = 0.38;
/// What the far treeline keeps. Its job is to sit clearly UNDER the play field.
uniform float value_far : hint_range(0.05, 1.0) = 0.28;
/// Chroma pulled out with distance. Value alone reads as "in shadow"; losing
/// saturation as well is what reads as "far away". The cool hue shift of real
/// aerial perspective is left to the Environment's depth fog, which already
/// supplies it for every material in the scene, not just this one.
uniform float desaturate_far : hint_range(0.0, 1.0) = 0.45;
// This ramp is 9-30 m where outline_post's is 12-40 m, and the difference is
// measured rather than sloppy. The clearing is a bowl whose rim is much closer on
// some headings than others: on `spawn_south` and `spawn_west` the canopies sit
// at 15-25 m, so a 12-40 m ramp gave them almost no recession — the band mean
// improved while the big near canopies stayed the lightest mass in frame. Pulling
// the ramp in to 9-30 m more than doubles what a 15 m tree collects (0.079 ->
// 0.198). 9 m still clears every near-field measurement (player 5.2-5.8 m, props
// 2-8 m), and `smoothstep` returns exactly 0 at or below its edge, so foliage
// inside the play field gets `value_near` and nothing else. The outline's ramp
// answers a different question — ink density per pixel — so the two are allowed
// to disagree.
uniform float recede_begin : hint_range(0.0, 80.0) = 9.0;
uniform float recede_end : hint_range(1.0, 200.0) = 30.0;

const vec3 REC709 = vec3(0.2126, 0.7152, 0.0722);

void vertex() {
	vec3 world = MODEL_MATRIX[3].xyz;
	float phase = world.x * 0.35 + world.z * 0.27;

	// Only sway above the origin: roots and trunk bases shouldn't slide.
	float h = max(VERTEX.y, 0.0);

	float sway = sin(TIME * sway_speed + phase) * sway_strength * h;
	float flutter = sin(TIME * flutter_speed + phase * 2.3 + VERTEX.y) * flutter_strength * h;

	VERTEX.x += sway + flutter;
	VERTEX.z += sway * 0.55 - flutter * 0.4;
}

void fragment() {
	// `-VERTEX.z` is view depth in metres — the same quantity outline_post
	// reconstructs from the depth buffer, so the two passes measure distance the
	// same way even though their thresholds differ (see recede_begin).
	float fade = smoothstep(recede_begin, recede_end, -VERTEX.z);

	vec3 tint = albedo.rgb;
	// Desaturate toward this pixel's own grey, not toward a fixed colour: mixing
	// every canopy toward one tint flattens the treeline into a single silhouette
	// and the individual trees stop being individual things.
	tint = mix(tint, vec3(dot(tint, REC709)), desaturate_far * fade);
	// Multiplicative, so the ratio between neighbouring canopies survives going
	// dark and the shapes keep reading. A lerp toward black would not.
	tint *= mix(value_near, value_far, fade);

	ALBEDO = tint;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
