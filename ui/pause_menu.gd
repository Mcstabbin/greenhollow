extends CanvasLayer
## Esc pauses. Also the only place the mouse is released, so the player is never
## stuck with a captured cursor and no way out.

@onready var _panel: Control = $Panel


func _ready() -> void:
	# Must keep running while the tree is paused, or it can't unpause itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	$Panel/Box/Resume.pressed.connect(_resume)
	$Panel/Box/Restart.pressed.connect(_restart)
	$Panel/Box/Quit.pressed.connect(_quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(value: bool) -> void:
	get_tree().paused = value
	_panel.visible = value
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	)
	if value:
		$Panel/Box/Resume.grab_focus()


func _resume() -> void:
	set_paused(false)


func _restart() -> void:
	GameState.reset()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _quit() -> void:
	get_tree().quit()
