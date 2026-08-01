class_name SwordTrail
extends MeshInstance3D
## The ribbon the blade leaves through a swing.
##
## Why it exists: with a ~0.8 m blade on a 2.2 m character at the default 5.5 m
## camera distance, a still frame of a swing shows a short pale stick somewhere
## near a limb. The motion is real — the tip covers about 180 degrees in 100 ms —
## but a still frame cannot show motion, and neither can a player's eye at that
## speed. The trail is what turns six frames of arm rotation into a legible arc,
## and it is the cheapest possible version of it: one ImmediateMesh, no particles,
## no shader, nothing the integrated-graphics target will notice. The docs call
## rebuilding an ImmediateMesh every frame its intended use, and a few hundred
## verts is noise — do NOT optimise the rebuild.
##
## Built as a world-space ribbon (`top_level`) rather than a child transform,
## because the whole point is that the older samples must NOT follow the arm.
##
## Six things here are corrections, not preferences. A critic found each one.
##
##  1. OPAQUE, NOT TRANSPARENT. Godot fills the depth and normal-roughness
##     buffers *before* the transparent pass, and art/shaders/outline_post reads
##     only those, so a `transparency = ALPHA` material can never be outlined —
##     not at any setting. In a world where every object carries a 1.3 px black
##     contour, the one un-contoured shape reads as a rendering error, which is
##     precisely what a critic said of the old ribbon, unprompted: "could be
##     mistaken for a lighting artefact". player.tscn's `StandardMaterial3D_trail`
##     is now ALPHA_SCISSOR, which stays in the opaque pass, writes depth, and
##     inherits the same contour as everything else. The consequence for this
##     script is that **vertex alpha must stay at 1.0**: partial alpha under a
##     scissor either pops off at the threshold, and under a hash would dither the
##     depth buffer and make the outline pass emit black speckle. So every fade
##     here is geometric or tonal, never alpha.
##  2. HUE. A white blade leaving a white trail across a white torso is invisible.
##     The ribbon is hot orange. Greenhollow is green grass, green canopy, white
##     torso and pale blue sky and water — every one of those is either green or a
##     cool desaturated tint, so orange is the only hue in the wheel that nothing
##     here competes with. Cyan was tried first and lost against the pale sky.
##  3. THREE BANDS, and the outer one is dark. A bright-only effect *borrows* its
##     contrast from the background and dies against a bright one; bright core plus
##     dark edge *carries* its own. Riot's VFX guide states it outright, and the
##     same ramp turns up in every good slash shader. See BAND_STOPS: a near-white
##     core at the leading edge over about 18% of the width, a saturated amber
##     body, and near-black rims. Judge it against grass, against sky, and in
##     greyscale.
##  4. LENGTH. The old ribbon held 20 ticks of history and then faded for 14 more,
##     so a point stayed on screen for 34 frames — it was still dissipating during
##     the next input window. The band is 10-18 frames (0.17-0.30 s); see
##     `history_ticks`.
##  5. SHAPE, not facets. Per-tick sampling of a tip that covers 180 degrees in
##     100 ms yields about 0.6 m of travel per sample, i.e. a six-sided polygon
##     rather than an arc. Fixed the way every mature trail fixes it:
##     distance-gated insertion with interpolated in-between points, then
##     Laplacian smoothing, then a width `Curve` so the thing tapers into a
##     crescent instead of staying a parallelogram.
##  6. A CRESCENT, NOT A FAN — and this is the correction that made the opaque
##     ribbon stop reading as a prop. Going opaque (1) fixed "reads as a lighting
##     artefact" and overshot straight into the opposite failure: a critic scoring
##     12/12 on the same set still said the arc "reads as geometry, not as an
##     effect ... at a still frame the arc looks like a physical prop the character
##     is holding: a cone, a sail, a wedge of cheese, a saucer", and ranked the spin
##     frame maximum screen area, minimum clarity. Alpha is not available as the
##     answer — `transparency = 1` puts the ribbon back where the outline pass
##     cannot see it — so the falloff is geometric:
##       * The ribbon's OUTER edge is fixed one `outer_reach` past the tip and the
##         width is taken INWARD from it, rather than the old symmetric spread about
##         the blade's midpoint. So the ribbon narrows onto the leading arc, and the
##         middle of a swept disc stays EMPTY. For the spin, whose ribbon wraps more
##         than a full revolution, that is the whole difference between a filled
##         saucer and an annulus: the bridge is visible through the hole, and a ring
##         of motion around the character cannot be mistaken for a held object.
##       * The tail therefore also stops reaching the grip. The old ribbon ran from
##         past-the-hand to past-the-tip along its entire length, so its near end
##         terminated in a hard edge at the hand — visible in captures as a ragged
##         black mass at the character's waist. Now only the newest cross-sections
##         reach the hand at all, so the ribbon emerges FROM the blade.
##       * `gap_centres` breaks the older part of the ribbon into separating slivers.
##         Gaps imply motion in a way a continuous sheet cannot, they cost area, and
##         each sliver is its own opaque shape so each one gets its own contour.
##         Only the trailing 60% is broken; the leading edge stays continuous,
##         because that is the part that says which way the blade is going.
##     Measured rather than eyeballed: the ribbon's screen footprint, counted by
##     capturing one frozen frame with the trail shown and hidden and differencing the
##     two, is 14% smaller than the old fan on the spin and 12% smaller on a slash. The
##     honest reading of that number is that this change is about DISTRIBUTION, not
##     ink — same order of coverage, arranged as a hollow broken ring instead of a
##     filled sheet.

