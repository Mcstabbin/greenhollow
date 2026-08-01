extends Node
## Headless measurement harness. Feel gets measured here, not argued about.
##
## Run as a SCENE, never with --script: GameState and Audio are autoloads, and
## autoloads are not instantiated when a bare script is the main loop.
##
##     GODOT="C:/tools/godot/Godot_v4.7.1-stable_win64_console.exe"
##     "$GODOT" --headless --fixed-fps 60 --path . res://tools/probe.tscn -- --suite=movement
##
## --fixed-fps decouples the physics step from wall time, so a run is both fast
## and deterministic. Without it the numbers drift with machine load.
##
## Output is a single JSON object between markers, so a critic can be handed the
## measurements without the engine's boot noise.

const LEVEL := "res://world/rooms/greenhollow_clearing.tscn"
const BEGIN := "##PROBE-BEGIN##"
const END := "##PROBE-END##"

## Every action the harness might hold. Released between measurements so one
## test can never leak a stuck input into the next.
const ALL_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "interact", "attack", "target", "shield", "roll", "cycle_item",
]

const ITEM_SWORD := "res://items/sword.tres"
const ITEM_AXE := "res://items/axe.tres"
const ITEM_BOW := "res://items/bow.tres"
const ITEM_SHIELD := "res://items/shield.tres"

var _measurements: Array = []
var _level: Node = null
var _player: CharacterBody3D = null
var _spawn: Transform3D


func _ready() -> void:
	var suite := _arg("suite", "movement")

	_level = load(LEVEL).instantiate()
	add_child(_level)
	await get_tree().physics_frame

	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		_fail("no node in group 'player' after loading %s" % LEVEL)
		return
	_spawn = _player.global_transform

	# Let gravity settle the capsule onto the ground and the camera pivot catch up.
	await _frames(40)

	match suite:
		"movement":
			await _suite_movement()
		"combat":
			await _suite_combat()
		"weapons":
			await _suite_weapons()
		"all":
			await _suite_movement()
			await _suite_combat()
			await _suite_weapons()
		_:
			_fail("unknown suite '%s' — known: movement, combat, weapons, all" % suite)
			return

	_emit(suite)

	# Tear the level down before quitting, or the engine prints leaked-instance
	# warnings that end up pasted into a critic's input as if they were findings.
	_release_all()
	remove_child(_level)
	_level.free()
	await get_tree().process_frame
	get_tree().quit(0)


# --- Suites ---------------------------------------------------------------

func _suite_movement() -> void:
	await _reset()

	# Time to reach top speed from a standstill. Explicit types throughout: the
	# player's @export properties are not visible to the static analyser through
	# a CharacterBody3D reference, so `:=` cannot infer them.
	var max_speed: float = _player.max_speed
	Input.action_press("move_forward")
	var target: float = max_speed * 0.99
	var frames: int = await _frames_until(
		func() -> bool: return _speed() >= target, 240)
	_add("accel_to_max_speed", _ms(frames), "ms",
		"press to 99%% of max_speed (%.1f m/s)" % max_speed)

	# Top speed actually achieved, which is not always the exported number.
	await _frames(30)
	_add("max_speed_actual", _speed(), "m/s",
		"sustained horizontal speed while holding forward")

	# Time to stop once input is released.
	_release_all()
	frames = await _frames_until(func() -> bool: return _speed() < 0.05, 240)
	_add("decel_to_stop", _ms(frames), "ms", "release to under 0.05 m/s")

	# Jump arc, from a standstill.
	await _reset()
	var floor_y := _player.global_position.y
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	var apex := floor_y
	var airborne := 0
	while airborne < 240:
		await get_tree().physics_frame
		airborne += 1
		apex = maxf(apex, _player.global_position.y)
		if airborne > 4 and _player.is_on_floor():
			break
	_add("jump_apex_height", apex - floor_y, "m", "peak rise above the takeoff plane")
	_add("jump_airtime", _ms(airborne), "ms", "takeoff to landing, jump tapped")

	# The same jump with the button held, which should go measurably higher —
	# if these two match, variable jump height is broken.
	await _reset()
	floor_y = _player.global_position.y
	Input.action_press("jump")
	apex = floor_y
	airborne = 0
	while airborne < 240:
		await get_tree().physics_frame
		airborne += 1
		apex = maxf(apex, _player.global_position.y)
		if airborne > 4 and _player.is_on_floor():
			break
	_release_all()
	_add("jump_apex_height_held", apex - floor_y, "m", "peak rise with jump held")
	_add("jump_airtime_held", _ms(airborne), "ms", "takeoff to landing, jump held")

	_release_all()


