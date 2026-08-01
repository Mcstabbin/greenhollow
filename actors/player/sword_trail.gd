class_name SwordTrail
extends MeshInstance3D
## The ribbon the blade leaves through a swing.
##
## Why it exists: with a ~0.8 m blade on a 2.2 m character at the default 5.5 m
## camera distance, a still frame of a swing shows a short pale stick somewhere
## near a limb. The motion is real — the tip covers about 180 degrees in 100 ms —
## but a still frame cannot show motion, and neither can a player's eye at that
## speed. The trail is what turns six frames of arm rotation into a legible arc,
## and it is the cheapest possible version of it: one ImmediateMesh strip, no
## particles, no shader, nothing the integrated-graphics target will notice.
##
## Built as a world-space ribbon (`top_level`) rather than a child transform,
## because the whole point is that the older samples must NOT follow the arm.
##
## Three things here are corrections, not preferences, and a critic found each of
## them independently:
##
##  1. HUE. A white blade leaving a white trail across a white torso is invisible.
##     The ribbon is hot orange. Greenhollow is green grass, green canopy, white
##     torso and pale blue sky and water — every one of those is either green or a
##     cool desaturated tint, so orange is the only hue in the wheel that nothing
##     here competes with. Cyan was tried first and lost against the pale sky and
##     the water it kept crossing.
##  2. WIDTH. The ribbon is widened past the blade at both ends (`over_reach`)
##     rather than spanning base-to-tip exactly. A trail is a smear of where the
##     blade *was*, not a photograph of it, and the smear is what carries at 640
##     px.
##  3. PERSISTENCE. The old version ate one segment per tick the instant sampling
##     stopped and faded the tail with `age * age`, so in a still frame it was a
##     scratch. Now the whole ribbon holds its shape and fades out as one object
##     over `fade_ticks`, which means the recovery frame still shows the arc that
##     just happened.

## The blade's inner and outer ends. Sampled every tick; the quad between two
## consecutive samples is one segment of the ribbon.
@export var blade_base: Node3D
@export var blade_tip: Node3D
## Ticks of history. Sampling is opened by the clip a few frames before the
## hitbox and closed several after (see tools/build_combat_anims.gd), so this has
## to cover more than the live window: 20 at 60 Hz is 333 ms.
@export var history: int = 20
## How far past each end of the blade the ribbon reaches, as a fraction of blade
## length. 0.0 is base-to-tip; 0.6 makes the band 2.2 m across — two and a bit
## times the old ribbon — which at 640 px is the difference between a band and a
## scratch. Past about 0.8 the spin's two revolutions merge into a filled orange
## disc rather than a ring.
@export var over_reach: float = 0.6
## Inner (near the hand) and outer (past the tip) edge colours. Hot on the inside,
## deep orange on the outside. Neither is white — a white core would put the
## white-on-white problem straight back.
@export var tint_inner: Color = Color(1.0, 0.86, 0.30, 1.0)
@export var tint_outer: Color = Color(1.0, 0.36, 0.02, 1.0)
## Ticks the finished ribbon takes to fade out. Long enough that a screenshot of
## the recovery pose still contains the arc.
@export var fade_ticks: int = 14

var _base_samples: PackedVector3Array = []
var _tip_samples: PackedVector3Array = []
var _immediate: ImmediateMesh
var _emitting := false
var _fade := 0.0


func _ready() -> void:
	# World space, and never culled: the ribbon's vertices are global, so the
	# node's own AABB says nothing useful about where it is on screen.
	top_level = true
	global_transform = Transform3D.IDENTITY
	extra_cull_margin = 16384.0
	_immediate = ImmediateMesh.new()
	mesh = _immediate
	visible = false


## Called from the clip's trail-on keyframe, which opens a few frames ahead of the
## hitbox so the wind-up is part of the arc.
func start() -> void:
	_emitting = true
	_fade = 1.0
	_base_samples.clear()
	_tip_samples.clear()


## Stop sampling. The ribbon then holds its shape and fades as one object, which
## reads as a trail dissipating rather than as a mesh being switched off.
func stop() -> void:
	_emitting = false


func _physics_process(_delta: float) -> void:
	if _emitting and blade_base != null and blade_tip != null:
		var b := blade_base.global_position
		var t := blade_tip.global_position
		# Widen past both ends of the blade. Done at sample time so the whole
		# ribbon, including its history, is consistently wide.
		var along := (t - b) * over_reach
		_base_samples.push_back(b - along)
		_tip_samples.push_back(t + along)
		while _base_samples.size() > history:
			_drop_oldest()
	elif not _base_samples.is_empty():
		_fade -= 1.0 / float(maxi(fade_ticks, 1))
		if _fade <= 0.0:
			_base_samples.clear()
			_tip_samples.clear()

	_rebuild()


func _drop_oldest() -> void:
	_base_samples.remove_at(0)
	_tip_samples.remove_at(0)


func _rebuild() -> void:
	_immediate.clear_surfaces()
	if _base_samples.size() < 2:
		visible = false
		return
	visible = true
	# Reassert it: something else moving the node would silently offset every vert.
	global_transform = Transform3D.IDENTITY

	var count := _base_samples.size()
	var alpha := clampf(_fade, 0.0, 1.0)
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		# Nearly flat, not squared: the old `age * age` taper made everything but
		# the leading two segments transparent, and a critic reported the result as
		# "barely more than a scratch" that "could be mistaken for a lighting
		# artefact". The whole ribbon is now essentially opaque and only fades as
		# one object, via `alpha`.
		var age := float(i) / float(count - 1)
		var edge: float = alpha * lerpf(0.85, 1.0, age)
		var inner := tint_inner
		inner.a = tint_inner.a * edge
		var outer := tint_outer
		outer.a = tint_outer.a * edge
		_immediate.surface_set_color(inner)
		_immediate.surface_add_vertex(_base_samples[i])
		_immediate.surface_set_color(outer)
		_immediate.surface_add_vertex(_tip_samples[i])
	_immediate.surface_end()
