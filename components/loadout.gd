class_name Loadout
extends Node
## What the player is holding. One slot, by design.
##
## Deliberately NOT in `GameState`. That autoload's header records that the
## previous project died of a growing singleton, and `CLAUDE.md` Rule 2 names
## inventory as a system not to build until the space demands it. A chest already
## receives the player in `interact(by)`, so it can reach this component directly
## and no global state is involved at all.
##
## The single slot means holding a shield means holding *only* a shield, with no
## attack. That is the chosen behaviour. `ItemData.hand` is already modelled, so
## adding an off-hand slot later is a second `_slots` entry rather than a rewrite.
##
## Equipped state does not survive a scene reload — you start with whatever the
## player scene ships. Chests are remembered by `GameState.opened`, so a reload
## does not let you re-open one; the loadout is the only thing that resets. Living
## with that beats growing the singleton, and `runtime_save_load` in the engine
## demos is the pattern when it needs fixing properly.

## The equipped item changed. `item` may be null when nothing is held.
signal equipped_changed(item: ItemData)
## A ranged weapon's ammo changed, or the equipped item has no ammo (-1).
signal ammo_changed(current: int, maximum: int)
## A new item was found for the first time, for the item-get moment.
signal item_found(item: ItemData)

## Where a weapon's scene is parented. Set this to the hand/grip node in the
## player scene. Exported rather than hardcoded so the same component works on
## anything with a grip — an enemy that can be disarmed, for instance.
@export var grip: Node3D

## What the player starts holding, if anything.
@export var starting_item: ItemData

var equipped: ItemData = null
var ammo: int = -1

## Ids of every item ever picked up. Kept so a chest can grant "the next thing you
## do not have" without needing to know what came before it. Ids rather than
## resources because this project has no resource UIDs, so comparing by path would
## break the moment a `.tres` is renamed.
var _found: Array[StringName] = []

var _instance: Node = null


func _ready() -> void:
	if starting_item != null:
		equip(starting_item)


## True once this item has ever been picked up, equipped or not.
func has_found(id: StringName) -> bool:
	return _found.has(id)


## Record an item as found and equip it. Returns false if it was already found, so
## a chest can move on to the next thing rather than granting a duplicate.
func grant(item: ItemData) -> bool:
	if item == null or has_found(item.id):
		return false
	_found.append(item.id)
	item_found.emit(item)
	equip(item)
	return true


## Put an item in the slot, replacing whatever was there. Safe to call with null
## to empty the hand.
func equip(item: ItemData) -> void:
	if _instance != null:
		# free(), not queue_free(): the replacement is parented in the same frame,
		# and a queued node would still be under the grip when it arrives — two
		# weapons in one hand for a frame, which a screenshot will catch.
		_instance.get_parent().remove_child(_instance)
		_instance.free()
		_instance = null

	equipped = item

	if item != null and item.scene != null:
		if grip == null:
			push_warning("Loadout has no grip assigned; %s will not be visible" % item.id)
		else:
			_instance = item.scene.instantiate()
			grip.add_child(_instance)

	_set_ammo_for(item)
	equipped_changed.emit(equipped)


## The instantiated weapon scene, so the player can find its hitbox or markers
## without knowing which weapon it is.
func instance() -> Node:
	return _instance


## Find a node of a given type inside the equipped weapon — its hitbox, its trail
## markers. Returns null when the weapon has none, which is normal: a shield has no
## hitbox and a bow's damage is carried by the arrow.
func find_in_weapon(type_name: String) -> Node:
	if _instance == null:
		return null
	if _instance.is_class(type_name) or (_instance.get_script() != null
			and _instance.get_script().get_global_name() == StringName(type_name)):
		return _instance
	var found := _instance.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null


## Spend one arrow. False when empty, so the caller does not play a fire animation
## for a shot that never happens.
func spend_ammo(count: int = 1) -> bool:
	if ammo < count:
		return false
	ammo -= count
	ammo_changed.emit(ammo, _max_ammo())
	return true


func add_ammo(count: int) -> void:
	if ammo < 0:
		return  # Nothing equipped that uses ammo.
	ammo = mini(ammo + count, _max_ammo())
	ammo_changed.emit(ammo, _max_ammo())


func _set_ammo_for(item: ItemData) -> void:
	var ranged := item as RangedWeapon
	ammo = ranged.start_ammo if ranged != null else -1
	ammo_changed.emit(ammo, _max_ammo())


func _max_ammo() -> int:
	var ranged := equipped as RangedWeapon
	return ranged.max_ammo if ranged != null else -1