## The blade's inner and outer ends. Sampled every tick; the quad between two
## consecutive samples is one segment of the ribbon.
@export var blade_base: Node3D
@export var blade_tip: Node3D
## How many ticks of blade travel the ribbon holds. This is the *smear length*,
## and it is the number the 10-18 frame band applies to: a point inserted now is
## dropped this many ticks later. 12 at 60 Hz is 200 ms, mid-band.
##
## It is a count of TICKS, not of points, because insertion is distance-gated —
## a fast part of the swing inserts several points in one tick and a slow part
## inserts none, so counting points would make the ribbon's length depend on how
## hard the blade happened to be moving.
@export var history_ticks: float = 12.0
## Where the ribbon's OUTER edge sits, past the blade tip, in blade lengths. This
## is the leading arc — the boundary furthest from the body and first into the
## space the blade is about to occupy — and it is deliberately the one edge that
## does NOT move: the crescent opens and closes by sliding its inner edge, so the
## silhouette a player tracks stays put.
@export var outer_reach: float = 0.75
## Where the ribbon's inner edge sits at its widest (newest) cross-section, past
## the hand, in blade lengths. Small: it only has to cover the grip so the ribbon
## looks like it comes off the blade. Everything older narrows away from it.
##
## The pair (0.75, 0.05) rather than (0.55, 0.20) is a deliberate trade at constant
## width — the band spans 1.8 blade lengths either way, but it sits 0.2 of a blade
## further out from the body. That is worth having, because the only screen space the
## camera does not have to look THROUGH the character to reach is outside the shoulders
## and above the head, so the outermost part of the ribbon is the part that escapes both
## the silhouette and the props. On slash_b's first live frame beside a chest — the
## frame a critic said "the signpost eats the arc" of — the shift is the difference
## between no visible arc and one clearly outside the head.
@export var inner_reach: float = 0.05
## Ticks the finished ribbon takes to narrow away to nothing once sampling stops.
## Geometric, not alpha — see the note on the opaque pipeline above. Ageing keeps
## running through the fade, so the ribbon shortens from the tail at the same time
## as it thins, which is what a dissipating smear does.
@export var fade_ticks: int = 6
## Distance gate. A point is only inserted once the blade has travelled this far
## since the last one, and if it has travelled further, that many interpolated
## points go in at once. 1 / resolution, in metres.
@export var point_spacing: float = 0.13
## Ceiling on points inserted in a single tick, so a teleport cannot spike.
@export var max_insert: int = 8
## Laplacian smoothing of the sampled spine, applied to a throwaway copy at
## rebuild time rather than to the stored samples — running it in place would
## compound every tick and creep the whole arc toward a straight line.
## Subdividing a chord adds vertices but no curvature; this is the pass that
## actually turns the faceted polygon into an arc.
@export var smooth_passes: int = 4
@export_range(0.0, 1.0) var smooth_strength: float = 0.5
## Width against age along the ribbon: 0 is the oldest sample, 1 the newest, and
## the value is the fraction of the full `inner_reach + 1 + outer_reach` span that
## is open at that point. Without it the ribbon is a parallelogram. Authored in
## player.tscn.
@export var width_curve: Curve
## Where along the ribbon the trailing slivers separate, as a fraction from the
## tail. Only the older part is broken; see note 6 in the header.
@export var gap_centres: PackedFloat32Array = PackedFloat32Array([0.13, 0.33, 0.53])
## How wide each of those gaps is, in the same fraction-of-length units. 0.06 of a
## ribbon that spans roughly a third of the frame is on the order of a dozen pixels at
## 640 px — enough to read as a gap, not enough to look like dropped geometry. 0.07 was
## tried and cost the frames a prop already eats; see the width curve in player.tscn.
@export var gap_width: float = 0.06
## The wind-up. A critic could only find the wind-up frame by comparing it against
## its paired idle — "a forearm raised one body-width with no flash, no trail, no
## ground mark and no change in stance is not enough at speed". So the ribbon now
## opens on the frame the swing is committed (Player.begin_attack) rather than on a
## keyframe three frames in, and for the first few ticks it is deliberately narrow:
## the blade already has an outlined shape attached to it, and that shape blooms
## into the arc. A full-width band on frame one would read as a swing that had
## already happened.
@export var bloom_ticks: float = 5.0
@export_range(0.0, 1.0) var bloom_from: float = 0.70
## The three bands. `tint_edge` is the load-bearing one: it is what lets the shape
## survive against the 0.91-value sky horizon and the white torso.
@export var tint_core: Color = Color(0.99, 0.95, 0.84, 1.0)
@export var tint_mid: Color = Color(1.0, 0.44, 0.04, 1.0)
@export var tint_edge: Color = Color(0.16, 0.05, 0.02, 1.0)

