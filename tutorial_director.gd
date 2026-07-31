extends Node
# ══════════════════════════════════════════════════════════
# TUTORIAL DIRECTOR v2 -- Scripted ten-step UnoChess tutorial
# Child of MainGame. Drives Kenji, locks input, advances steps.
# Inert unless Progression.next_mode == "tutorial".
# v2: turn rotation fixed · deferred end_turn (signal-safety) ·
# dynamic card indices · phase management per step ·
# KenjiBox tap indicator · step-9 check/checkmate handling
# ══════════════════════════════════════════════════════════

var active: bool = false
var current_step: int = 0
var free_play: bool = false
var main: Node2D

# -- Step state --
var _awaiting_piece_select: bool = false
var _awaiting_move_target: bool = false
var _kenji_move_pending: bool = false
var _end_turn_queued: bool = false
var _tap_advances: bool = false
var _step_10_rook_col: int = 8
var _step_10_rook_direction: int = -1

const KENJI_BOX_SCENE := preload("res://kenji_box.tscn")

var kenji_box: Control
var _pulse_tween: Tween
var _pointer: Control
var _pulsed_targets: Array = []
var _scale_tweens: Array = []

var _steps: Array = []

func _init_steps() -> void:
	_steps = [
		{ # 0
			"kenji_text": "Number cards are your energy. Tap the glowing card!",
			"step_type": "card_click",
			"target_card_index": 0,
			"advance_on": "card_staged",
		},
		{ # 1
			"kenji_text": "A 3 gives 3 energy. Energy moves pieces -- one square, one energy. Confirm it!",
			"step_type": "button_press",
			"target_button": "confirm",
			"advance_on": "energy_confirmed",
		},
		{ # 2
			"kenji_text": "Now -- move your pawn forward!",
			"step_type": "board_move",
			"target_piece": Vector2i(5, 2),
			"target_dest": Vector2i(5, 3),
			"advance_on": "piece_moved",
		},
		{ # 3
			"kenji_text": "",
			"step_type": "watch",
			"advance_on": "kenji_done",
			"kenji_scripted_move": {
				"from": Vector2i(4, 5),
				"to": Vector2i(4, 4),
				"kenji_text": "My pawn wanders too far... be gentle with it!",
			},
		},
		{ # 4
			"kenji_text": "Capture it! Captures draw you a bonus card!",
			"step_type": "board_move",
			"target_piece": Vector2i(5, 3),
			"target_dest": Vector2i(4, 4),
			"advance_on": "capture_made",
		},
		{ # 5
			"kenji_text": "Stage THREE number cards of DIFFERENT colors -- all-different gives bonus energy. Then confirm!",
			"step_type": "multi_card",
			"advance_on": "energy_confirmed",
		},
		{ # 6
			"kenji_text": "Special cards bend the rules. Play the Landmine, then place it on the glowing square.",
			"step_type": "trap_place",
			"target_trap_pos": Vector2i(3, 4),
			"advance_on": "trap_placed",
		},
		{ # 7
			"kenji_text": "",
			"step_type": "watch",
			"advance_on": "kenji_done",
			"kenji_scripted_move": {
				"from": Vector2i(3, 5),
				"to": Vector2i(3, 4),
				"kenji_text": "...I meant to do that.",
			},
		},
		{ # 8
			"kenji_text": "",
			"step_type": "watch_then_reverse",
			"advance_on": "reverse_played",
			"kenji_scripted_move": {
				"from": Vector2i(6, 8),
				"to": Vector2i(5, 6),
				"kenji_text": "The Reverse card undoes my last move -- play it and watch my Knight walk backwards in shame!",
			},
		},
		{ # 9
			"kenji_text": "Now finish me. My King is exposed. You know everything you need.",
			"step_type": "free_play",
			"advance_on": "white_wins",
		},
	]

# ══════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════
func _ready() -> void:
	if Progression.next_mode != "tutorial":
		return
	active = true
	main = get_parent()
	main.tutorial_active = true
	_init_steps()
	call_deferred("_deferred_start")

