extends Control
# Phase 4 — Visual board rendering & click routing (no rule logic)

const COLS := 8
const ROWS := 10
const MIN_TILE := 32.0
const MAX_TILE := 72.0

const PIECE_GLYPHS := {
	0: "P", 1: "N", 2: "B", 3: "R", 4: "Q", 5: "K",
}

const LIGHT_SQ := Color(0.93, 0.86, 0.71)
const DARK_SQ := Color(0.55, 0.45, 0.33)
const SELECT_TINT := Color(1.0, 0.92, 0.2, 0.45)
const MOVE_TINT := Color(0.2, 0.85, 0.35, 0.4)
const CAPTURE_RING := Color(0.9, 0.15, 0.15, 0.55)
const COORD_COLOR := Color(0.0, 0.0, 0.0, 0.4)
const TRAP_HOVER := Color(0.9, 0.2, 0.2, 0.35)
const FROZEN_TINT := Color(0.45, 0.78, 0.95, 0.5)

var main: Node2D
var grid_manager: Node2D

var tile_size: float = 64.0
var selected_pos: Vector2i = Vector2i(-1, -1)
var highlighted_moves: Array = []
var trap_hover_pos: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	main = get_parent().get_parent().get_parent().get_parent().get_parent() as Node2D
	grid_manager = main.get_node("GridManager") as Node2D
	mouse_filter = Control.MOUSE_FILTER_STOP

	main.piece_moved.connect(func(_t, _f, _to): _redraw())
	main.capture_made.connect(func(_p, _b): _redraw())
	main.trap_triggered.connect(func(_t, _p, _r): _redraw())
	main.turn_started.connect(func(_p, _t): _clear_selection(); _redraw())
	main.phase_changed.connect(func(_phase): _on_phase_changed(_phase))

	get_parent().resized.connect(_fit_board)
	call_deferred("_fit_board")

func _fit_board() -> void:
	var avail: Vector2 = get_parent().size
	if avail.x <= 0.0 or avail.y <= 0.0:
		avail = get_viewport_rect().size - Vector2(320.0, 16.0)
	tile_size = clampf(floorf(minf(avail.x / COLS, avail.y / ROWS)), MIN_TILE, MAX_TILE)
	custom_minimum_size = Vector2(COLS, ROWS) * tile_size
	size = custom_minimum_size
	_redraw()

func _display_row_for_board_row(board_row: int) -> int:
	return ROWS - board_row

func _board_row_for_display_row(display_row: int) -> int:
	return ROWS - display_row

func _on_phase_changed(phase: int) -> void:
	if phase != main.GamePhase.MOVE_PIECE:
		_clear_selection()
		_redraw()

func _clear_selection() -> void:
	selected_pos = Vector2i(-1, -1)
	highlighted_moves.clear()

func clear_trap_hover() -> void:
	trap_hover_pos = Vector2i(-1, -1)
	_redraw()

func _redraw() -> void:
	queue_redraw()

