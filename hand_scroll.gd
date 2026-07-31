extends ScrollContainer
# Mouse wheel scrolls the hand horizontally -- works in ALL modes.

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			scroll_horizontal -= 60
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			scroll_horizontal += 60
			accept_event() 