## Sword attacks: the wind-up, the live window, commitment, the combo/cancel
## window, the charge threshold, and whether damage actually lands exactly once
## per target per swing.
##
## Everything here reads an observable the game itself uses — `monitoring` on the
## real hitbox, the swing counter the multi-hit guard keys off, the health of a
## real hurtbox — rather than a number the player script reports about itself.
func _suite_combat() -> void:
	await _reset()

	# Wiring first, so a missing sword reads as a failure rather than as a
	# plausible-looking zero further down.
	#
	# Found THROUGH THE LOADOUT, not at a fixed path. The sword used to be nodes inside
	# player.tscn and is now an equipped item, so a hardcoded path here would be asserting
	# something the game no longer promises — and would keep passing if the loadout stopped
	# working, because the path would still be wrong in the same way.
	var hitbox: Node = _hitbox()
	_add("sword_hitbox_wired", 1.0 if hitbox != null else -1.0, "bool",
		"the equipped weapon presents a HitBox through the Loadout")
	if hitbox == null:
		return
	var layer: int = hitbox.collision_layer
	var mask: int = hitbox.collision_mask
	_add("hitbox_layer", float(layer), "bitmask", "expect 16 (layer 5 player_hitbox)")
	_add("hitbox_mask", float(mask), "bitmask", "expect 32 (layer 6 enemy_hurtbox)")

	# --- Swing one: wind-up and the live window ---------------------------
	var on_at := -1
	var off_at := -1
	var released := false
	Input.action_press("attack")
	var elapsed := 0
	while elapsed < 180:
		await get_tree().physics_frame
		elapsed += 1
		# Let go quickly: holding past charge_time turns this into a spin.
		if elapsed >= 2 and not released:
			Input.action_release("attack")
			released = true
		var live: bool = _player.is_attack_hitbox_active()
		if on_at < 0:
			if live:
				on_at = elapsed
		elif off_at < 0 and not live:
			off_at = elapsed
			break
	_add("attack_windup", _ms(on_at), "ms", "attack press to sword hitbox monitoring")
	_add("attack_hitbox_active", _ms(off_at - on_at if off_at > 0 else -1), "ms",
		"hitbox monitoring true to false")
	_add("attack_clip", 1.0 if String(_player.get_anim_state()) == "slash_a" else -1.0,
		"bool", "first swing plays slash_a")

	# --- Commitment and the combo link ------------------------------------
	# One press, then a second press well inside the swing. The follow-up is
	# buffered and can only start when the clip's cancel keyframe opens the
	# window, so the frame it starts IS the total commitment.
	await _reset()
	# +2, not +1: the first press starts a swing of its own, so the counter has to
	# clear TWO starts before the follow-up has actually been accepted.
	var want_starts: int = int(_player.get_attack_start_count()) + 2
	var commit := -1
	Input.action_press("attack")
	elapsed = 0
	while elapsed < 240:
		await get_tree().physics_frame
		elapsed += 1
		if elapsed == 2:
			Input.action_release("attack")
		if elapsed == 6:
			Input.action_press("attack")   # follow-up, pressed early on purpose
		if elapsed == 8:
			Input.action_release("attack")
		if int(_player.get_attack_start_count()) >= want_starts:
			commit = elapsed
			break
	_add("attack_commitment", _ms(commit), "ms",
		"first press to the second swing being accepted, follow-up pressed at frame 6")
	# One frame later, because the anim state machine travels after the Player's
	# physics tick. Checked so the combo is proven to alternate, not repeat.
	await _frames(2)
	var second_clip := String(_player.get_anim_state())
	_add("combo_alternates", 1.0 if second_clip == "slash_b" else -1.0, "bool",
		"second swing plays slash_b, not slash_a again (got '%s')" % second_clip)
	_release_all()

	# --- Charge threshold and the spin ------------------------------------
	await _reset()
	Input.action_press("attack")
	var charged_at := await _frames_until(
		func() -> bool: return bool(_player.is_attack_charged()), 180)
	_add("charge_threshold", _ms(charged_at), "ms",
		"attack held to the charged tell firing")

	var starts: int = _player.get_attack_start_count()
	Input.action_release("attack")
	on_at = -1
	off_at = -1
	var spin_at := -1
	elapsed = 0
	while elapsed < 180:
		await get_tree().physics_frame
		elapsed += 1
		if spin_at < 0 and int(_player.get_attack_start_count()) > starts:
			spin_at = elapsed
		var live: bool = _player.is_attack_hitbox_active()
		if on_at < 0:
			if live:
				on_at = elapsed
		elif off_at < 0 and not live:
			off_at = elapsed
			break
	_add("spin_release_to_start", _ms(spin_at), "ms",
		"charged release to the spin clip starting")
	_add("spin_windup", _ms(on_at), "ms", "charged release to hitbox monitoring")
	_add("spin_hitbox_active", _ms(off_at - on_at if off_at > 0 else -1), "ms",
		"spin hitbox monitoring true to false — deliberately longer than a slash")
	_add("spin_clip", 1.0 if String(_player.get_anim_state()) == "spin_attack" else -1.0,
		"bool", "the charged release plays spin_attack")
	_release_all()
	await _frames(60)

	# --- Attacking out of a run -------------------------------------------
	# The Move state has its own wiring to Attack, and a null export there would
	# fail silently in exactly the situation a player is most likely to be in.
	await _reset()
	Input.action_press("move_forward")
	await _frames(20)
	var running: float = _speed()
	starts = _player.get_attack_start_count()
	Input.action_press("attack")
	var from_run := await _frames_until(
		func() -> bool: return int(_player.get_attack_start_count()) > starts, 60)
	Input.action_release("attack")
	_add("run_speed_before_attack", running, "m/s", "speed when the attack was pressed")
	_add("attack_from_run", _ms(from_run), "ms", "press to swing accepted while running")
	_release_all()
	await _frames(45)

	# --- Damage, and the multi-hit guard ----------------------------------
	await _reset()
	var target := _spawn_target(1.25, 1.0)
	await _frames(4)
	var health: Node = target.get_node("Health")
	var start_hp: int = health.current

	await _swing_once()
	var after_one: int = health.current
	_add("damage_one_swing", float(start_hp - after_one), "hp",
		"health lost across a whole single swing — slash_damage is 1, so more than 1 means the arc double-dipped")

	await _frames(40)
	await _swing_once()
	_add("damage_two_swings", float(start_hp - int(health.current)), "hp",
		"cumulative after a second swing — proves the guard resets per swing")
	_add("swing_ids_used", float(_player.get_attack_swing_id()), "count",
		"per-swing instance counter after two swings")

	target.queue_free()
	await _frames(4)
	_release_all()

	# The two taps above both re-enter the Attack state, so both play slash_a. The
	# combo's SECOND clip only runs when the follow-up is chained inside the first
	# swing, and it has its own arc — one re-authoring pass shipped a slash_b that
	# swung past a target entirely, which nothing above would have caught.
	#
	# Fresh reset and a fresh target, because every swing lunges the player forward
	# and three of them have already moved them most of a metre.
	await _reset()
	var combo_target := _spawn_target(1.25, 1.0)
	await _frames(4)
	var combo_health: Node = combo_target.get_node("Health")
	var before_combo: int = combo_health.current
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(4)
	Input.action_press("attack")   # chained, so the combo advances to slash_b
	await _frames(2)
	Input.action_release("attack")
	await _frames(70)
	_add("damage_combo_two_hits", float(before_combo - int(combo_health.current)), "hp",
		"health lost across a chained slash_a + slash_b — 2 means both arcs reach what is in front of the player")

	combo_target.queue_free()
	await _frames(4)
	_release_all()