func _draw() -> void:
	if grid_manager == null:
		return

	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(tile_size * 0.5)
	var coord_size: int = maxi(int(tile_size * 0.2), 9)

	for display_row in range(ROWS):
		var board_row := _board_row_for_display_row(display_row)
		for col in range(1, COLS + 1):
			var board_pos := Vector2i(col, board_row)
			var tile_origin := Vector2((col - 1) * tile_size, display_row * tile_size)
			var tile_rect := Rect2(tile_origin, Vector2(tile_size, tile_size))

			var is_light := (col + board_row) % 2 == 0
			draw_rect(tile_rect, LIGHT_SQ if is_light else DARK_SQ)

			if grid_manager.board.has(board_pos):
				var frozen_check: Dictionary = grid_manager.board[board_pos]
				if frozen_check.get("frozen_turns", 0) > 0:
					draw_rect(tile_rect, FROZEN_TINT, true)

			if board_pos == selected_pos:
				draw_rect(tile_rect, SELECT_TINT, true)

			if board_pos == trap_hover_pos:
				draw_rect(tile_rect, TRAP_HOVER, true)

			for move in highlighted_moves:
				if move.to_pos == board_pos:
					if move.get("is_capture", false):
						draw_rect(tile_rect, CAPTURE_RING, false, 3.0)
					else:
						draw_rect(tile_rect, MOVE_TINT, true)

			if col == 1:
				draw_string(font, tile_origin + Vector2(2.0, coord_size + 1.0),
						str(board_row), HORIZONTAL_ALIGNMENT_LEFT, -1, coord_size, COORD_COLOR)
			if board_row == 1:
				draw_string(font, tile_origin + Vector2(tile_size - coord_size * 0.8, tile_size - 3.0),
						char(96 + col), HORIZONTAL_ALIGNMENT_LEFT, -1, coord_size, COORD_COLOR)

			if grid_manager.board.has(board_pos):
				var piece: Dictionary = grid_manager.board[board_pos]
				var glyph: String = PIECE_GLYPHS.get(piece.type, "?")
				var text_color := Color.WHITE if piece.owner == "white" else Color(0.12, 0.12, 0.12)
				var outline := Color(0.1, 0.1, 0.1) if piece.owner == "white" else Color(0.85, 0.85, 0.85)
				var text_pos := tile_origin + Vector2(tile_size * 0.5 - font_size * 0.3, tile_size * 0.5 + font_size * 0.35)
				draw_string(font, text_pos + Vector2(1, 1), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline)
				draw_string(font, text_pos, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if tile_size <= 0.0:
			return
		var local: Vector2 = event.position
		var col := int(local.x / tile_size) + 1
		var display_row := int(local.y / tile_size)
		if col < 1 or col > COLS or display_row < 0 or display_row >= ROWS:
			if trap_hover_pos != Vector2i(-1, -1):
				trap_hover_pos = Vector2i(-1, -1)
				_redraw()
			return
		var board_pos := Vector2i(col, _board_row_for_display_row(display_row))
		var should_hover: bool = main.pending_trap_type != "" and grid_manager.is_square_empty(board_pos)
		for trap in main.traps:
			if trap.position == board_pos:
				should_hover = false
				break
		# TUTORIAL HOOK: only show hover on director-approved square
		if should_hover and main.tutorial_active:
			var td = main.get_node_or_null("TutorialDirector")
			if td and td.has_method("is_board_pos_allowed") and not td.is_board_pos_allowed(board_pos):
				should_hover = false
		if should_hover:
			if trap_hover_pos != board_pos:
				trap_hover_pos = board_pos
				_redraw()
		else:
			if trap_hover_pos != Vector2i(-1, -1):
				trap_hover_pos = Vector2i(-1, -1)
				_redraw()
		return

	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if tile_size <= 0.0:
		return

	var local := mb.position
	var col := int(local.x / tile_size) + 1
	var display_row := int(local.y / tile_size)
	if col < 1 or col > COLS or display_row < 0 or display_row >= ROWS:
		return

	var board_pos := Vector2i(col, _board_row_for_display_row(display_row))
	_handle_board_click(board_pos)
	accept_event()

func _handle_board_click(board_pos: Vector2i) -> void:
	# TUTORIAL HOOK -- gate board clicks through the director
	if main.tutorial_active:
		var td = main.get_node_or_null("TutorialDirector")
		if td and td.has_method("is_board_interaction_allowed"):
			if not td.is_board_interaction_allowed():
				return
		if td.has_method("is_board_pos_allowed") and not td.is_board_pos_allowed(board_pos):
			return
		if td.has_method("notify_board_click"):
			td.notify_board_click(board_pos)

	if main.pending_trap_type != "":
		main.place_trap(board_pos)
		_redraw()
		return

	if main.pending_amaterasu:
		main.bless_piece(board_pos)
		_redraw()
		return

	if main.game_phase != main.GamePhase.MOVE_PIECE:
		return

	for move in highlighted_moves:
		if move.to_pos == board_pos:
			if main.execute_move(selected_pos, board_pos):
				_clear_selection()
				_redraw()
			return

	var piece: Dictionary = grid_manager.get_piece_at(board_pos)
	if not piece.is_empty() and piece.owner == main.current_turn:
		selected_pos = board_pos
		highlighted_moves = grid_manager.get_moves_for(board_pos)
		_redraw()
		return

	_clear_selection()
	_redraw()
