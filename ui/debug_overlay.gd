extends CanvasLayer
## Live readout for M0 feel-tuning. Delete this once movement is dialled in.

@onready var label: Label = $Label

var _player: Node3D


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	# Off by default. A permanent stats readout over the view is a dev tool,
	# not something a player should have to look past.
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		return

	var speed: float = _player.get_horizontal_speed()
	var grounded := "yes" if _player.is_on_floor() else "no"
	var lockon := _player.get_node_or_null("LockOn") as LockOnSystem
	var lock := "-"
	if lockon != null:
		lock = "%s (%d in range)" % [
			lockon.target.actor.name if lockon.is_locked() and lockon.target.actor != null
				else ("locked" if lockon.is_locked() else "none"),
			lockon.candidate_count()]
	label.text = "\n".join([
		"FPS          %d" % Engine.get_frames_per_second(),
		"speed        %.2f / %.2f m/s" % [speed, _player.max_speed],
		"vertical     %+.2f m/s" % _player.velocity.y,
		"grounded     %s" % grounded,
		"anim         %s" % _player.get_anim_state(),
		"lock-on      %s" % lock,
		"",
		"WASD move | Space jump | E interact | Q lock on",
		"Esc pause | F3 hide this",
		"",
		"Tune live: Debugger -> Remote -> Player",
	])
