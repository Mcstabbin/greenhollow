extends CanvasLayer
## Hearts, rupee/key counters, the interaction prompt, and a message banner.

@onready var _hearts: HeartRow = $Hearts
@onready var _rupees: Label = $Counters/Rupees
@onready var _keys: Label = $Counters/Keys
@onready var _item: Label = $Counters/Item
@onready var _prompt: Label = $Prompt
@onready var _message: Label = $Message

var _msg_timer := 0.0
var _loadout: Loadout = null
var _equipped: ItemData = null
var _ammo := -1


func _ready() -> void:
	GameState.health_changed.connect(_on_health)
	GameState.rupees_changed.connect(_on_rupees)
	GameState.keys_changed.connect(_on_keys)
	GameState.message.connect(_on_message)
	_on_health(GameState.heart_quarters, GameState.heart_quarters_max)
	_on_rupees(GameState.rupees)
	_on_keys(GameState.keys)
	_prompt.text = ""
	_item.text = ""
	_message.text = ""
	_message.modulate.a = 0.0
	_sync_loadout()


## Wired by the player, which owns the slot. Pushed in rather than looked up here for the
## reason the docs give first: a scene with no dependencies is one you can drop into any
## level, and the HUD hunting the scene tree for a player is the version of this that
## breaks the day something else has a loadout.
##
## With one equip slot this line IS the inventory: it is the only thing that answers "what
## am I holding" and "how many arrows are left" without looking at the character.
## The `is_node_ready` guard is load-bearing rather than cautious: the player and the HUD
## are separate scenes in the same level, so there is no guaranteed order between their
## `_ready` calls, and the first version of this crashed writing to a Label that the
## HUD's own `@onready` had not reached yet.
func bind_loadout(loadout: Loadout) -> void:
	_loadout = loadout
	loadout.equipped_changed.connect(_on_equipped)
	loadout.ammo_changed.connect(_on_ammo)
	if is_node_ready():
		_sync_loadout()


func _sync_loadout() -> void:
	if _loadout == null:
		return
	_ammo = _loadout.ammo
	_on_equipped(_loadout.equipped)


func _on_equipped(item: ItemData) -> void:
	_equipped = item
	_refresh_item()


func _on_ammo(current: int, _maximum: int) -> void:
	_ammo = current
	_refresh_item()


## Ammo only appears for something that HAS ammo, which is the same split the item
## resources make: a shield resource has no ammo field, so the HUD shows no ammo count.
func _refresh_item() -> void:
	if _equipped == null:
		_item.text = ""
	elif _ammo >= 0:
		_item.text = "%s  ×%d" % [_equipped.display_name, _ammo]
	else:
		_item.text = _equipped.display_name


func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			var tween := create_tween()
			tween.tween_property(_message, "modulate:a", 0.0, 0.4)


## Quarter-heart units in, hearts out. The row owns the arithmetic.
func _on_health(current: int, maximum: int) -> void:
	_hearts.set_health(current, maximum)


func _on_rupees(total: int) -> void:
	_rupees.text = "◆ %d" % total


func _on_keys(total: int) -> void:
	_keys.text = "⚷ %d" % total


func _on_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 1.0
	_msg_timer = 3.2


## Called by the player each frame with the focused interactable (or null).
func set_prompt(target) -> void:
	if target == null:
		_prompt.text = ""
	else:
		_prompt.text = "[E]  %s" % target.prompt