## Cross-section stops, as a fraction of the ribbon's width from the inner (hand)
## edge to the outer (past-tip) edge, and the flat role of the band between each
## consecutive pair. Emitting one triangle strip per band with duplicated boundary
## vertices keeps every band a flat colour, which is the whole art direction — a
## smooth gradient beside a 1.3 px hard contour reads as a rendering error.
##
## The core sits at 0.68-0.86, i.e. 18% of the width on the tip side, because that
## is the leading edge of the swept shape — the part furthest from the body and
## first into the space the blade is about to occupy.
const BAND_STOPS: Array[float] = [0.0, 0.05, 0.68, 0.86, 0.95, 1.0]
const ROLE_EDGE := 0
const ROLE_MID := 1
const ROLE_CORE := 2
const BAND_ROLES: Array[int] = [ROLE_EDGE, ROLE_MID, ROLE_CORE, ROLE_MID, ROLE_EDGE]
## Longitudinal holds. Guilty Gear Xrd animates at 15 fps with interpolation off —
## "every frame now is a key frame" — and a continuously lerped ribbon is exactly
## what makes a smear look like a 3D ribbon instead of a drawn effect. Three flat
## holds along the length, darkest at the tail.
const HOLDS := 3
## How much of the band colour survives in the oldest hold. The rest is tint_edge,
## so the tail is dark rather than merely faint. 0.3 was tried first and made the
## older two thirds a muddy near-brown: it read as a wooden prop rather than as a
## smear, and it cost the frames where the only part of the ribbon outside the torso
## IS the tail — slash_b's first live frame, and slash_a's recovery. 0.5 keeps the
## dark-to-hot ramp, and the near-black rims are a separate band role that this does
## not touch.
const TAIL_MIX := 0.5

var _base: PackedVector3Array = []
var _tip: PackedVector3Array = []
## Ticks since insertion, one per cross-section. Fractional for the interpolated
## points, so the tail retreats smoothly rather than in whole-tick blocks.
var _age: PackedFloat32Array = []
## The bloom factor each cross-section was born with, so the wind-up's narrow
## opening stays narrow as the swing widens around it.
var _bloom: PackedFloat32Array = []
var _immediate: ImmediateMesh
var _emitting := false
var _fade := 0.0
var _ticks := 0.0
## The blade is tracked every tick, emitting or not, purely so that start() has a
## previous position to seed from. Without it the first frame of a swing holds one
## cross-section, which is not a quad and draws nothing — and the first frame of a
## swing is the wind-up, the single frame a player most needs to read.
var _have_last := false
var _last_base := Vector3.ZERO
var _last_tip := Vector3.ZERO


func _ready() -> void:
	# World space, and never culled: the ribbon's vertices are global, so the
	# node's own AABB says nothing useful about where it is on screen.
	top_level = true
	global_transform = Transform3D.IDENTITY
	extra_cull_margin = 16384.0
	_immediate = ImmediateMesh.new()
	mesh = _immediate
	visible = false


