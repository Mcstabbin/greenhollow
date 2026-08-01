extends Interactable
## A chest. Open it once, get what's inside, it stays open.
##
## Built procedurally from two boxes so it needs no model: the nature kit has
## no chest. Lid swings on a Tween.
##
## The item-get moment is GENERIC. There is no branch per item anywhere below: the chest
## asks the opener's Loadout for the first thing in `contains` that has never been picked
## up, grants it, and shows the line the ITEM carries (`ItemData.found_text`). Adding a
## fifth weapon is a `.tres` file and an array entry.

## Items this chest can give, in order. The first one never yet found is what comes out,
## so a chest holds a PREFERENCE rather than a specific object and never has to remember
## what it has already handed over — the Loadout knows what has been found.
##
## Stated per chest rather than defaulted to the loadout's catalogue on purpose: a
## fallback would have turned every chest in the level into a weapon chest, including the
## one holding the key the forest gate needs.
@export var contains: Array[ItemData] = []
@export var contains_key: bool = false
@export var rupees: int = 0
@export var chest_id: String = ""

var _lid: Node3D
var _open := false


func _ready() -> void:
	super()
	prompt = "Open"
	one_shot = true

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.48, 0.31, 0.18)
	wood.roughness = 1.0
	wood.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.90, 0.72, 0.26)
	gold.roughness = 0.4
	gold.metallic = 0.3

	var base := MeshInstance3D.new()
	base.name = "Base"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.5, 0.9, 1.0)
	base.mesh = bm
	base.position.y = 0.45
	base.material_override = wood
	add_child(base)

	# Lid pivots at the back edge so it swings like a hinge.
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0, 0.9, -0.5)
	add_child(_lid)
	var lid_mesh := MeshInstance3D.new()
	lid_mesh.name = "Mesh"
	var lm := BoxMesh.new()
	lm.size = Vector3(1.55, 0.28, 1.05)
	lid_mesh.mesh = lm
	lid_mesh.position = Vector3(0, 0.14, 0.5)
	lid_mesh.material_override = gold
	_lid.add_child(lid_mesh)

	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.0, 2.2)
	shape.shape = box
	shape.position.y = 0.7
	add_child(shape)

	# Solid so you bump into it rather than walking through.
	var body := StaticBody3D.new()
	body.name = "Body"
	var bshape := CollisionShape3D.new()
	bshape.name = "Shape"
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(1.5, 0.9, 1.0)
	bshape.shape = bbox
	bshape.position.y = 0.45
	body.add_child(bshape)
	add_child(body)

	if chest_id != "" and GameState.is_opened(chest_id):
		_lid.rotation.x = -1.9
		_open = true
		_used = true


func _on_interact(by: Node3D) -> void:
	if _open:
		return
	_open = true
	if chest_id != "":
		GameState.mark_opened(chest_id)

	Audio.play("break", -6.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_lid, "rotation:x", -1.9, 0.45)

	if _give_item(by):
		return
	if contains_key:
		GameState.add_key()
		GameState.say("Found a small key!")
	if rupees > 0:
		GameState.add_rupees(rupees)
		GameState.say("Found %d rupees!" % rupees)


## Hand over the first item the opener has never found. Returns true if something was
## given, so a chest that has run out of items falls through to its rupees rather than
## opening on nothing.
##
## The opener is reached through `interact(by)` — the Loadout is a component on the
## player, not global state, so nothing here goes near an autoload to find it. See the
## header of components/loadout.gd for why that matters.
func _give_item(by: Node3D) -> bool:
	if by == null or contains.is_empty():
		return false
	var loadout := by.get_node_or_null("Loadout") as Loadout
	if loadout == null:
		return false
	var item := loadout.next_unfound(contains)
	if item == null:
		return false
	loadout.grant(item)
	# The item's own line, so the chest needs no idea what came out of it.
	GameState.say(item.found_text)
	return true