## The other three weapons, and the claims the whole design rests on:
##
##  1. THE AXE IS ONLY NUMBERS. Its wind-up, live window, commitment and damage all differ
##     from the sword's, and nothing in actors/player/ mentions it. The measurements here
##     are the evidence — if `axe_windup` equalled `attack_windup` the data model would be
##     decorative.
##  2. EQUIPPING REALLY SWAPS. A different hitbox node, a different capsule, and exactly
##     one weapon under the grip — not two, and not the old one hidden.
##  3. THE BOW SPENDS AMMO AND ITS ARROW DAMAGES. Measured on a real `Health` component
##     through a real `HurtBox3D`, not on the bow's own opinion of itself.
##  4. THE SHIELD REDUCES DAMAGE, inside its arc and not outside it, applied to a real
##     `Health` so the arithmetic is the game's rather than this file's.
func _suite_weapons() -> void:
	var loadout := _player.get_node_or_null("Loadout") as Loadout
	_add("loadout_present", 1.0 if loadout != null else -1.0, "bool",
		"the player has a Loadout component")
	if loadout == null:
		return
	var grip := loadout.grip
	_add("starts_with_sword", 1.0 if String(loadout.equipped.id) == "sword" else -1.0,
		"bool", "player.tscn ships the sword equipped (got '%s')" % loadout.equipped.id)

	# --- The chest, before anything else has been granted -----------------
	# Driven by calling `interact` directly rather than by walking the player into it: what
	# is under test is the item-get rule, not pathfinding, and a probe that has to navigate
	# to a chest fails for reasons that have nothing to do with chests.
	var chest: Node = _level.get_node_or_null("World/Gameplay/Chest_weapons")
	_add("weapon_chest_in_level", 1.0 if chest != null else -1.0, "bool",
		"the clearing has a chest that hands out items")
	if chest != null:
		chest.call("interact", _player)
		await _frames(4)
		var got := String(loadout.equipped.id)
		_add("chest_grants_next_unfound", 1.0 if got == "axe" else -1.0, "bool",
			"the chest lists axe/bow/shield and the player already has the sword, so the"
			+ " axe comes out (got '%s')" % got)
		var order: Array[ItemData] = [
			load(ITEM_SWORD), load(ITEM_AXE), load(ITEM_BOW), load(ITEM_SHIELD)]
		var next := loadout.next_unfound(order)
		_add("found_order_skips_held", 1.0 if String(next.id) == "bow" else -1.0, "bool",
			"asked for the first unfound item of all four, the answer is the bow: the"
			+ " starting sword counts as found and so does the axe just granted (got '%s')"
			% next.id)

	# --- The swap ---------------------------------------------------------
	await _equip(loadout, ITEM_SWORD)
	var sword_box := _hitbox()
	var sword_radius := _capsule_radius(sword_box)
	var sword_box_id := sword_box.get_instance_id() if sword_box != null else 0
	_add("sword_hitbox_radius", sword_radius, "m",
		"capsule radius the sword's .tres applies — 0.13, the inline sword's own value")

	await _equip(loadout, ITEM_AXE)
	var axe_box := _hitbox()
	_add("equip_swaps_hitbox",
		1.0 if axe_box != null and axe_box.get_instance_id() != sword_box_id else -1.0,
		"bool", "the axe's hitbox is a DIFFERENT node from the sword's")
	_add("axe_hitbox_radius", _capsule_radius(axe_box), "m",
		"0.2 — bigger than the sword's, from items/axe.tres and not from the weapon scene")
	_add("grip_holds_one_weapon", float(grip.get_child_count()), "count",
		"exactly 1: the old weapon is freed, not hidden, and not queued for later")

	# --- Axe timing, measured exactly as the sword's is --------------------
	await _reset()
	var windup := await _measure_swing_windows()
	_add("axe_windup", _ms(int(windup[0])), "ms",
		"press to hitbox monitoring. The sword measures 133 ms on the SAME clip — the"
		+ " difference is items/axe.tres asking for a slower playback rate")
	_add("axe_hitbox_active", _ms(int(windup[1])), "ms", "longer than the sword's 100 ms")
	_add("axe_commitment", _ms(await _measure_commitment()), "ms",
		"first press to the follow-up being accepted. The sword measures 417 ms")

	# The axe's charged attack runs on a SECOND derived rate (7/11 = 0.636 against the
	# slashes' 5/8), because the spin's authored key sits at a different frame. Measured
	# too, or half the numbers in items/axe.tres would be unverified assertions.
	await _reset()
	Input.action_press("attack")
	var charged := await _frames_until(
		func() -> bool: return bool(_player.is_attack_charged()), 180)
	_add("axe_charge_threshold", _ms(charged), "ms",
		"MeleeWeapon.ms_charge is 1250 for the axe against the sword's 1050")
	Input.action_release("attack")
	var spin := await _measure_live_window()
	_add("axe_spin_windup", _ms(int(spin[0])), "ms",
		"charged release to hitbox monitoring. The sword's spin measures 167 ms")
	_add("axe_spin_active", _ms(int(spin[1])), "ms", "the sword's spin measures 300 ms")
	_release_all()
	await _frames(90)

	await _reset()
	var axe_target := _spawn_target(1.25, 1.0)
	await _frames(4)
	var axe_health: Node = axe_target.get_node("Health")
	var axe_start: int = axe_health.current
	await _swing_once()
	_add("axe_damage_one_swing", float(axe_start - int(axe_health.current)), "hp",
		"2 — the axe's opening step carries a HealthAction of 2 where the sword's is 1")
	axe_target.queue_free()
	await _frames(4)
	_release_all()

	# The chained pair, which is where per-STEP damage shows: the axe's follow-through is
	# 3 where its opener is 2, so a full chain is 5. Nothing in code knows that.
	await _reset()
	var chain_target := _spawn_target(1.25, 1.0)
	await _frames(4)
	var chain_health: Node = chain_target.get_node("Health")
	var chain_start: int = chain_health.current
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(6)
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(110)
	_add("axe_damage_combo_two_hits", float(chain_start - int(chain_health.current)), "hp",
		"5 = 2 + 3. Per-step damage, so a chain's finisher hits harder with no code")
	chain_target.queue_free()
	await _frames(4)
	_release_all()

	await _suite_bow(loadout)
	await _suite_shield(loadout)