func _deferred_start() -> void:
	await get_tree().process_frame

	main.turn_started.connect(_on_turn_started)
	main.piece_moved.connect(_on_piece_moved)
	main.capture_made.connect(_on_capture_made)
	main.trap_placed.connect(_on_trap_placed)
	main.energy_confirmed.connect(_on_energy_confirmed)
	main.game_over.connect(_on_game_over)
	main.card_played.connect(_on_card_played)

	var canvas := main.get_node_or_null("CanvasLayer")
	if canvas:
		kenji_box = KENJI_BOX_SCENE.instantiate()
		kenji_box.name = "KenjiBox"
		canvas.add_child(kenji_box)
		kenji_box.tapped.connect(_on_kenji_box_tapped)

	_prepare_tutorial_board()
	main.board_ui._redraw()
	_build_tutorial_hands_and_deck()
	main.refresh_hand_ui()

	main.chess_clock.start_match(main.starting_time, "white")
	main.set_phase(main.GamePhase.PLAY_CARDS)
	_lock_all_input()
	_start_step(0)

# ══════════════════════════════════════════════════════════
# BOARD / HANDS / DECK SETUP
# ══════════════════════════════════════════════════════════
func _prepare_tutorial_board() -> void:
	var gm = main.grid_manager
	if gm == null:
		return
	gm.board.clear()
	_place_piece(gm, Vector2i(1, 1), main.PieceType.ROOK, "white")
	_place_piece(gm, Vector2i(2, 1), main.PieceType.KNIGHT, "white")
	_place_piece(gm, Vector2i(3, 1), main.PieceType.BISHOP, "white")
	_place_piece(gm, Vector2i(4, 1), main.PieceType.QUEEN, "white")
	_place_piece(gm, Vector2i(5, 1), main.PieceType.KING, "white")
	_place_piece(gm, Vector2i(6, 1), main.PieceType.BISHOP, "white")
	_place_piece(gm, Vector2i(7, 1), main.PieceType.KNIGHT, "white")
	_place_piece(gm, Vector2i(8, 1), main.PieceType.ROOK, "white")
	for col in range(1, 9):
		_place_piece(gm, Vector2i(col, 2), main.PieceType.PAWN, "white")
	_place_piece(gm, Vector2i(5, 10), main.PieceType.KING, "black")
	_place_piece(gm, Vector2i(6, 8), main.PieceType.KNIGHT, "black")
	_place_piece(gm, Vector2i(4, 5), main.PieceType.PAWN, "black")
	_place_piece(gm, Vector2i(3, 5), main.PieceType.PAWN, "black")
	_place_piece(gm, Vector2i(8, 10), main.PieceType.ROOK, "black")

func _place_piece(gm: Node2D, pos: Vector2i, ptype: int, piece_owner: String) -> void:
	gm.board[pos] = {"type": ptype, "owner": piece_owner, "has_moved": false}

func _build_tutorial_hands_and_deck() -> void:
	main.white_hand = [
		main.make_card("3", main.CardType.NUMBER, main.CardColor.RED, 3),
		main.make_card("2", main.CardType.NUMBER, main.CardColor.BLUE, 2),
		main.make_card("2", main.CardType.NUMBER, main.CardColor.GREEN, 2),
		main.make_card("Landmine", main.CardType.TRAP, main.CardColor.NONE),
		main.make_card("Reverse", main.CardType.UTILITY, main.CardColor.NONE),
		main.make_card("+2 Draw", main.CardType.DRAW, main.CardColor.NONE),
	]
	main.black_hand.clear()
	main.shared_deck.clear()
	for _i in range(20):
		main.shared_deck.append(main.make_card("1", main.CardType.NUMBER, main.CardColor.YELLOW, 1))
	main.discard_pile.clear()
	main.exiled_cards.clear()

