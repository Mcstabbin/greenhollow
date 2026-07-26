extends Node
## The one place run state lives. Deliberately tiny.
##
## Milestone rule: this is allowed to exist only now that the space is worth
## walking around. Resist growing it. No stats, no XP curve, no skill tree —
## the previous project died of exactly that.

signal rupees_changed(total: int)
signal keys_changed(total: int)
signal message(text: String)

var rupees := 0
var keys := 0

## Chests remember being opened, keyed by their scene-unique name.
var opened := {}


func add_rupees(n: int) -> void:
	rupees += n
	rupees_changed.emit(rupees)


func add_key(n: int = 1) -> void:
	keys += n
	keys_changed.emit(keys)


func spend_key() -> bool:
	if keys <= 0:
		return false
	keys -= 1
	keys_changed.emit(keys)
	return true


func is_opened(id: String) -> bool:
	return opened.get(id, false)


func mark_opened(id: String) -> void:
	opened[id] = true


func say(text: String) -> void:
	message.emit(text)


func reset() -> void:
	rupees = 0
	keys = 0
	opened.clear()
	rupees_changed.emit(rupees)
	keys_changed.emit(keys)
