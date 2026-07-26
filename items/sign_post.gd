extends Interactable
## A readable sign. The generator parents the sign model under this as "Mesh".

@export_multiline var text: String = "..."


func _ready() -> void:
	super()
	prompt = "Read"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.4, 2.6)
	shape.shape = box
	shape.position.y = 1.0
	add_child(shape)


func _on_interact(_by: Node3D) -> void:
	GameState.say(text)