## The bow: ammo comes out of the loadout, damage arrives through the vendored HitBox3D on
## the arrow, and the draw has to be a state the capture harness can find by name.
func _suite_bow(loadout: Loadout) -> void:
	await _reset()
	await _equip(loadout, ITEM_BOW)
	_add("bow_has_no_hitbox", 1.0 if _hitbox() == null else -1.0, "bool",
		"a bow carries no damage volume — the arrow does")
	_add("bow_ammo_start", float(loadout.ammo), "arrows", "RangedWeapon.start_ammo is 15")

	var target := _spawn_target(5.0, 1.2)
	await _frames(4)
	var health: Node = target.get_node("Health")
	var start_hp: int = health.current

	# Hold past the 500 ms draw, then release. The clip and the state are both asserted,
	# because tools/shots/legibility.json photographs the draw by waiting for them.
	Input.action_press("attack")
	var drawn := await _frames_until(
		func() -> bool: return String(_player.get_anim_state()) == "bow_draw", 60)
	_add("bow_draw_clip", _ms(drawn), "ms", "press to the bow_draw clip being current")
	await _frames(40)
	_add("bow_draw_state", 1.0 if String(_player.get_state_name()) == "Aim" else -1.0,
		"bool", "the draw is its own gameplay state (got '%s')" % _player.get_state_name())
	Input.action_release("attack")

	var hit_at := await _frames_until(
		func() -> bool: return int(health.current) < start_hp, 120)
	_add("bow_shot_to_hit", _ms(hit_at), "ms",
		"release to the arrow damaging a target 5 m ahead — aimed by the character's"
		+ " facing alone, since there is no lock-on system to assist it")
	_add("bow_arrow_damage", float(start_hp - int(health.current)), "hp",
		"2 at full draw: RangedWeapon.damage scaled by draw power")
	_add("bow_ammo_after_shot", float(loadout.ammo), "arrows", "one arrow spent, so 14")
	target.queue_free()
	await _frames(30)
	_release_all()

	# A tap. min_power 0.35 scales 2 damage to 1, so a panic shot is never useless and
	# never optimal.
	await _reset()
	var tap_target := _spawn_target(5.0, 1.2)
	await _frames(4)
	var tap_health: Node = tap_target.get_node("Health")
	var tap_start: int = tap_health.current
	Input.action_press("attack")
	await _frames(3)
	Input.action_release("attack")
	await _frames_until(func() -> bool: return int(tap_health.current) < tap_start, 120)
	_add("bow_tap_damage", float(tap_start - int(tap_health.current)), "hp",
		"1 — a shot loosed three frames into a 500 ms draw")
	# After the queue, not on the damage frame: `queue_free` takes effect at the end of the
	# frame, so counting immediately measures the queue rather than the world.
	await _frames(6)
	_add("arrows_left_in_world", float(_arrows_in_world()), "count",
		"0: an arrow that hit is freed on the spot, so a fight does not leak nodes")
	tap_target.queue_free()
	await _frames(4)
	_release_all()


