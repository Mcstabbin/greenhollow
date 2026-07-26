extends CanvasLayer
## Live readout for M0 feel-tuning. Delete this once movement is dialled in.

@onready var label: Label = $Label

var _player: Node3D


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		return

	var speed: float = _player.get_horizontal_speed()
	var grounded := "yes" if _player.is_on_floor() else "no"
	label.text = "\n".join([
		"FPS          %d" % Engine.get_frames_per_second(),
		"speed        %.2f / %.2f m/s" % [speed, _player.max_speed],
		"vertical     %+.2f m/s" % _player.velocity.y,
		"grounded     %s" % grounded,
		"",
		"WASD move  |  Space jump  |  Mouse look",
		"Esc releases the mouse",
		"",
		"Tune live: Debugger -> Remote -> Player",
	])
