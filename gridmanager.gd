extends Node2D
# ═══════════════════════════════════════════════════════════════════
# UNOCHESS — gridmanager.gd · v1.6.4 "Ponytail Cut"
# Board state · Spatial queries · Chess-legality engine
# Full 17-method contract (maingame.md §13) + hash/reset debts PAID
# ═══════════════════════════════════════════════════════════════════

enum PieceType { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING }

const BOARD_COLS := 8   # columns 1..8
const BOARD_ROWS := 10  # rows 1..10 (White home = 1-2, Black home = 9-10)

const DIRS_ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIRS_DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const DIRS_ALL := DIRS_ORTHO + DIRS_DIAG
const KNIGHT_JUMPS := [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
]

const FLING_RADIUS := {0: 99, 1: 6, 2: 6, 3: 4, 4: 2, 5: 1}
# Pawn=🪶anywhere · Knight/Bishop=6 · Rook=4 · Queen=2 · King=⚓1

# board: Vector2i(col, row) → {type: PieceType, owner: String, has_moved: bool}
var board: Dictionary = {}

@onready var main = get_parent()  # maingame.gd — read-only (frozen_pieces, stadium)

func _ready():
	setup_board()

# ══════════════════════════════════════════════════════════
# SETUP & RESET (Rulebook §1.1)
# ══════════════════════════════════════════════════════════
func setup_board():
	# TUTORIAL HOOK -- fix 2: director sets up tutorial board
	if main and main.tutorial_active:
		return
	board.clear()
	var back := [PieceType.ROOK, PieceType.KNIGHT, PieceType.BISHOP, PieceType.QUEEN,
			PieceType.KING, PieceType.BISHOP, PieceType.KNIGHT, PieceType.ROOK]
	for i in range(8):
		_place(Vector2i(i + 1, 1), back[i], "white")
		_place(Vector2i(i + 1, 2), PieceType.PAWN, "white")
		_place(Vector2i(i + 1, 10), back[i], "black")
		_place(Vector2i(i + 1, 9), PieceType.PAWN, "black")
	print("🏁 Board ready: 8×10, 6 empty middle rows. King on column 5 (e-file).")

func reset_board():
	setup_board()

func _place(pos: Vector2i, type: int, owner: String):
	board[pos] = {"type": type, "owner": owner, "has_moved": false}

# ══════════════════════════════════════════════════════════
# BASIC QUERIES
# ══════════════════════════════════════════════════════════
func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 1 and pos.x <= BOARD_COLS and pos.y >= 1 and pos.y <= BOARD_ROWS

func get_piece_at(pos: Vector2i) -> Dictionary:
	return {"type": board[pos].type, "owner": board[pos].owner} if board.has(pos) else {}

func is_square_empty(pos: Vector2i) -> bool:
	return in_bounds(pos) and not board.has(pos)

func is_owned_by(pos: Vector2i, owner: String) -> bool:
	return board.has(pos) and board[pos].owner == owner

func get_player_pieces(owner: String) -> Array:
	var pieces: Array = []
	for pos in board.keys():
		if board[pos].owner == owner:
			pieces.append({"type": board[pos].type, "position": pos})
	return pieces

func get_king_pos(owner: String) -> Vector2i:
	for pos in board.keys():
		if board[pos].owner == owner and board[pos].type == PieceType.KING:
			return pos
	return Vector2i(-1, -1)

# ══════════════════════════════════════════════════════════
# SPATIAL OPERATIONS
# ══════════════════════════════════════════════════════════
func move_piece(from_pos: Vector2i, to_pos: Vector2i):
	if not board.has(from_pos):
		push_warning("move_piece: no piece at %s" % from_pos)
		return
	if board.has(to_pos):
		print("⚠️ GridManager: overwriting occupant at ", to_pos)
		board.erase(to_pos)
	board[to_pos] = board[from_pos]
	board[to_pos].has_moved = true
	board.erase(from_pos)

func destroy_piece(pos: Vector2i):
	board.erase(pos)

func revive_piece(piece_type: int, pos: Vector2i, owner: String):
	board[pos] = {"type": piece_type, "owner": owner, "has_moved": true}