# ══════════════════════════════════════════════════════════
# STEP MACHINE
# ══════════════════════════════════════════════════════════
func _start_step(idx: int) -> void:
	if idx >= _steps.size():
		return
	current_step = idx
	var step: Dictionary = _steps[idx]
	var text: String = step.get("kenji_text", "")
	if text != "":
		_show_kenji(text, false)

	_lock_all_input()

	match step.step_type:
		"card_click":
			_unlock_card(step.target_card_index)
		"button_press":
			_unlock_button(step.target_button)
		"board_move":
			_awaiting_piece_select = true
			_awaiting_move_target = false
			if main.current_turn == "white":
				_prep_white_action()
			_highlight_board_square(step.target_piece, true)
		"multi_card":
			_unlock_number_cards()
			_unlock_button("confirm")
		"trap_place":
			_unlock_trap_card()
			call_deferred("_enter_special_phase")
			_highlight_board_square(step.target_trap_pos, true)
		"watch", "watch_then_reverse":
			# Kenji acts when HIS turn starts. If it's still white's turn, end it.
			if main.current_turn == "white":
				_queue_end_white_turn()
		"free_play":
			free_play = true
			_prepare_step_9_board()
			_unlock_all_input()

func _advance_step() -> void:
	if current_step >= _steps.size() - 1:
		return
	current_step += 1
	_start_step(current_step)

# Player action steps are self-funding: energy + correct phase.
func _prep_white_action() -> void:
	if main.current_energy < 2:
		main.current_energy = 2
	main.set_phase(main.GamePhase.MOVE_PIECE)

func _enter_special_phase() -> void:
	if not active or free_play:
		return
	if main.current_turn == "white" and not main.game_over_flag:
		main.set_phase(main.GamePhase.SPECIAL_CARD)

# SIGNAL-SAFETY: main emits signals MID-function (capture_made fires before
# the move finishes). Never end_turn synchronously from a handler.
func _queue_end_white_turn() -> void:
	if _end_turn_queued:
		return
	_end_turn_queued = true
	await get_tree().process_frame
	if main.current_turn == "white" and not main.game_over_flag:
		main.end_turn()
	_end_turn_queued = false

# ══════════════════════════════════════════════════════════
# KENJI SCRIPTED MOVES (run at start of HIS turn)
# ══════════════════════════════════════════════════════════
func _execute_kenji_scripted_move(move_data: Dictionary) -> void:
	_kenji_move_pending = true
	await get_tree().create_timer(0.8).timeout
	if main.game_over_flag:
		_kenji_move_pending = false
		return
	var from_pos: Vector2i = move_data["from"]
	var to_pos: Vector2i = move_data["to"]
	var gm = main.grid_manager
	var piece: Dictionary = gm.get_piece_at(from_pos)
	if piece.is_empty():
		_kenji_move_pending = false
		return

	gm.move_piece(from_pos, to_pos)
	main.piece_moved.emit(piece.type, from_pos, to_pos)
	_record_kenji_move(piece.type, from_pos, to_pos)

	if current_step == 7:
		_force_trap_trigger(to_pos)

	_kenji_move_pending = false

	var step: Dictionary = _steps[current_step]
	var text: String = move_data.get("kenji_text", "")
	if text != "":
		_show_kenji(text, step.step_type == "watch")

	await get_tree().create_timer(0.5).timeout
	if not main.game_over_flag and main.current_turn == "black":
		main.end_turn()

func _record_kenji_move(ptype: int, from_pos: Vector2i, to_pos: Vector2i) -> void:
	main.last_move = {
		"mover": "black", "piece_type": ptype,
		"from_pos": from_pos, "to_pos": to_pos,
		"was_capture": false, "captured_piece": {},
		"was_castle": false, "castle_data": {},
	}
	main.last_move_by_player["black"] = main.last_move.duplicate(true)

func _force_trap_trigger(pos: Vector2i) -> void:
	for i in range(main.traps.size()):
		var trap = main.traps[i]
		if trap.position == pos:
			main.traps.remove_at(i)
			main.grid_manager.destroy_piece(pos)
			main.on_piece_destroyed(pos)
			main.trap_triggered.emit(trap.type, pos, "detonated")
			main.ui_message.emit("Landmine detonated!")
			main.board_ui._redraw()
			return

