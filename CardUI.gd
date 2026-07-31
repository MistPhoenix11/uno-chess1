extends ColorRect

signal card_clicked(index: int)

const CARD_COLORS := {
	0: Color(0.9, 0.2, 0.2),
	1: Color(0.2, 0.4, 0.9),
	2: Color(0.2, 0.7, 0.3),
	3: Color(0.9, 0.85, 0.2),
}

var _index: int = -1
var _disabled: bool = false

@onready var _label: Label = $Label

func setup(card: Dictionary, index: int, disabled: bool = false) -> void:
	_index = index
	_disabled = disabled or card.get("locked", false)
	_label.text = card.get("name", "CARD")
	var color_key: int = card.get("color", 4)
	if color_key in CARD_COLORS:
		color = CARD_COLORS[color_key]
	else:
		color = Color(0.45, 0.45, 0.5)
	modulate = Color(0.55, 0.55, 0.55, 0.85) if _disabled else Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE if _disabled else Control.MOUSE_FILTER_STOP
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _gui_input(event: InputEvent) -> void:
	if _disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(_index)
		accept_event()