## Open the ribbon. Called from Player.begin_attack on the frame the swing is
## committed, so the wind-up already carries a shape.
##
## Guarded, and the guard is load-bearing: the clips still carry an `_anim_trail_on`
## key a few frames in, and without the guard that key would clear the wind-up's
## samples right as they became useful.
func start() -> void:
	if _emitting:
		return
	_emitting = true
	_fade = 1.0
	_ticks = 0.0
	_clear()


## Stop sampling. The ribbon then narrows and shortens away on its own, which
## reads as a trail dissipating rather than as a mesh being switched off.
func stop() -> void:
	_emitting = false


func _physics_process(_delta: float) -> void:
	var have := blade_base != null and blade_tip != null
	var b := blade_base.global_position if have else Vector3.ZERO
	var t := blade_tip.global_position if have else Vector3.ZERO

	for i in _age.size():
		_age[i] += 1.0

	if _emitting and have:
		if _base.is_empty():
			if _have_last:
				_push(_last_base, _last_tip, 1.0)
			_push(b, t, 0.0)
		else:
			_extend(b, t)
		_ticks += 1.0
	elif not _base.is_empty():
		_fade -= 1.0 / float(maxi(fade_ticks, 1))

	_expire()
	if _fade <= 0.0:
		_clear()
	_rebuild()

	_last_base = b
	_last_tip = t
	_have_last = have


# --- Sampling --------------------------------------------------------------

## Distance-gated insertion. Nothing goes in until the blade has moved
## `point_spacing`; when it has moved further, the gap is filled with that many
## interpolated points in one tick. Straight interpolation adds no curvature by
## itself — the smoothing pass in _rebuild is what makes it an arc — but it is
## what gives that pass something to work with.
func _extend(b: Vector3, t: Vector3) -> void:
	var last := _base.size() - 1
	var prev_b := _base[last]
	var prev_t := _tip[last]
	var moved: float = maxf(prev_b.distance_to(b), prev_t.distance_to(t))
	if moved < point_spacing:
		return
	var steps: int = clampi(ceili(moved / maxf(point_spacing, 0.001)), 1, max_insert)
	for k in range(1, steps + 1):
		var f := float(k) / float(steps)
		_push(prev_b.lerp(b, f), prev_t.lerp(t, f), 1.0 - f)


func _push(b: Vector3, t: Vector3, age: float) -> void:
	_base.push_back(b)
	_tip.push_back(t)
	_age.push_back(age)
	_bloom.push_back(lerpf(bloom_from, 1.0, clampf(_ticks / maxf(bloom_ticks, 0.001), 0.0, 1.0)))


## Drop the tail. Ageing runs during the fade too, so a finished ribbon shortens
## as well as thinning.
func _expire() -> void:
	var drop := 0
	while drop < _age.size() and _age[drop] > history_ticks:
		drop += 1
	if drop == 0:
		return
	_base = _base.slice(drop)
	_tip = _tip.slice(drop)
	_age = _age.slice(drop)
	_bloom = _bloom.slice(drop)


func _clear() -> void:
	_base.clear()
	_tip.clear()
	_age.clear()
	_bloom.clear()


# --- Geometry --------------------------------------------------------------