# ══════════════════════════════════════════════════════════
# REVERSE STEP (index 8)
# ══════════════════════════════════════════════════════════
func _setup_reverse_phase() -> void:
	_lock_all_input()
	main.set_phase(main.GamePhase.SPECIAL_CARD)
	var hand: Array = main.get_active_hand()
	for i in range(hand.size()):
		if hand[i].name == "Reverse":
			_unlock_card(i)
			break

# ══════════════════════════════════════════════════════════
# STEP 9 -- FREE PLAY
# ══════════════════════════════════════════════════════════
func _prepare_step_9_board() -> void:
	var gm = main.grid_manager
	gm.board.clear()
	_place_piece(gm, Vector2i(5, 1), main.PieceType.KING, "white")
	# TUTORIAL HOOK: Queen at (4,8) for two-move capture path to (5,10)
	# Move 1: (4,8)->(4,9) ortho, Move 2: (4,9)->(5,10) diag capture
	_place_piece(gm, Vector2i(4, 8), main.PieceType.QUEEN, "white")
	_place_piece(gm, Vector2i(7, 8), main.PieceType.ROOK, "white")
	_place_piece(gm, Vector2i(5, 10), main.PieceType.KING, "black")
	_place_piece(gm, Vector2i(8, 10), main.PieceType.ROOK, "black")
	_step_10_rook_col = 8
	_step_10_rook_direction = -1

	main.white_hand.clear()
	main.white_hand.append(main.make_card("4", main.CardType.NUMBER, main.CardColor.RED, 4))
	main.white_hand.append(main.make_card("5", main.CardType.NUMBER, main.CardColor.BLUE, 5))
	main.white_hand.append(main.make_card("3", main.CardType.NUMBER, main.CardColor.GREEN, 3))
	main.black_hand.clear()

	main.shared_deck.clear()
	for _i in range(30):
		main.shared_deck.append(main.make_card("1", main.CardType.NUMBER, main.CardColor.YELLOW, 1))

	main.refresh_hand_ui()
	main.board_ui._redraw()

func _do_step_9_kenji_move() -> void:
	if not active or not free_play:
		return
	await get_tree().create_timer(1.0).timeout
	if main.game_over_flag or main.current_turn != "black":
		return
	var gm = main.grid_manager

	# TUTORIAL HOOK: Kenji ignores check in free-play -- rook shuffle only

	# Terrible rook shuffle -- NEVER onto an occupied square (his own King lives on row 10!)
	var from_col: int = _step_10_rook_col
	var to_col: int = from_col + _step_10_rook_direction
	if to_col < 1 or to_col > 8 or not gm.is_square_empty(Vector2i(to_col, 10)):
		_step_10_rook_direction *= -1
		to_col = from_col + _step_10_rook_direction
	var from_pos := Vector2i(from_col, 10)
	var to_pos := Vector2i(to_col, 10)
	var piece: Dictionary = gm.get_piece_at(from_pos)
	if piece.is_empty() or to_col < 1 or to_col > 8 or not gm.is_square_empty(to_pos):
		main.end_turn()
		return
	gm.move_piece(from_pos, to_pos)
	main.piece_moved.emit(piece.type, from_pos, to_pos)
	_record_kenji_move(piece.type, from_pos, to_pos)
	_step_10_rook_col = to_col
	main.board_ui._redraw()
	main.end_turn()

# ══════════════════════════════════════════════════════════
# INPUT LOCKDOWN / UNLOCK
# ══════════════════════════════════════════════════════════
func _lock_all_input() -> void:
	if main.hand_container:
		for child in main.hand_container.get_children():
			if child.has_method("setup"):
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disable_game_hud_buttons(true)
	main.board_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unlock_all_input() -> void:
	if main.hand_container:
		for child in main.hand_container.get_children():
			if child.has_method("setup"):
				child.mouse_filter = Control.MOUSE_FILTER_STOP
	_disable_game_hud_buttons(false)
	main.board_ui.mouse_filter = Control.MOUSE_FILTER_STOP