## The shield. There is no player `Health` and no player `HurtBox3D` yet — both belong to
## whoever brings enemies — so the reduction is measured the only honest way available:
## take the multiplier the block state resolves for a given attacker position, and apply it
## to a real `Health` component through the addon's own damage path.
func _suite_shield(loadout: Loadout) -> void:
	await _reset()
	await _equip(loadout, ITEM_SHIELD)
	_add("shield_has_no_hitbox", 1.0 if _hitbox() == null else -1.0, "bool",
		"blocking is a state, not a swing")

	var block: Node = _player.get_node_or_null("StateMachine/Block")
	if block == null:
		_add("shield_state_present", -1.0, "bool", "StateMachine/Block is missing")
		return

	Input.action_press("shield")
	var up := await _frames_until(
		func() -> bool: return String(_player.get_state_name()) == "Block", 60)
	_add("shield_raise", _ms(up), "ms", "press to the Block state being current")
	_add("shield_clip", 1.0 if String(_player.get_anim_state()) == "block" else -1.0,
		"bool", "the guard has its own held pose (got '%s')" % _player.get_anim_state())

	# Inside the deflect window first, because it is the shorter one: a hit taken within
	# 200 ms of the shield coming up is deflected outright.
	var ahead := _ahead_of_player(2.0)
	_add("shield_deflect_damage", _damage_through(block, ahead, 4), "hp",
		"0 of 4: raised INTO the blow, inside ShieldItem.ms_deflect_window")

	await _frames(20)  # past 200 ms, so this is an ordinary block
	_add("shield_block_damage", _damage_through(block, ahead, 4), "hp",
		"1 of 4: damage_multiplier 0.25, applied by the addon's own Health path")
	_add("shield_back_damage", _damage_through(block, _ahead_of_player(-2.0), 4), "hp",
		"4 of 4: outside the 140-degree arc. A shield that works from behind is not one")

	# Guarding costs mobility, and the number is the shield's.
	Input.action_press("move_forward")
	await _frames(60)
	_add("shield_walk_speed", _speed(), "m/s",
		"2.7 = max_speed 6.0 x ShieldItem.move_scale 0.45")
	_release_all()
	await _frames(30)
	_add("shield_lowered_state", 1.0 if String(_player.get_state_name()) != "Block" else -1.0,
		"bool", "releasing the button leaves the guard (got '%s')" % _player.get_state_name())

	# Back to the sword, so a suite run leaves the player as it found them.
	await _equip(loadout, ITEM_SWORD)