func promote_piece(pos: Vector2i, new_type: int):
	if board.has(pos):
		board[pos].type = new_type

func fling_to_random_empty(from_pos: Vector2i, piece_type: int = -1) -> Vector2i:
	var piece: Dictionary = get_piece_at(from_pos)
	var radius: int = FLING_RADIUS.get(piece_type, 99)
	var candidates: Array = []
	for x in range(1, BOARD_COLS + 1):
		for y in range(2, BOARD_ROWS):  # SACRED RANKS: rows 1 & 10 excluded for ALL
			var p := Vector2i(x, y)
			if p == from_pos or not is_square_empty(p):
				continue
			if maxi(absi(p.x - from_pos.x), absi(p.y - from_pos.y)) > radius:
				continue
			# ⚓ Anvil clause — King never flung into check (origin vacated in sim)
			if piece_type == PieceType.KING and move_leaves_king_in_check(from_pos, p, piece.owner):
				continue
			candidates.append(p)
	if candidates.is_empty():
		return from_pos  # 💢 spring FAILS under the weight — trap spent, piece stands
	var dest: Vector2i = candidates[randi_range(0, candidates.size() - 1)]
	move_piece(from_pos, dest)
	return dest

# ══════════════════════════════════════════════════════════
# PATH BLOCKING (Rulebook §4.2: no phasing)
# ══════════════════════════════════════════════════════════
func is_path_clear(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	var d := to_pos - from_pos
	if d.x != 0 and d.y != 0 and absi(d.x) != absi(d.y):
		return false
	var step := Vector2i(signi(d.x), signi(d.y))
	var cursor := from_pos + step
	while cursor != to_pos:
		if board.has(cursor):
			return false  # 🧱 frozen pieces block too — they're still THERE
		cursor += step
	return true

# ══════════════════════════════════════════════════════════
# ATTACK & CHECK DETECTION
# NOTE: _attacks ≠ _generate_moves and MUST stay separate —
# pawns attack squares they can't move to. Do not "deduplicate".
# ══════════════════════════════════════════════════════════
func is_square_attacked(pos: Vector2i, by_owner: String) -> bool:
	for from_pos in board.keys():
		var p = board[from_pos]
		# ❄️ frozen pieces project NO threat (§9)
		if p.owner == by_owner and not _is_frozen(from_pos) and _attacks(from_pos, p, pos):
			return true
	return false

func _attacks(from_pos: Vector2i, piece: Dictionary, target: Vector2i) -> bool:
	var dx: int = absi(target.x - from_pos.x)
	var dy: int = target.y - from_pos.y
	var ady: int = absi(dy)
	match piece.type:
		PieceType.PAWN:
			return dx == 1 and dy == (1 if piece.owner == "white" else -1)
		PieceType.KNIGHT:
			return (dx == 1 and ady == 2) or (dx == 2 and ady == 1)
		PieceType.BISHOP:
			return dx == ady and dx > 0 and is_path_clear(from_pos, target)
		PieceType.ROOK:
			return ((dx > 0 and ady == 0) or (ady > 0 and dx == 0)) \
					and is_path_clear(from_pos, target)
		PieceType.QUEEN:
			var lined: bool = (dx == ady and dx > 0) or (dx > 0 and ady == 0) or (ady > 0 and dx == 0)
			return lined and is_path_clear(from_pos, target)
		PieceType.KING:
			return maxi(dx, ady) == 1
	return false

func is_in_check(owner: String) -> bool:
	var king_pos := get_king_pos(owner)
	if king_pos == Vector2i(-1, -1) or _is_frozen(king_pos):
		return false  # ❄️ §9: check PAUSED while King frozen
	return is_square_attacked(king_pos, _opponent(owner))

func move_leaves_king_in_check(from_pos: Vector2i, to_pos: Vector2i, owner: String) -> bool:
	# THE simulation engine — sole owner of apply-test-restore. (Absorbed its twin.)
	if not board.has(from_pos):
		return false
	var mover = board[from_pos]
	var captured = board.get(to_pos)  # null if empty
	board[to_pos] = mover
	board.erase(from_pos)
	var result := is_in_check(owner)
	board[from_pos] = mover
	if captured != null:
		board[to_pos] = captured
	else:
		board.erase(to_pos)
	return result

# ══════════════════════════════════════════════════════════
# LEGAL MOVE GENERATION — ONE pipeline, three contract views
# ══════════════════════════════════════════════════════════
func get_moves_for(pos: Vector2i) -> Array:
	# Geometric candidates, minus frozen movers, minus self-checks.
	if not board.has(pos) or _is_frozen(pos):
		return []
	var legal: Array = []
	for move in _generate_moves(pos, board[pos]):
		if not move_leaves_king_in_check(pos, move.to_pos, board[pos].owner):
			legal.append(move)
	return legal

func get_legal_check_escapes(owner: String) -> Array:
	# Empty array = CHECKMATE (geometry, not wallet — §6.2). Costing is maingame's job.
	var escapes: Array = []
	for from_pos in board.keys():
		if board[from_pos].owner != owner:
			continue
		for move in get_moves_for(from_pos):
			escapes.append({
				"piece_type": board[from_pos].type, "from_pos": from_pos,
				"to_pos": move.to_pos, "is_capture": move.is_capture,
			})
	return escapes

func get_king_safe_squares(owner: String) -> Array:
	# Emergency Protocol destinations — the King's own legal moves. Nothing more.
	var king_pos := get_king_pos(owner)
	if king_pos == Vector2i(-1, -1):
		return []
	var safe: Array = []
	for move in get_moves_for(king_pos):
		safe.append(move.to_pos)
	return safe

func get_all_legal_moves(owner: String) -> Array:
	# Enumerate all legal (from, to) pairs for all pieces of owner. No energy costing.
	var all_moves: Array = []
	for from_pos in board.keys():
		if board[from_pos].owner != owner:
			continue
		for move in get_moves_for(from_pos):
			all_moves.append({
				"from_pos": from_pos,
				"to_pos": move.to_pos,
				"piece_type": board[from_pos].type,
				"is_capture": move.is_capture,
			})
	return all_moves

func _generate_moves(from_pos: Vector2i, piece: Dictionary) -> Array:
	match piece.type:
		PieceType.PAWN:
			var moves: Array = []
			var forward: int = 1 if piece.owner == "white" else -1
			for dist in range(1, _pawn_max_squares() + 1):
				var sq := from_pos + Vector2i(0, forward * dist)
				if not in_bounds(sq) or board.has(sq):
					break  # blocked — no phasing
				moves.append({"to_pos": sq, "is_capture": false})
			for dx in [-1, 1]:
				var sq := from_pos + Vector2i(dx, forward)
				if in_bounds(sq) and board.has(sq) \
						and board[sq].owner != piece.owner and not _is_frozen(sq):
					moves.append({"to_pos": sq, "is_capture": true})
			return moves
		PieceType.KNIGHT:
			return _steps(from_pos, piece.owner, KNIGHT_JUMPS)
		PieceType.BISHOP:
			return _slide(from_pos, piece.owner, DIRS_DIAG)
		PieceType.ROOK:
			return _slide(from_pos, piece.owner, DIRS_ORTHO)
		PieceType.QUEEN:
			return _slide(from_pos, piece.owner, DIRS_ALL)
		PieceType.KING:
			return _steps(from_pos, piece.owner, DIRS_ALL)
	return []

func _steps(from_pos: Vector2i, owner: String, offsets: Array) -> Array:
	# Shared engine for the two step-movers (King, Knight). Twins, merged.
	var moves: Array = []
	for off in offsets:
		var sq: Vector2i = from_pos + off
		if not in_bounds(sq):
			continue
		if board.has(sq):
			if board[sq].owner != owner and not _is_frozen(sq):
				moves.append({"to_pos": sq, "is_capture": true})
		else:
			moves.append({"to_pos": sq, "is_capture": false})
	return moves

func _slide(from_pos: Vector2i, owner: String, dirs: Array) -> Array:
	# ONE direction per move (§4.2). Ray stops at first occupant.
	var moves: Array = []
	for dir in dirs:
		var sq: Vector2i = from_pos + dir
		while in_bounds(sq):
			if board.has(sq):
				if board[sq].owner != owner and not _is_frozen(sq):
					moves.append({"to_pos": sq, "is_capture": true})
				break  # frozen OR friendly OR captured — the wall ends the ray
			moves.append({"to_pos": sq, "is_capture": false})
			sq += dir
	return moves

func _pawn_max_squares() -> int:
	if main and main.has_method("is_stadium_active") \
			and main.is_stadium_active("Pawn's Rebellion"):
		return 3
	return 2

# ══════════════════════════════════════════════════════════
# CASTLING (Rulebook §4.4) — King col 5 · Kingside 5→7/8→6 · Queenside 5→3/1→4
# ══════════════════════════════════════════════════════════
func can_castle(owner: String, side: String) -> bool:
	var row: int = 1 if owner == "white" else 10
	var king_pos := Vector2i(5, row)
	var rook_pos := Vector2i(8, row) if side == "kingside" else Vector2i(1, row)
	if not board.has(king_pos) or board[king_pos].type != PieceType.KING \
			or board[king_pos].owner != owner or board[king_pos].has_moved:
		return false
	if not board.has(rook_pos) or board[rook_pos].type != PieceType.ROOK \
			or board[rook_pos].owner != owner or board[rook_pos].has_moved:
		return false
	if _is_frozen(king_pos) or _is_frozen(rook_pos):
		return false
	var between: Array = [Vector2i(6, row), Vector2i(7, row)] if side == "kingside" \
			else [Vector2i(2, row), Vector2i(3, row), Vector2i(4, row)]
	for sq in between:
		if board.has(sq):
			return false
	var king_path: Array = [Vector2i(5, row), Vector2i(6, row), Vector2i(7, row)] if side == "kingside" \
			else [Vector2i(5, row), Vector2i(4, row), Vector2i(3, row)]
	for sq in king_path:
		if is_square_attacked(sq, _opponent(owner)):
			return false
	return true

func execute_castle_on_board(owner: String, side: String) -> Dictionary:
	var row: int = 1 if owner == "white" else 10
	var data := {
		"king_from": Vector2i(5, row),
		"king_to": Vector2i(7, row) if side == "kingside" else Vector2i(3, row),
		"rook_from": Vector2i(8, row) if side == "kingside" else Vector2i(1, row),
		"rook_to": Vector2i(6, row) if side == "kingside" else Vector2i(4, row),
	}
	move_piece(data.king_from, data.king_to)
	move_piece(data.rook_from, data.rook_to)
	return data

# ══════════════════════════════════════════════════════════
# POSITION HASH — threefold repetition (debt PAID, session 15)
# ══════════════════════════════════════════════════════════
func get_position_hash() -> String:
	var keys: Array = board.keys()
	keys.sort()
	var parts: Array = []
	for pos in keys:
		parts.append("%d,%d:%d%s" % [pos.x, pos.y, board[pos].type, board[pos].owner[0]])
	return ";".join(parts)

# ══════════════════════════════════════════════════════════
# INTERNAL HELPERS
# ══════════════════════════════════════════════════════════
func _is_frozen(pos: Vector2i) -> bool:
	return main and "frozen_pieces" in main and main.frozen_pieces.has(pos)

func _opponent(owner: String) -> String:
	return "black" if owner == "white" else "white"

# ══════════════════════════════════════════════════════════
# DEBUG — headless playtest visualizer
# ══════════════════════════════════════════════════════════
func print_board():
	var glyphs := {PieceType.PAWN: "P", PieceType.KNIGHT: "N", PieceType.BISHOP: "B",
			PieceType.ROOK: "R", PieceType.QUEEN: "Q", PieceType.KING: "K"}
	print("    a  b  c  d  e  f  g  h")
	for row in range(BOARD_ROWS, 0, -1):
		var line := "%2d " % row
		for col in range(1, BOARD_COLS + 1):
			var pos := Vector2i(col, row)
			if board.has(pos):
				var g: String = glyphs[board[pos].type]
				line += " " + (g if board[pos].owner == "white" else g.to_lower()) + " "
			else:
				line += " · "
		print(line) 
