extends Control
# TUTORIAL HOOK -- KenjiBox: bottom-left dialogue panel for tutorial mode

signal tapped

@onready var portrait: ColorRect = $Portrait
@onready var name_label: Label = $Portrait/NameLabel
@onready var speech_bubble: Panel = $SpeechBubble
@onready var bubble_label: Label = $SpeechBubble/BubbleLabel
@onready var tap_hint: Label = $TapHint

var _advance_on_tap: bool = false

func _ready() -> void:
	hide()

func show_text(text: String, advance_on_tap: bool = false) -> void:
	bubble_label.text = text
	_advance_on_tap = advance_on_tap
	tap_hint.visible = advance_on_tap
	show()

func _gui_input(event: InputEvent) -> void:
	if _advance_on_tap and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		tapped.emit()
