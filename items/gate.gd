extends Interactable
## The way out of the forest. Locked until you find the small key.
##
## The generator parents the fence_gate model under this as "Mesh" and a
## StaticBody3D named "Blocker" that stops you walking through.

@export var locked: bool = true

var _open := false


func _ready() -> void:
	super()
	prompt = "Unlock"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 4.0)
	shape.shape = box
	shape.position.y = 1.2
	add_child(shape)


func _on_interact(_by: Node3D) -> void:
	if _open:
		return
	if locked and not GameState.spend_key():
		GameState.say("The gate is locked. A small key would open it.")
		return

	_open = true
	prompt = "Open"
	GameState.say("The gate swings open. The forest path lies beyond...")

	var mesh := get_node_or_null("Mesh")
	if mesh:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(mesh, "rotation:y", deg_to_rad(-95.0), 0.7)

	var blocker := get_node_or_null("Blocker")
	if blocker:
		for c in blocker.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).set_deferred("disabled", true)
