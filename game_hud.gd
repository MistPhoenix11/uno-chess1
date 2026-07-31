extends VBoxContainer
# Phase 4 — HUD labels, phase buttons, choice dialogs · v1.6.2

var main: Node2D

@onready var turn_label: Label = $StatusRow/TurnLabel
@onready var energy_label: Label = $StatusRow/EnergyLabel
@onready var clock_row: HBoxContainer = $ClockRow
@onready var white_clock_label: Label = $ClockRow/WhiteClock
@onready var black_clock_label: Label = $ClockRow/BlackClock
@onready var message_label: Label = $MessageLabel
@onready var phase_buttons: HBoxContainer = $PhaseButtons
@onready var confirm_btn: Button = $PhaseButtons/ConfirmCards
@onready var skip_move_btn: Button = $PhaseButtons/SkipMovement
@onready var skip_special_btn: Button = $PhaseButtons/SkipSpecial
@onready var end_turn_btn: Button = $PhaseButtons/EndTurn
@onready var castle_row: HBoxContainer = $CastleRow
@onready var castle_kingside_btn: Button = $CastleRow/CastleKingside
@onready var castle_queenside_btn: Button = $CastleRow/CastleQueenside
@onready var skip_choice_row: HBoxContainer = $SkipChoiceRow
@onready var resist_skip_btn: Button = $SkipChoiceRow/ResistSkip
@onready var accept_skip_btn: Button = $SkipChoiceRow/AcceptSkip
@onready var emergency_row: HBoxContainer = $EmergencyRow
@onready var accept_emergency_btn: Button = $EmergencyRow/AcceptEmergency
@onready var decline_emergency_btn: Button = $EmergencyRow/DeclineEmergency
@onready var trap_cancel_row: HBoxContainer = $TrapCancelRow
@onready var cancel_trap_btn: Button = $TrapCancelRow/CancelTrap

# Coin toss — OPTIONAL node. HUD works with or without it in the scene.
# When you build it: HBoxContainer "ColorChoiceRow" + buttons "ChooseWhite"/"ChooseBlack".
var color_choice_row: HBoxContainer = null

func _ready() -> void:
	main = get_parent().get_parent().get_parent().get_parent() as Node2D

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$StatusRow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	castle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skip_choice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emergency_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trap_cancel_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HandScroll.mouse_filter = Control.MOUSE_FILTER_PASS
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	confirm_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.confirm_cards_and_move())
	skip_move_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.skip_movement())
	skip_special_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.skip_special_phase())
	end_turn_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.end_turn())
	castle_kingside_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.execute_castle("kingside"))
	castle_queenside_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.execute_castle("queenside"))
	resist_skip_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.resolve_skip(true))
	accept_skip_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.resolve_skip(false))
	accept_emergency_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.resolve_emergency_protocol(true))
	decline_emergency_btn.pressed.connect(func(): 
		if not main.bot_players.get(main.current_turn, false): 
			main.resolve_emergency_protocol(false))
	cancel_trap_btn.pressed.connect(func():
		if not main.bot_players.get(main.current_turn, false):
			main.cancel_trap_placement())

	# Optional coin-toss row — safe whether or not the node exists yet
	color_choice_row = get_node_or_null("ColorChoiceRow")
	if color_choice_row:
		color_choice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		color_choice_row.get_node("ChooseWhite").pressed.connect(func(): main.choose_color("white"))
		color_choice_row.get_node("ChooseBlack").pressed.connect(func(): main.choose_color("black"))

	# FIX 3: _clock_frozen self-heals — any new turn = a living match (rematch-safe)
	main.turn_started.connect(func(_p, _t):
		_clock_frozen = false
		_refresh_hud())
	main.phase_changed.connect(func(_phase): _refresh_hud())
	main.energy_confirmed.connect(func(_amt, _bonus): _refresh_hud())
	main.piece_moved.connect(func(_t, _f, _to): _refresh_hud())

	# FIX 1 + FIX 2: 3-arg signature, freeze clock AND slam the button doors
	main.game_over.connect(func(_w, _r, _d):
		_clock_frozen = true
		_update_button_visibility())

	_refresh_hud()

func _refresh_hud() -> void:
	turn_label.text = "%s's Turn (Turn %d)" % [main.current_turn.capitalize(), main.turn_number]
	energy_label.text = "Energy: %d" % main.current_energy
	_update_button_visibility()

func _update_button_visibility() -> void:
	phase_buttons.visible = false
	castle_row.visible = false
	skip_choice_row.visible = false
	emergency_row.visible = false
	trap_cancel_row.visible = false
	if color_choice_row:
		color_choice_row.visible = false

	confirm_btn.visible = false
	skip_move_btn.visible = false
	skip_special_btn.visible = false
	end_turn_btn.visible = false

	if main.game_over_flag:
		return  # dead games get NO buttons — zombie purge, absolute

	match main.game_phase:
		main.GamePhase.PLAY_CARDS:
			phase_buttons.visible = true
			confirm_btn.visible = true
			skip_move_btn.visible = true
		main.GamePhase.MOVE_PIECE:
			phase_buttons.visible = true
			skip_move_btn.visible = true
			castle_row.visible = true
		main.GamePhase.SPECIAL_CARD:
			phase_buttons.visible = true
			skip_special_btn.visible = not main.special_played_this_turn
			end_turn_btn.visible = true
		main.GamePhase.AWAITING_SKIP_CHOICE:
			skip_choice_row.visible = true
		main.GamePhase.AWAITING_EMERGENCY_CHOICE:
			emergency_row.visible = true
		main.GamePhase.AWAITING_COLOR_CHOICE:
			if color_choice_row:
				color_choice_row.visible = true

func show_message(text: String) -> void:
	message_label.text = text

func update_trap_cancel(show: bool) -> void:
	trap_cancel_row.visible = show

# ══════════════════════════════════════════════════════════
# CHESS CLOCK DISPLAY
# ══════════════════════════════════════════════════════════
const CLOCK_ACTIVE := Color(1.0, 1.0, 1.0)
const CLOCK_INACTIVE := Color(0.55, 0.55, 0.55)
const CLOCK_LOW := Color(1.0, 0.25, 0.25)
const LOW_TIME := 30.0

var _clock_frozen := false

func update_clock_display(w: float, b: float, active: String = "") -> void:
	if active == "":
		active = main.current_turn

	white_clock_label.text = "♔ " + ChessClock.format_time(w)
	black_clock_label.text = "♚ " + ChessClock.format_time(b)
	_style_clock(white_clock_label, w, active == "white")
	_style_clock(black_clock_label, b, active == "black")

func _style_clock(label: Label, seconds: float, is_active: bool) -> void:
	if seconds <= LOW_TIME and is_active and not _clock_frozen:
		var pulse := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 320.0))
		label.add_theme_color_override("font_color", CLOCK_LOW * pulse)
	elif seconds <= LOW_TIME:
		label.add_theme_color_override("font_color", CLOCK_LOW)
	elif is_active:
		label.add_theme_color_override("font_color", CLOCK_INACTIVE if _clock_frozen else CLOCK_ACTIVE)
	else:
		label.add_theme_color_override("font_color", CLOCK_INACTIVE)

func _refresh() -> void:
	_refresh_hud() 