func _disable_game_hud_buttons(dis: bool) -> void:
	if main.game_hud == null:
		return
	var hud = main.game_hud
	var buttons := [
		hud.get_node_or_null("PhaseButtons/ConfirmCards"),
		hud.get_node_or_null("PhaseButtons/SkipMovement"),
		hud.get_node_or_null("PhaseButtons/SkipSpecial"),
		hud.get_node_or_null("PhaseButtons/EndTurn"),
		hud.get_node_or_null("ResignButton"),
		hud.get_node_or_null("CastleRow/CastleKingside"),
		hud.get_node_or_null("CastleRow/CastleQueenside"),
	]
	for btn in buttons:
		if btn:
			btn.disabled = dis

func _unlock_card(index: int, with_pointer: bool = true) -> void:
	if main.hand_container == null:
		return
	var children = main.hand_container.get_children()
	if index >= 0 and index < children.size():
		var card_ui = children[index]
		card_ui.mouse_filter = Control.MOUSE_FILTER_STOP
		_start_pulse(card_ui)
		if with_pointer:
			_show_pointer_on_card(index)

func _unlock_number_cards() -> void:
	var hand: Array = main.get_active_hand()
	for i in range(hand.size()):
		if hand[i].type == main.CardType.NUMBER and not hand[i].get("locked", false):
			_unlock_card(i, false)

func _unlock_trap_card() -> void:
	var hand: Array = main.get_active_hand()
	for i in range(hand.size()):
		if hand[i].name == "Landmine":
			_unlock_card(i)
			return

func _unlock_button(btn_name: String) -> void:
	if main.game_hud == null:
		return
	var btn_map := {
		"confirm": "PhaseButtons/ConfirmCards",
		"skip_move": "PhaseButtons/SkipMovement",
		"skip_special": "PhaseButtons/SkipSpecial",
		"end_turn": "PhaseButtons/EndTurn",
	}
	var path: String = btn_map.get(btn_name, "")
	if path == "":
		return
	var btn: Button = main.game_hud.get_node_or_null(path)
	if btn:
		btn.disabled = false
		_start_pulse(btn)

func _highlight_board_square(pos: Vector2i, on: bool) -> void:
	var board_ui = main.board_ui
	if on:
		board_ui.mouse_filter = Control.MOUSE_FILTER_STOP
		var found := false
		for m in board_ui.highlighted_moves:
			if m.to_pos == pos:
				found = true
				break
		if not found:
			board_ui.highlighted_moves.append({"to_pos": pos, "is_capture": false})
		board_ui._redraw()
	else:
		board_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board_ui.highlighted_moves.clear()
		board_ui._redraw()

# ══════════════════════════════════════════════════════════
# KENJI BOX -- text + tap indicator
# ══════════════════════════════════════════════════════════
func _show_kenji(text: String, tap_to_continue: bool) -> void:
	if kenji_box == null:
		return
	_tap_advances = tap_to_continue
	var final_text := text
	if tap_to_continue:
		final_text += "\n\n▼ tap to continue ▼"
	kenji_box.show_text(final_text, tap_to_continue)
	if tap_to_continue:
		kenji_box.pivot_offset = kenji_box.size / 2.0
		_start_pulse(kenji_box)

func _on_kenji_box_tapped() -> void:
	if not active or free_play:
		return
	if not _tap_advances:
		return
	_tap_advances = false
	_stop_pulses()
	_advance_step()

# ══════════════════════════════════════════════════════════
# PULSE & POINTER
# ══════════════════════════════════════════════════════════
func _start_pulse(target: Control) -> void:
	var glow := create_tween()
	glow.set_loops()
	glow.tween_property(target, "self_modulate", Color(1.0, 0.82, 0.2, 0.95), 0.45)
	glow.tween_property(target, "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.45)
	_scale_tweens.append(glow)

	var st := create_tween()
	st.set_loops()
	st.tween_property(target, "scale", Vector2(1.06, 1.06), 0.45).set_ease(Tween.EASE_OUT)
	st.tween_property(target, "scale", Vector2(1.0, 1.0), 0.45).set_ease(Tween.EASE_IN)
	_scale_tweens.append(st)
	_pulsed_targets.append(target)

func _show_pointer_on_card(index: int) -> void:
	_remove_pointer()
	if main.hand_container == null:
		return
	var children = main.hand_container.get_children()
	if index < 0 or index >= children.size():
		return
	var card_ui: Control = children[index]
	_pointer = Control.new()
	_pointer.name = "TutorialPointer"
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_ui.add_child(_pointer)
	var label := Label.new()
	label.text = "v"
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2, 1.0))
	label.add_theme_font_size_override("font_size", 20)
	_pointer.add_child(label)
	_pointer.set_position(Vector2(card_ui.size.x / 2.0 - 8.0, -24.0))
	var bounce := create_tween()
	bounce.set_loops()
	bounce.tween_property(_pointer, "position:y", -32.0, 0.5).set_ease(Tween.EASE_OUT)
	bounce.tween_property(_pointer, "position:y", -20.0, 0.5).set_ease(Tween.EASE_IN)

