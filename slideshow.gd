extends Control
# Standalone UnoChess rules slideshow -- no game-state dependencies.
# Navigate with Back/Next or Left/Right/Escape. Exit/Done return to main_menu.tscn.

const MAIN_MENU := "res://main_menu.tscn"
const PANEL_COUNT := 8

var _panels: Array[Dictionary] = []
var _current_index: int = 0

@onready var title_label: Label = %TitleLabel
@onready var body_label: RichTextLabel = %BodyLabel
@onready var image_rect: TextureRect = %ImageRect
@onready var image_placeholder: Control = %ImagePlaceholder
@onready var back_button: Button = %BackButton
@onready var next_button: Button = %NextButton
@onready var exit_button: Button = %ExitButton
@onready var progress_label: Label = %ProgressLabel

func _ready() -> void:
	_build_panels()
	_set_static_labels()
	_refresh()

func _set_static_labels() -> void:
	back_button.text = String.chr(0x25C0) + " Back"
	# Replaced the mangled 🖼️ escape sequence with a safe star
	image_placeholder.get_node("PlaceholderLabel").text = "★ IMAGE COMING SOON"

func _build_panels() -> void:
	_panels = [
		{
			"title": "THE BATTLEFIELD ♜",
			"body": "Welcome to UnoChess! This is chess... with a deck problem. The board is [b]8 wide, 10 deep[/b] - bigger than chess, more room to scheme. [b]Your goal: take down the enemy King.[/b] Everything else is just how you get there.",
			"image": "res://assets/slideshow/p1_board.png",
		},
		{
			"title": "ENERGY IS EVERYTHING ⚡",
			"body": "Pieces don't move for free. You pay in [b]energy[/b], and energy comes from [b]number cards (1-4)[/b] played from your hand. Play up to [b]3 number cards[/b] per turn - their total is your energy budget. Match card colors for [b]bonus energy[/b]. ★ ⚠ Spend it or lose it - [b]unspent energy vanishes at end of turn.[/b] You draw [b]2 cards[/b] at the end of every turn.",
			"image": "res://assets/slideshow/p2_cards.png",
		},
		{
			"title": "WHAT MOVES COST ★",
			"body": "Every piece has a price tag: [b]Pawn[/b] - 1 per square (max 2 squares) - [b]Bishop / Rook[/b] - 2 per square - [b]Knight[/b] - 3 flat, any jump - [b]Queen[/b] - 3 per square ♛ [i]royalty ain't cheap[/i] - [b]King[/b] - 4 flat. Capturing costs the same as moving there - and captures pay a [b]bounty: draw a card.[/b] ✔ Castling is available too, for a combined King + Rook fee.",
			"image": "res://assets/slideshow/p3_costs.png",
		},
		{
			"title": "SPECIAL CARDS ★",
			"body": "Beyond numbers, your deck hides [b]special cards[/b]: disruption, draws, traps, stadiums... and a few legends. ♞ [b]One special card per turn.[/b] Choose it well. Specials are your turn's plot twist - energy wins battles, specials win wars.",
			"image": "res://assets/slideshow/p4_specials.png",
		},
		{
			"title": "REVERSE ↩",
			"body": "After your opponent moves a piece, you get ONE chance to undo it: play Reverse during your own turn's special phase. Their piece snaps back to where it started. ⚠ Reverse rewinds the BOARD, not the game - captured pieces stay dead, spent cards stay spent, drawn cards are kept. And no, you can't Reverse a Reverse.",
			"image": "res://assets/slideshow/p5_reverse.png",
		},
		{
			"title": "TRAPS ☠",
			"body": "Trap cards arm a square of your choice. The [b]type is announced[/b] - the [b]location is secret.[/b] Even the board won't tell. ✖ Traps trigger on [b]ANY piece that steps on them - including yours.[/b] Memory is part of the price. [b]Landmine[/b] ☠ - 50% chance to destroy the piece. A dud stays a dud. [b]Spring Trap[/b] ↩ - chance to bounce the piece back where it came from. [b]Ice Trap[/b] ❄ - chance to freeze a piece for 2 turns: can't move, can't be captured. Frozen squares glow [b]light blue.[/b] A failed Spring or Ice trap is spent.",
			"image": "res://assets/slideshow/p6_traps.png",
		},
		{
			"title": "CHECK & THE EMERGENCY PROTOCOL ⚠",
			"body": "Your King in danger? You must deal with it - turns don't end while you're ignoring check. Cornered with no way out? The [b]Emergency Protocol[/b] saves your King... at a cost: your King takes a [b]wound.[/b] ✖ ⚠ [b]Two wounds and your King is done.[/b] There are no third chances.",
			"image": "res://assets/slideshow/p7_check.png",
		},
		{
			"title": "HOW IT ENDS ♚",
			"body": "[b]WIN:[/b] bring down the enemy King - by capture, or by inflicting his second wound. ✖ [b]WIN:[/b] your opponent's clock hits 0:00. ⏳ [b]DRAW:[/b] the same position repeats three times [i](actual piece moves - you can't stall your way to safety)[/i], or [b]40 turns pass without a single capture.[/b] ✔ Now shuffle up. The King is waiting. ♞♚",
			"image": "res://assets/slideshow/p8_victory.png",
		},
	]

func _refresh() -> void:
	var panel: Dictionary = _panels[_current_index]

	title_label.text = panel["title"]
	body_label.text = panel["body"]

	# Image slot
	var image_path: String = panel["image"]
	if ResourceLoader.exists(image_path):
		var tex: Texture2D = load(image_path) as Texture2D
		if tex:
			image_rect.texture = tex
			image_rect.visible = true
			image_placeholder.visible = false
		else:
			_show_image_placeholder()
	else:
		_show_image_placeholder()

	# Navigation buttons
	back_button.visible = _current_index > 0
	back_button.disabled = _current_index == 0

	if _current_index == PANEL_COUNT - 1:
		next_button.text = "Done " + String.chr(0x2714)
	else:
		next_button.text = "Next " + String.chr(0x25B6)

	# Progress
	progress_label.text = "Panel %d / %d" % [_current_index + 1, PANEL_COUNT]

func _show_image_placeholder() -> void:
	image_rect.texture = null
	image_rect.visible = false
	image_placeholder.visible = true

func _on_back_pressed() -> void:
	if _current_index > 0:
		_current_index -= 1
		_refresh()

func _on_next_pressed() -> void:
	if _current_index < PANEL_COUNT - 1:
		_current_index += 1
		_refresh()
	else:
		_return_to_menu()

func _on_exit_pressed() -> void:
	_return_to_menu()

func _return_to_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right"):
		_on_next_pressed()
	elif event.is_action_pressed("ui_left"):
		_on_back_pressed()
	elif event.is_action_pressed("ui_cancel"):
		_return_to_menu()