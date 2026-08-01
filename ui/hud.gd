extends CanvasLayer
## Hearts, rupee/key counters, the interaction prompt, and a message banner.

@onready var _hearts: HeartRow = $Hearts
@onready var _rupees: Label = $Counters/Rupees
@onready var _keys: Label = $Counters/Keys
@onready var _prompt: Label = $Prompt
@onready var _message: Label = $Message

var _msg_timer := 0.0


func _ready() -> void:
	GameState.health_changed.connect(_on_health)
	GameState.rupees_changed.connect(_on_rupees)
	GameState.keys_changed.connect(_on_keys)
	GameState.message.connect(_on_message)
	_on_health(GameState.heart_quarters, GameState.heart_quarters_max)
	_on_rupees(GameState.rupees)
	_on_keys(GameState.keys)
	_prompt.text = ""
	_message.text = ""
	_message.modulate.a = 0.0


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