func _remove_pointer() -> void:
	if _pointer and is_instance_valid(_pointer):
		_pointer.queue_free()
	_pointer = null

func _stop_pulses() -> void:
	for st in _scale_tweens:
		if st and st.is_valid():
			st.kill()
	_scale_tweens.clear()
	for t in _pulsed_targets:
		if is_instance_valid(t):
			t.self_modulate = Color.WHITE
			t.scale = Vector2.ONE
	_pulsed_targets.clear()
	_remove_pointer()

# ══════════════════════════════════════════════════════════
# SIGNAL HANDLERS
# ══════════════════════════════════════════════════════════
func _on_turn_started(player: String, _turn: int) -> void:
	if not active:
		return
	if free_play:
		if player == "black":
			_do_step_9_kenji_move()
		return

	await get_tree().process_frame
	if free_play:
		return
	_reapply_step_locks()

	var step: Dictionary = _steps[current_step]
	if player == "black":
		if step.step_type in ["watch", "watch_then_reverse"] \
		and step.has("kenji_scripted_move") and not _kenji_move_pending:
			_execute_kenji_scripted_move(step.kenji_scripted_move)
		elif step.step_type not in ["watch", "watch_then_reverse"]:
			# Nothing scripted -- Kenji passes politely
			await get_tree().create_timer(0.5).timeout
			if main.current_turn == "black" and not main.game_over_flag:
				main.end_turn()
	elif player == "white":
		# TUTORIAL HOOK: auto-advance after Kenji's mine detonation
		if step.step_type == "watch" and current_step == 7:
			_advance_step()
		elif step.step_type == "watch_then_reverse" and not _kenji_move_pending and current_step == 8:
			_setup_reverse_phase()

func _reapply_step_locks() -> void:
	if free_play:
		return
	_lock_all_input()
	var step: Dictionary = _steps[current_step]
	match step.step_type:
		"card_click":
			_unlock_card(step.target_card_index)
		"button_press":
			_unlock_button(step.target_button)
		"board_move":
			_awaiting_piece_select = true
			_awaiting_move_target = false
			if main.current_turn == "white":
				_prep_white_action()
			_highlight_board_square(step.target_piece, true)
		"multi_card":
			_unlock_number_cards()
			_unlock_button("confirm")
		"trap_place":
			_unlock_trap_card()
			call_deferred("_enter_special_phase")
			_highlight_board_square(step.target_trap_pos, true)

func _on_piece_moved(_piece_type: int, from_pos: Vector2i, to_pos: Vector2i) -> void:
	if not active or _kenji_move_pending or free_play:
		return
	var step: Dictionary = _steps[current_step]
	if step.get("advance_on", "") == "piece_moved" and step.step_type == "board_move" \
	and from_pos == step.target_piece and to_pos == step.target_dest:
		_stop_pulses()
		_highlight_board_square(Vector2i(-1, -1), false)
		_advance_step()
		_queue_end_white_turn()

func _on_capture_made(_pos: Vector2i, _bounty: int) -> void:
	if not active or _kenji_move_pending or free_play:
		return
	var step: Dictionary = _steps[current_step]
	if step.get("advance_on", "") == "capture_made":
		_stop_pulses()
		_highlight_board_square(Vector2i(-1, -1), false)
		_advance_step()
		_queue_end_white_turn()

