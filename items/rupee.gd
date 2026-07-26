extends Area3D
## Auto-collected pickup. Walk into it, it's yours.
##
## Follows the duck-typed pattern from KenneyNL/Starter-Kit-3D-Platformer's
## coin.gd: the pickup asks the body whether it can collect, rather than the
## player knowing about every pickup type.

const COLOURS := {
	"green": Color(0.25, 0.85, 0.40),
	"blue": Color(0.30, 0.55, 0.95),
	"red": Color(0.92, 0.30, 0.32),
}

@export var value: int = 1
@export var colour: String = "green"

var _taken := false
var _t := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # player body
	body_entered.connect(_on_body_entered)

	var gem := SphereMesh.new()
	gem.radius = 0.28
	gem.height = 0.85
	gem.radial_segments = 6
	gem.rings = 2
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = gem
	_mesh.position.y = 0.75
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	var c: Color = COLOURS.get(colour, COLOURS["green"])
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 0.25
	_mesh.material_override = mat
	add_child(_mesh)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	shape.shape = sphere
	shape.position.y = 0.75
	add_child(shape)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	_mesh.rotate_y(2.2 * delta)
	_mesh.position.y = 0.75 + sin(_t * 3.0) * 0.12


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	GameState.add_rupees(value)
	# Higher pitch for the bigger denominations, so value is audible.
	Audio.play("coin", -4.0)
	set_deferred("monitoring", false)

	# Small pop before it disappears.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_mesh, "scale", Vector3.ONE * 1.6, 0.12)
	tween.tween_property(_mesh, "position:y", 1.5, 0.18)
	await tween.finished
	queue_free()
