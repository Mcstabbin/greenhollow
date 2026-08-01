class_name RangedWeapon
extends ItemData
## A drawn-and-fired weapon. The only genuinely new subsystem in the four.
##
## The draw is the readability risk: it is a held pose with no motion, which is
## exactly the shape that failed a forced-choice legibility test for the charged
## sword attack ("only the blade's colour changed — if the glow had been absent I
## would have called it IDLE with confidence 5 and been wrong"). A bow draw needs a
## silhouette change or a hard-edged ground mark, not a tint.

## Press to fully drawn. A shot released early is weaker — see `min_power`.
@export var ms_draw: int = 500

## Damage scale of a shot released the instant the draw begins. Full draw is 1.0.
## Non-zero so tapping still does something, low enough that it is never optimal.
@export_range(0.0, 1.0) var min_power: float = 0.35

## Damage of a FULL-power hit. Scaled by draw for anything less, floored at 1 so a
## panic shot still does something.
##
## A plain integer rather than the `Array[HealthAction]` an AttackStep carries, and the
## asymmetry is honest: a melee step's actions are fixed at author time, while an
## arrow's amount is only known when the string is released. The action is built on
## launch instead — items/arrow.gd is a `BasicHitBox3D`, so setting `amount` is what
## writes it.
@export var damage: int = 2

## The projectile, spawned into the level rather than parented to the player so it
## keeps flying if the player moves, turns, or dies.
@export var projectile: PackedScene

## Metres per second. Fast enough to feel like a bow, slow enough that the arrow
## is a visible object rather than a hitscan.
@export var projectile_speed: float = 34.0

## Seconds before an arrow that hit nothing removes itself. Without this, a missed
## shot is a permanent node.
@export var projectile_lifetime: float = 4.0

@export_group("Ammo")
## Arrows carried. Ammo lives on the loadout, not in GameState.
@export var max_ammo: int = 30
## Ammo the item arrives with.
@export var start_ammo: int = 15

@export_group("Aiming")
## When locked on, the shot is steered toward the target by this fraction — 0 is
## no assist, 1 is homing. A third-person bow without some assist is a chore,
## because the camera and the arrow do not share an origin.
@export_range(0.0, 1.0) var lockon_assist: float = 0.85
## Beyond this range the assist tapers to nothing, so distant targets still
## require aim. Keep inside the lock-on range or the two systems disagree.
@export var assist_range: float = 12.0


func is_ranged() -> bool:
	return true
