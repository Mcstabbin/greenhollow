extends Node
## The one place run state lives. Deliberately tiny.
##
## Milestone rule: this is allowed to exist only now that the space is worth
## walking around. Resist growing it. No stats, no XP curve, no skill tree —
## the previous project died of exactly that.

signal rupees_changed(total: int)
signal keys_changed(total: int)
## Health in quarter-heart units. 4 units = one heart.
signal health_changed(current: int, maximum: int)
## Emitted when the player's health reaches zero.
signal player_died()
signal message(text: String)

var rupees := 0
var keys := 0

## Quarter-hearts, not hit points: three hearts is 12. Integers all the way, so a
## quarter of a heart is exact and nothing ever renders half a pixel of fill.
var heart_quarters := 12
var heart_quarters_max := 12

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


## Mirror the player's Health component into the HUD's single source of truth.
## The component stays authoritative — this is a projection of it, so the HUD has
## one thing to listen to and never has to go looking for the player node.
func set_health(current: int, maximum: int) -> void:
	heart_quarters_max = maxi(maximum, 1)
	heart_quarters = clampi(current, 0, heart_quarters_max)
	health_changed.emit(heart_quarters, heart_quarters_max)


## Called by the player when its Health component reports death.
func notify_died() -> void:
	player_died.emit()


## Add a heart container: raises the maximum by 4 and refills.
func add_heart_container() -> void:
	var grown := heart_quarters_max + 4
	set_health(grown, grown)


func is_opened(id: String) -> bool:
	return opened.get(id, false)


func mark_opened(id: String) -> void:
	opened[id] = true


func say(text: String) -> void:
	message.emit(text)


func reset() -> void:
	rupees = 0
	keys = 0
	# Refill, but keep the maximum: heart containers are permanent progress, so a
	# reset should not take back a container the player has already earned.
	heart_quarters = heart_quarters_max
	opened.clear()
	rupees_changed.emit(rupees)
	keys_changed.emit(keys)
	health_changed.emit(heart_quarters, heart_quarters_max)