# --- Weapon-suite helpers -------------------------------------------------

## Equip by resource, waiting a frame so the new weapon's nodes are in the tree and their
## `_ready` has run before anything is measured.
func _equip(loadout: Loadout, path: String) -> void:
	var item := load(path) as ItemData
	if item == null:
		_fail("could not load %s" % path)
		return
	if not loadout.grant(item):
		loadout.equip(item)
	await _frames(4)


## Wind-up and live-window frames of one tapped swing, the same measurement the combat
## suite makes on the sword — same code, so the axe's numbers are comparable rather than
## merely plausible.
func _measure_swing_windows() -> Array:
	Input.action_press("attack")
	return await _measure_live_window(true)


## Frames to the hitbox arming and how long it stays armed, from now. `release` taps the
## button off after two frames, which is what keeps a press from becoming a charge.
func _measure_live_window(release: bool = false) -> Array:
	var on_at := -1
	var off_at := -1
	var released := not release
	var elapsed := 0
	while elapsed < 240:
		await get_tree().physics_frame
		elapsed += 1
		if elapsed >= 2 and not released:
			Input.action_release("attack")
			released = true
		var live: bool = _player.is_attack_hitbox_active()
		if on_at < 0:
			if live:
				on_at = elapsed
		elif off_at < 0 and not live:
			off_at = elapsed
			break
	_release_all()
	await _frames(60)
	return [on_at, off_at - on_at if off_at > 0 else -1]


## Frames from the first press to a chained follow-up being accepted.
func _measure_commitment() -> int:
	await _reset()
	var want: int = int(_player.get_attack_start_count()) + 2
	var commit := -1
	Input.action_press("attack")
	var elapsed := 0
	while elapsed < 300:
		await get_tree().physics_frame
		elapsed += 1
		if elapsed == 2:
			Input.action_release("attack")
		if elapsed == 6:
			Input.action_press("attack")
		if elapsed == 8:
			Input.action_release("attack")
		if int(_player.get_attack_start_count()) >= want:
			commit = elapsed
			break
	_release_all()
	await _frames(60)
	return commit