func _rebuild() -> void:
	_immediate.clear_surfaces()
	var count := _base.size()
	if count < 2 or _fade <= 0.0:
		visible = false
		return
	visible = true
	# Reassert it: something else moving the node would silently offset every vert.
	global_transform = Transform3D.IDENTITY

	# Smooth the spine and the span separately. Smoothing the span as well as the
	# centre keeps the ribbon's width and twist continuous, so the bands stay
	# parallel instead of shearing where the sampling was coarsest.
	var spine := PackedVector3Array()
	var span := PackedVector3Array()
	spine.resize(count)
	span.resize(count)
	for i in count:
		spine[i] = (_base[i] + _tip[i]) * 0.5
		span[i] = _tip[i] - _base[i]
	spine = _smoothed(spine)
	span = _smoothed(span)

	# Cross-sections are measured in BLADE LENGTHS along the blade's own axis: 0 is
	# the base, 1 the tip. The outer edge is pinned one `outer_reach` past the tip
	# and every cross-section takes its width INWARD from there, rather than
	# spreading symmetrically about the blade's midpoint as it used to. That
	# asymmetry is the whole of note 6: the ribbon collapses onto its leading arc,
	# the middle of a swept circle stays empty, and the tail no longer reaches the
	# grip. Width is tapered by the curve, narrowed by the bloom the sample was born
	# with, and collapsed by the fade — all multiplicative, none touching alpha.
	var s_out := 1.0 + outer_reach
	var full := s_out + inner_reach
	var fade := clampf(_fade, 0.0, 1.0)
	var s_in := PackedFloat32Array()
	var solid := PackedByteArray()
	s_in.resize(count)
	solid.resize(count)
	for i in count:
		var u := float(i) / float(count - 1)
		s_in[i] = s_out - full * _taper(u) * _bloom[i] * fade
		solid[i] = 0 if _in_gap(u) else 1

	# One strip per band per unbroken run. A run holding a single cross-section
	# contains no quad and would draw nothing, so short runs are dropped rather than
	# emitted as a degenerate surface.
	for band in BAND_ROLES.size():
		var v0: float = BAND_STOPS[band]
		var v1: float = BAND_STOPS[band + 1]
		var role: int = BAND_ROLES[band]
		var i := 0
		while i < count:
			if solid[i] == 0:
				i += 1
				continue
			var run_end := i
			while run_end + 1 < count and solid[run_end + 1] == 1:
				run_end += 1
			if run_end > i:
				_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
				for k in range(i, run_end + 1):
					var u := float(k) / float(count - 1)
					var colour := _band_colour(role, u, fade)
					_immediate.surface_set_color(colour)
					_immediate.surface_add_vertex(_edge(spine[k], span[k], s_in[k], s_out, v0))
					_immediate.surface_set_color(colour)
					_immediate.surface_add_vertex(_edge(spine[k], span[k], s_in[k], s_out, v1))
				_immediate.surface_end()
			i = run_end + 1


func _taper(u: float) -> float:
	if width_curve != null:
		return width_curve.sample_baked(u)
	return lerpf(0.26, 0.97, u)


## One point on a cross-section. `v` is the band stop, 0 at the inner edge and 1 at
## the outer; `s_in`/`s_out` are that cross-section's edges in blade lengths, where
## 0 is the blade base and 1 the tip. `spine` is the blade's midpoint, hence the
## half-length offset.
func _edge(spine: Vector3, span: Vector3, s_in: float, s_out: float, v: float) -> Vector3:
	return spine + span * (lerpf(s_in, s_out, v) - 0.5)


## Is this point of the length inside one of the trailing gaps? Gaps past the
## midpoint are ignored outright: breaking up the leading edge would cost the one
## part of the ribbon that says which way the blade is travelling.
func _in_gap(u: float) -> bool:
	if u > 0.6:
		return false
	var half_gap := gap_width * 0.5
	for centre in gap_centres:
		if absf(u - centre) < half_gap:
			return true
	return false


## Flat colour for one band at one point along the length. `u` is 0 at the tail.
##
## No UVs and no texture: the three-band ramp that a slash shader would sample
## from a gradient is expressed directly in vertex colour here, which is both
## cheaper and the only way to get the hard band boundaries this art direction
## wants.
func _band_colour(role: int, u: float, fade: float) -> Color:
	var hold := floori(clampf(u, 0.0, 0.9999) * float(HOLDS))
	var step := float(hold) / float(HOLDS - 1)
	var mix: float = lerpf(TAIL_MIX, 1.0, step) * fade
	var target := tint_mid
	if role == ROLE_EDGE:
		target = tint_edge
	elif role == ROLE_CORE:
		target = tint_core
	var out := tint_edge.lerp(target, mix)
	# Never partial. The material is alpha-scissored so it can be outlined, and a
	# scissor has no opinion about 0.4 — see the header.
	out.a = 1.0
	return out


## Laplacian smoothing, endpoints pinned. Returns a new array rather than
## mutating in place, because GDScript packed arrays are value types and a
## by-reference read of this would be a silent no-op.
func _smoothed(points: PackedVector3Array) -> PackedVector3Array:
	var out := points
	var n := out.size()
	if n < 3 or smooth_passes <= 0:
		return out
	var rate := smooth_strength * 0.5
	for _pass in smooth_passes:
		# `prev` keeps the value from BEFORE this pass touched it, which is what
		# makes each pass a proper Jacobi sweep instead of a one-sided drift down
		# the array.
		var prev := out[0]
		for i in range(1, n - 1):
			var cur := out[i]
			out[i] = cur + (prev + out[i + 1] - cur * 2.0) * rate
			prev = cur
	return out
