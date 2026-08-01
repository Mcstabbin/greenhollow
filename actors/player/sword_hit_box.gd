class_name SwordHitBox
extends BasicHitBox3D
## The player's sword hitbox. Layer 5 (player_hitbox), masks layer 6
## (enemy_hurtbox).
##
## The addon (cluttered-code/godot-health-hitbox-hurtbox, PRIOR-ART.md #2) already
## does damage application, typed actions and hurtbox modifiers — all this adds is
## the one thing it has no opinion about: per-swing hit bookkeeping.
##
## That idea is lifted from Snaiel's `DamageSource.instance` (PRIOR-ART.md, last
## section). A counter increments once per swing; a hurtbox already recorded
## against the current counter is ignored. So a blade that sweeps out of a target
## and back into it during one slash lands one hit, and the next slash lands
## again. Without this a wide arc double-dips and damage becomes a function of
## geometry rather than of timing.

## Emitted after a hurtbox is actually damaged — once per target per swing.
signal landed(hurt_box: HurtBox3D)

var _swing: int = 0
var _hit_this_swing: Dictionary[int, int] = {}


func _ready() -> void:
	super()
	# Armed only by the animation's method track, never by default.
	monitoring = false


## Called from the clip's `_anim_hitbox_on` keyframe. Re-enabling `monitoring`
## makes Area3D re-report bodies that are already overlapping, which is what lets
## a second swing hit a target the blade never left.
func begin_swing() -> void:
	_swing += 1
	_hit_this_swing.clear()
	monitoring = true


func end_swing() -> void:
	monitoring = false


## Which swing we are on. The probe reads this to detect that a new attack
## actually started rather than inferring it from a timer.
func get_swing_id() -> int:
	return _swing


## Overrides HitBox3D's own handler — `area_entered` is connected by name, so the
## subclass method is what runs, and `super()` still does the damage.
func _on_area_entered(area: Area3D) -> void:
	if area is HurtBox3D:
		var id := area.get_instance_id()
		if _hit_this_swing.get(id, -1) == _swing:
			return
		_hit_this_swing[id] = _swing
		super._on_area_entered(area)
		landed.emit(area)
		return
	super._on_area_entered(area)