## Damage that actually lands on a fresh Health component, given where the attack comes
## from. The multiplier is the block state's; the arithmetic is the addon's.
func _damage_through(block: Node, source: Vector3, amount: int) -> float:
	var health := Health.new()
	health.max = 99
	health.current = 99
	var multiplier: float = block.call("damage_multiplier_from", source)
	health.damage(amount, 0, multiplier, HealthActionType.Enum.KINETIC)
	var applied := 99 - health.current
	health.free()
	return float(applied)


func _ahead_of_player(distance: float) -> Vector3:
	var rig: Node3D = _player.get_node("Rig")
	var facing := rig.global_basis.z
	facing.y = 0.0
	return _player.global_position + facing.normalized() * distance


func _capsule_radius(hitbox: Node) -> float:
	if hitbox == null:
		return -1.0
	var shape := hitbox.get_node_or_null("Shape") as CollisionShape3D
	var capsule := shape.shape as CapsuleShape3D if shape != null else null
	return capsule.radius if capsule != null else -1.0


func _arrows_in_world() -> int:
	return get_tree().get_nodes_in_group("arrow").size()


## The equipped weapon's hitbox, however the player found it. Null for a shield or a bow,
## which is correct: neither has one.
func _hitbox() -> Node:
	var loadout: Node = _player.get_node_or_null("Loadout")
	if loadout == null:
		return null
	return loadout.call("find_in_weapon", "SwordHitBox") as Node


## Tap attack and wait out the whole swing.
func _swing_once() -> void:
	Input.action_press("attack")
	await _frames(2)
	Input.action_release("attack")
	await _frames(34)


## A minimal enemy stand-in: Health plus a BasicHurtBox3D on layer 6, built in
## code so the combat suite does not depend on an enemy scene that another
## builder owns. Placed `ahead` metres along the player's facing.
func _spawn_target(ahead: float, height: float) -> Node3D:
	var rig: Node3D = _player.get_node("Rig")
	var facing := rig.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()

	var root := Node3D.new()
	root.name = "ProbeTarget"

	var health := Health.new()
	health.name = "Health"
	health.max = 99
	health.current = 99
	root.add_child(health)

	var hurt := BasicHurtBox3D.new()
	hurt.name = "HurtBox"
	hurt.health = health
	hurt.collision_layer = 32   # layer 6, enemy_hurtbox
	hurt.collision_mask = 0
	hurt.monitoring = false     # it only needs to BE found
	hurt.monitorable = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	hurt.add_child(shape)
	root.add_child(hurt)

	_level.add_child(root)
	root.global_position = _player.global_position + facing * ahead + Vector3.UP * height
	return root


# --- Plumbing -------------------------------------------------------------

## Park the player back at spawn with no velocity and no held inputs.
func _reset() -> void:
	_release_all()
	_player.velocity = Vector3.ZERO
	_player.global_transform = _spawn
	await _frames(30)


## The player's horizontal speed as a real float, not a Variant.
func _speed() -> float:
	return Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()


func _release_all() -> void:
	for action in ALL_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## Advance until `test` returns true. Returns the frame count, or -1 on timeout
## so a missing feature reads as a failure rather than as a plausible number.
func _frames_until(test: Callable, timeout_frames: int) -> int:
	var elapsed := 0
	while elapsed < timeout_frames:
		await get_tree().physics_frame
		elapsed += 1
		if test.call():
			return elapsed
	return -1


func _ms(frames: int) -> float:
	if frames < 0:
		return -1.0
	return frames * 1000.0 / float(Engine.physics_ticks_per_second)


func _add(name: String, value: float, unit: String, note: String) -> void:
	_measurements.append({
		"name": name,
		"value": snappedf(value, 0.001),
		"unit": unit,
		"note": note,
		"timed_out": value < 0.0,
	})


func _emit(suite: String) -> void:
	print(BEGIN)
	print(JSON.stringify({
		"suite": suite,
		"physics_hz": Engine.physics_ticks_per_second,
		"measurements": _measurements,
	}, "  "))
	print(END)


func _fail(reason: String) -> void:
	printerr("probe: %s" % reason)
	print(BEGIN)
	print(JSON.stringify({"error": reason}, "  "))
	print(END)
	get_tree().quit(1)


## Read `--key=value` out of the args after the `--` separator.
func _arg(key: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with("--%s=" % key):
			return raw.split("=", true, 1)[1]
	return fallback