func _on_trap_placed(_trap_type: String) -> void:
	if not active or free_play:
		return
	var step: Dictionary = _steps[current_step]
	if step.get("advance_on", "") == "trap_placed":
		_stop_pulses()
		_highlight_board_square(Vector2i(-1, -1), false)
		_advance_step()
		# NOTE: no end_turn here -- place_trap ends the turn itself.

func _on_energy_confirmed(_amount: int, _bonus: int) -> void:
	if not active or free_play:
		return
	var step: Dictionary = _steps[current_step]
	if step.get("advance_on", "") == "energy_confirmed":
		_stop_pulses()
		_advance_step()

func _on_card_played(card_name: String, _player: String) -> void:
	if not active or free_play:
		return
	var step: Dictionary = _steps[current_step]
	if step.get("advance_on", "") == "reverse_played" and card_name == "Reverse":
		_stop_pulses()
		_advance_step()

func _on_game_over(winner: String, _reason: String, _data: Dictionary) -> void:
	if not active or not free_play:
		return
	if winner == "white":
		_show_kenji("You are ready. Face me for real -- in the Ladder.", false)
		Progression.tutorial_complete = true
		Progression.save_progress()
		if main.game_over_screen:
			main.game_over_screen.visible = false
		await get_tree().create_timer(3.0).timeout
		get_tree().change_scene_to_file("res://main_menu.tscn")

# ══════════════════════════════════════════════════════════
# PUBLIC QUERIES (hooks in main_game / board_ui)
# ══════════════════════════════════════════════════════════
func is_board_pos_allowed(pos: Vector2i) -> bool:
	if not active:
		return true
	if free_play:
		return true
	var step: Dictionary = _steps[current_step]
	match step.step_type:
		"board_move":
			return pos == step.target_piece or pos == step.target_dest
		"trap_place":
			return pos == step.target_trap_pos
	return false

func is_board_interaction_allowed() -> bool:
	if not active or free_play:
		return true
	return _steps[current_step].step_type in ["board_move", "trap_place"]

func is_card_allowed(index: int) -> bool:
	if not active or free_play:
		return true
	var step: Dictionary = _steps[current_step]
	var hand: Array = main.get_active_hand()
	if index < 0 or index >= hand.size():
		return false
	match step.step_type:
		"card_click":
			return index == step.target_card_index
		"multi_card":
			return hand[index].type == main.CardType.NUMBER and not hand[index].get("locked", false)
		"trap_place":
			return hand[index].name == "Landmine"
		"watch_then_reverse":
			return hand[index].name == "Reverse"
	return false

func is_button_allowed(btn_name: String) -> bool:
	if not active or free_play:
		return true
	var step: Dictionary = _steps[current_step]
	if step.step_type == "button_press":
		return btn_name == step.target_button
	if step.step_type == "multi_card":
		return btn_name == "confirm"
	return false

func notify_board_click(pos: Vector2i) -> void:
	if not active or free_play:
		return
	var step: Dictionary = _steps[current_step]
	if step.step_type == "board_move":
		if _awaiting_piece_select and pos == step.target_piece:
			_awaiting_piece_select = false
			_awaiting_move_target = true
			call_deferred("_set_tutorial_move_highlight")
		elif _awaiting_move_target and pos == step.target_dest:
			_awaiting_move_target = false
			main.execute_move(step.target_piece, pos)

func _set_tutorial_move_highlight() -> void:
	if not active or free_play:
		return
	var s: Dictionary = _steps[current_step]
	if s.step_type == "board_move" and _awaiting_move_target:
		var bui = main.board_ui
		var cap: bool = not main.grid_manager.get_piece_at(s.target_dest).is_empty()
		bui.highlighted_moves.clear()
		bui.highlighted_moves.append({"to_pos": s.target_dest, "is_capture": cap})
		bui._redraw()

func notify_card_clicked(index: int) -> void:
	if not active or free_play:
		return
	var step: Dictionary = _steps[current_step]
	if step.step_type == "card_click" and step.get("advance_on", "") == "card_staged":
		if index == step.target_card_index:
			_stop_pulses()
			call_deferred("_advance_step")
