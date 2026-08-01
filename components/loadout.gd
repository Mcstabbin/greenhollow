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

## Every item, in canonical order, for the debug cycle key. Chests state their own
## contents instead of reading this: falling back to the catalogue would have quietly
## turned the chest holding the forest gate's key into a weapon chest.
@export var catalogue: Array[ItemData] = []

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
		# Recorded as found, but WITHOUT the item_found banner: you are already holding
		# it, so there is nothing to announce. Skipping this was a real bug rather than
		# a nicety — a chest asking for "the first thing not yet found" would have
		# handed back the sword the player is holding, forever.
		if not _found.has(starting_item.id):
			_found.append(starting_item.id)
		equip(starting_item)


## True once this item has ever been picked up, equipped or not.
func has_found(id: StringName) -> bool:
	return _found.has(id)


## The first entry of `from` that has never been picked up. Null when there is nothing
## left, which is how a chest knows to fall back to rupees.
##
## Takes the list rather than reading `catalogue`, deliberately: a chest that fell back to
## the catalogue when its own list was empty would silently turn EVERY chest in the level
## into a weapon chest, including the one holding the key the forest gate needs.
func next_unfound(from: Array[ItemData]) -> ItemData:
	for item in from:
		if item != null and not has_found(item.id):
			return item
	return null


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
			_apply_shape(item)

	_set_ammo_for(item)
	equipped_changed.emit(equipped)


## Equip the next thing in `catalogue`, wrapping. Granted rather than merely equipped,
## so cycling past an item also marks it found and a chest stops offering it.
##
## This exists for a concrete reason and not as a convenience: tools/capture.tscn can
## only reach the game through InputMap actions, so without an input that changes the
## loadout there is NO WAY to photograph the axe, the bow or the shield. Bound to F4.
func cycle() -> void:
	if catalogue.is_empty():
		return
	var at := catalogue.find(equipped)
	var item := catalogue[(at + 1) % catalogue.size()]
	# Recorded as found but deliberately NOT announced. A debug key handing you a weapon is
	# not an item-get moment, and going through `grant` raised the found banner in the
	# middle of every capture frame taken through this key — a 30-point label across the
	# bottom of a frame whose whole purpose is judging a silhouette.
	if not _found.has(item.id):
		_found.append(item.id)
	equip(item)


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


## A named node inside the equipped weapon — its trail markers, its arrow spawn, its
## charge glow. Null when this weapon has none, which is normal and not an error: a
## shield has no BladeTip and a sword has no ArrowSpawn.
func part(part_name: StringName) -> Node:
	if _instance == null:
		return null
	return _instance.get_node_or_null(NodePath(String(part_name)))


## Make the instanced scene match its data. Only shapes and sizes: anything about how
## the weapon BEHAVES belongs to whoever swings it.
##
## The hitbox capsule is here because the alternative is keeping a weapon's reach in two
## places — the generator that builds the mesh and the resource that tunes the fight —
## and they had already diverged by 4 cm, which is more than the margin by which the
## combo's second swing reaches a target in front of the player.
func _apply_shape(item: ItemData) -> void:
	var melee := item as MeleeWeapon
	if melee == null:
		return
	var shape := find_in_weapon("CollisionShape3D") as CollisionShape3D
	if shape == null:
		return
	var capsule := shape.shape as CapsuleShape3D
	if capsule == null:
		return
	# duplicate(), because a CapsuleShape3D loaded from the weapon scene is shared with
	# every other instance of that scene and resizing it in place would reach across
	# them — the same trap as editing a shared Material.
	capsule = capsule.duplicate() as CapsuleShape3D
	capsule.radius = melee.hitbox_radius
	capsule.height = maxf(melee.hitbox_height, melee.hitbox_radius * 2.0 + 0.01)
	shape.shape = capsule


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
