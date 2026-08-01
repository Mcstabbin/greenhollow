class_name SwordTrail
extends MeshInstance3D
## The ribbon the blade leaves while its hitbox is live.
##
## Why it exists: with a 0.6 m blade on a 1.5 m character at a 4.5 m camera
## distance, a single screenshot of a swing shows a thin white stick somewhere near
## a limb. The motion is real — the tip covers about 180 degrees in 100 ms — but a
## still frame cannot show motion, and neither can a player's eye at that speed.
## The trail is what turns six frames of arm rotation into a legible arc, and it is
## the cheapest possible version of it: one ImmediateMesh strip, no particles, no
## shader, nothing the integrated-graphics target will notice.
##
## Built as a world-space ribbon (`top_level`) rather than a child transform,
## because the whole point is that the older samples must NOT follow the arm.

## The blade's inner and outer ends. Sampled every tick; the quad between two
## consecutive samples is one segment of the ribbon.
@export var blade_base: Node3D
@export var blade_tip: Node3D
## Ticks of history. Ten at 60 Hz is 167 ms, slightly longer than the live window,
## so the ribbon is at full length exactly when the hit lands.
@export var history: int = 10
@export var tint: Color = Color(0.72, 0.93, 1.0, 0.9)

var _base_samples: PackedVector3Array = []
var _tip_samples: PackedVector3Array = []
var _immediate: ImmediateMesh
var _emitting := false


func _ready() -> void:
	# World space, and never culled: the ribbon's vertices are global, so the
	# node's own AABB says nothing useful about where it is on screen.
	top_level = true
	global_transform = Transform3D.IDENTITY
	extra_cull_margin = 16384.0
	_immediate = ImmediateMesh.new()
	mesh = _immediate
	visible = false


## Called from the clip's hitbox-on window.
func start() -> void:
	_emitting = true
	_base_samples.clear()
	_tip_samples.clear()


## Stop sampling. The ribbon then eats itself one segment per tick, which reads as
## a trail dissipating rather than as a mesh being switched off.
func stop() -> void:
	_emitting = false


func _physics_process(_delta: float) -> void:
	if _emitting and blade_base != null and blade_tip != null:
		_base_samples.push_back(blade_base.global_position)
		_tip_samples.push_back(blade_tip.global_position)
	elif not _base_samples.is_empty():
		_drop_oldest()

	while _base_samples.size() > history:
		_drop_oldest()

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
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		# Squared, so the tail thins out fast and the leading edge stays bright.
		var age := float(i) / float(count - 1)
		var colour := tint
		colour.a *= age * age
		_immediate.surface_set_color(colour)
		_immediate.surface_add_vertex(_base_samples[i])
		_immediate.surface_set_color(colour)
		_immediate.surface_add_vertex(_tip_samples[i])
	_immediate.surface_end()
