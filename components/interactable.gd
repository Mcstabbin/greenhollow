class_name Interactable
extends Area3D
## Base for anything the player can press Interact on.
##
## Proximity + facing rather than a RayCast3D aimed down the camera: this is a
## third-person adventure with no crosshair, so "the thing I'm standing next to
## and looking at" is the right selection rule (it's what Zelda does).
##
## Interactables live on collision layer 3; the player's InteractField masks it.

signal interacted(by: Node3D)

## Verb shown in the HUD prompt, e.g. "Open", "Read".
@export var prompt: String = "Examine"
## If true, it can only be used once.
@export var one_shot: bool = false

var _used := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true


func can_interact() -> bool:
	return not (one_shot and _used)


## Called by the player. Subclasses override _on_interact.
func interact(by: Node3D) -> void:
	if not can_interact():
		return
	_used = true
	interacted.emit(by)
	_on_interact(by)


func _on_interact(_by: Node3D) -> void:
	pass
