class_name Arrow
extends BasicHitBox3D
## One arrow. Nocked on the string while the bow is drawn, then launched into the level
## and forgotten about.
##
## It IS the hitbox rather than carrying one, which is the shape the vendored addon
## (cluttered-code/godot-health-hitbox-hurtbox, MIT — see PRIOR-ART.md) is built for: a
## `BasicHitBox3D` already owns typed `HealthAction`s, applies them to any `HurtBox3D`
## it overlaps, and has `ignore_collisions` for exactly the "one arrow, one victim"
## rule. Adding an Area3D child to a Node3D root would have been a second node and no
## extra behaviour.
##
## PRIOR-ART.md's projectile pass found precisely one 3D projectile addon for Godot 4
## (NekoZer0158/NZ_projectiles, 10 stars) and it is a bullet-hell framework: ~120 files
## and a strategy Resource per behaviour. This is the whole of what a bow needs.
##
## The same object is the nocked arrow and the fired one, which is deliberate. The
## engine's own hand-tracking pickup demo reparents a held object while preserving its
## world transform, and doing the same here means the arrow a player sees drawn is the
## arrow that flies — there is no separate "visual" arrow to keep in sync.

## Flight is over: it hit something, stuck, or timed out. The bow does not listen; this
## is here so a quiver or a pickup can later.
signal finished(arrow: Arrow)

## Metres per second, overwritten from RangedWeapon.projectile_speed on launch.
@export var speed: float = 34.0
## Downward acceleration in flight, in m/s^2. NOT called `gravity`: Area3D already has a
## property of that name (its gravity-override field) and shadowing it is a parse error,
## which is a two-second bug to fix and an easy one to reintroduce.
##
## Gentle, and much less than the world's 9.8. An arrow that visibly arcs is charming and
## makes a third-person bow unaimable, because the camera and the arrow do not share an
## origin. This is enough droop to read as a projectile over the ~24 m play area.
@export var drop: float = 4.5
## Seconds before an arrow that hit nothing removes itself. Without this a missed shot
## is a permanent node.
@export var lifetime: float = 4.0
## How long an arrow that hit the world stays stuck in it. Long enough to see where the
## shot went, short enough that the clearing does not fill up with fletching.
@export var stick_time: float = 2.5
## What flight stops against. Layer 1 only: `world`. Deliberately not the player's own
## body layer, or a shot fired from inside the character's capsule dies on frame one.
@export_flags_3d_physics var world_mask: int = 1

var _velocity := Vector3.ZERO
var _flying := false
var _life := 0.0
var _stuck := -1.0


func _ready() -> void:
	super()
	# Layer 5 player_hitbox, mask 6 enemy_hurtbox — the same pair the melee hitboxes
	# use, so an enemy needs no knowledge of what hit it.
	collision_layer = 16
	collision_mask = 32
	monitoring = false
	set_physics_process(false)
	action_applied.connect(_on_action_applied)


## Held on the string. Inert: no monitoring, no motion, no lifetime — an arrow that
## damaged something while still being drawn would be a very confusing weapon.
func nock() -> void:
	_flying = false
	_life = 0.0
	_stuck = -1.0
	ignore_collisions = false
	monitoring = false
	set_physics_process(false)


## Loose it. `direction` need not be normalised.
func launch(from: Transform3D, direction: Vector3, arrow_speed: float, damage: int) -> void:
	global_transform = from
	speed = arrow_speed
	amount = maxi(damage, 1)
	_velocity = direction.normalized() * speed
	_flying = true
	_life = 0.0
	_face_travel()
	monitoring = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _stuck >= 0.0:
		_stuck -= delta
		if _stuck <= 0.0:
			_finish()
		return
	if not _flying:
		return

	_life += delta
	if _life >= lifetime:
		_finish()
		return

	_velocity.y -= drop * delta
	var from := global_position
	var to := from + _velocity * delta

	# Swept against the world, not a position test. At 34 m/s an arrow covers 0.57 m per
	# tick, which is wider than most of the geometry in the level — a point test would
	# tunnel straight through a fence.
	var query := PhysicsRayQueryParameters3D.create(from, to, world_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		_face_travel()
		return

	# Stuck. Pulled a little back along its own path so the head is buried rather than
	# coplanar with the surface, which would z-fight and shimmer.
	global_position = hit["position"] as Vector3 + _velocity.normalized() * 0.06
	_flying = false
	set_deferred("monitoring", false)
	_stuck = stick_time


## Point the shaft along travel. The mesh is authored down -Z, which is what `look_at`
## aims, so this is one call rather than a basis built by hand.
func _face_travel() -> void:
	if _velocity.length_squared() < 0.0001:
		return
	var up := Vector3.UP
	# A shot straight up or down would make `look_at` degenerate. Rare, and the fix is
	# one line, so it may as well be here.
	if absf(_velocity.normalized().dot(up)) > 0.99:
		up = Vector3.FORWARD
	look_at(global_position + _velocity, up)


## Damage landed. The arrow is spent: one arrow, one victim, and it does not go on to
## hit the thing standing behind.
##
## `ignore_collisions` rather than switching monitoring off, and the difference is not
## cosmetic: this runs INSIDE the area_entered signal, and Area3D refuses to change
## `monitoring` while it is dispatching one — "Function blocked during in/out signal",
## which is an error at runtime and a silently-still-armed arrow if it is ignored. The
## addon exposes the flag for exactly this.
func _on_action_applied(_hurt_box: HurtBox3D) -> void:
	ignore_collisions = true
	_finish()


func _finish() -> void:
	_flying = false
	# Deferred for the same reason: _finish is reachable from inside the collision signal.
	set_deferred("monitoring", false)
	set_physics_process(false)
	finished.emit(self)
	queue_free()
