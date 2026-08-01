class_name ItemData
extends Resource
## Base for anything the player can hold. One `.tres` per item.
##
## Four items and one slot, so there is deliberately no inventory framework here.
## `CLAUDE.md` Rule 2 names inventory as a system not to build until the space
## demands it, and `autoload/game_state.gd`'s header records that the previous
## project died of exactly that. Seventeen grid-inventory addons exist for 4.7 and
## every one of them is aimed at a problem we do not have (see PRIOR-ART.md).
##
## Subclasses carry what differs: MeleeWeapon, ShieldItem, RangedWeapon. Splitting
## by subclass rather than piling shield and bow fields onto one resource keeps the
## inspector honest — a shield should not show an ammo count.
##
## Revisit the whole approach past roughly 30 items; a Godot core contributor makes
## a reasonable case that a Resource per row becomes inspector clutter at scale.
## At four it is the clearest thing available.

## Stable identifier, used for save data and for equality. **Not** the resource
## path: this project has no resource UIDs, so a `path=`-only reference breaks
## silently when a `.tres` is renamed, and a chest holding a renamed weapon would
## quietly contain nothing. Compare and persist by `id`.
@export var id: StringName = &""

## Shown in the HUD and in the item-get banner.
@export var display_name: String = "Item"

## The item-get line. Held here rather than in the chest so the same message
## appears wherever the item comes from, and so a chest needs no per-item branch.
@export_multiline var found_text: String = "You found something!"

## Which hand it occupies. Only MAIN is reachable today — the loadout has a single
## slot by design — but naming the slot now is what makes adding an off-hand a
## small change rather than a rewrite.
@export_enum("Main hand", "Off hand") var hand: int = 0

## The visual, plus whatever hitbox or marker nodes it needs, as a scene the
## loadout instantiates under the grip. A scene rather than a mesh so a weapon can
## carry its own hitbox, trail markers and glow without the player knowing which
## weapon it is holding.
@export var scene: PackedScene


## Everything the player needs to know to hold this without type-checking it.
func is_melee() -> bool:
	return false


func is_shield() -> bool:
	return false


func is_ranged() -> bool:
	return false
