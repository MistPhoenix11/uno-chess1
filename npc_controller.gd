extends Node
# NPC Controller — v0.25.2 "Kenji learns violence — court-corrected edition"
# Fixes over Cascade's run: := inference (6 sites), .piece_type → .type,
# empty-Dictionary check (engine never returns null), "player1" → "white",
# division-by-zero guard on energy_ratio.

var main: Node2D
var grid_manager: Node2D

const PROFILES := {
	"kenji":   {"delay": 1.2, "blunder_rate": 0.40, "pick_from_top": 999},
	"yuki":    {"delay": 1.6, "blunder_rate": 0.15, "pick_from_top": 3},
	"takeshi": {"delay": 2.0, "blunder_rate": 0.05, "pick_from_top": 1},
}

var active_profile := "kenji"

func _ready() -> void:
	main = get_parent()
	main.turn_started.connect(_on_turn_started)
	# NOTE: do NOT grab main.grid_manager here — parent isn't ready yet.

func _on_turn_started(player: String, _turn: int) -> void:
	if not main.bot_players.get(player, false):
		return  # human turn — bot stays silent
	await get_tree().create_timer(PROFILES[active_profile]["delay"]).timeout
	_take_turn(player)

# ── Lazy grid resolution, one door for everyone ──
func _gm() -> Node2D:
	if grid_manager == null:
		grid_manager = main.grid_manager
	if grid_manager == null:
		grid_manager = main.get_node_or_null("GridManager")
	return grid_manager

func _resolve_amaterasu(player: String) -> bool:
	if not main.pending_amaterasu:
		return false
	var gm := _gm()
	if gm == null:
		return false
	var king_pos: Vector2i = gm.get_king_pos(player)
	if king_pos != Vector2i(-1, -1) and main.bless_piece(king_pos):
		print("🤖 Kenji (%s) resolves Amaterasu on King." % player)
		return true
	for pos in gm.board.keys():
		if gm.is_owned_by(pos, player) and main.bless_piece(pos):
			print("🤖 Kenji (%s) resolves Amaterasu on %s." % [player, pos])
			return true
	return false

func _find_random_empty_square() -> Vector2i:
	var gm := _gm()
	if gm == null:
		return Vector2i(-1, -1)
	var empties: Array = []
	for x in range(1, 9):
		for y in range(1, 11):
			var pos := Vector2i(x, y)
			if gm.is_square_empty(pos):
				empties.append(pos)
	if empties.is_empty():
		return Vector2i(-1, -1)
	return empties[randi_range(0, empties.size() - 1)]

func _place_random_trap(player: String) -> bool:
	if main.pending_trap_type == "":
		return false
	var trap_name: String = main.pending_trap_type
	# Engine enforces one-trap-per-square — retry a few times before giving up.
	for _attempt in range(5):
		var pos: Vector2i = _find_random_empty_square()
		if pos == Vector2i(-1, -1):
			return false
		if main.place_trap(pos):
			print("🤖 Kenji (%s) places %s at %s." % [player, trap_name, pos])
			return true
	return false

func _resolve_bot_interrupts(player: String) -> bool:
	var handled := false
	if main.game_phase == main.GamePhase.AWAITING_EMERGENCY_CHOICE:
		main.resolve_emergency_protocol(true)
		print("🤖 Kenji (%s) accepts Emergency Protocol." % player)
		handled = true
	if main.game_phase == main.GamePhase.AWAITING_SKIP_CHOICE:
		main.resolve_skip(false)  # resist=false → accept the skip (engine-verified)
		print("🤖 Kenji (%s) accepts Skip." % player)
		handled = true
	if main.pending_trap_type != "":
		handled = true
		if not _place_random_trap(player):
			main.cancel_trap_placement()
			print("🤖 Kenji (%s) cancels trap placement." % player)
	if main.pending_amaterasu:
		handled = true
		if not _resolve_amaterasu(player):
			print("🤖 Kenji (%s) failed to resolve Amaterasu." % player)
	return handled

func _skip_special_if_still_open() -> void:
	if main.game_phase == main.GamePhase.SPECIAL_CARD:
		main.skip_special_phase()

func _handle_special_phase(player: String) -> void:
	if main.game_phase != main.GamePhase.SPECIAL_CARD:
		return
	var hand: Array = main.get_active_hand()
	var trap_indices: Array = []
	var other_indices: Array = []
	for i in range(hand.size()):
		var scan_card = hand[i]
		if scan_card.type == main.CardType.NUMBER:
			continue
		if scan_card.type == main.CardType.LEGENDARY:
			continue  # v0.3 territory
		if scan_card.name == "Reverse":
			continue  # held pending the window ruling
		if scan_card.locked:
			continue  # bounty lock — engine would reject anyway
		if scan_card.name in main.TRAP_CARDS:
			trap_indices.append(i)
		else:
			other_indices.append(i)

	# Trap branch — 50% chance if any trap is held
	if trap_indices.size() > 0 and randf() <= 0.5:
		var trap_index: int = trap_indices[randi_range(0, trap_indices.size() - 1)]
		var trap_card = hand[trap_index]
		if main.play_special_card(trap_index):
			print("🤖 Kenji (%s) plays special: %s" % [player, trap_card.name])
			if not _place_random_trap(player):
				main.cancel_trap_placement()
				print("🤖 Kenji (%s) cannot place trap — cancelled." % player)
			_skip_special_if_still_open()
		else:
			_skip_special_if_still_open()
		return

	if other_indices.is_empty():
		_skip_special_if_still_open()
		return

	# Non-trap branch — 50% chance, per spec
	if randf() > 0.5:
		_skip_special_if_still_open()
		return

	var pick_index: int = other_indices[randi_range(0, other_indices.size() - 1)]
	var pick_card = hand[pick_index]
	if main.play_special_card(pick_index):
		print("🤖 Kenji (%s) plays special: %s" % [player, pick_card.name])
	else:
		_skip_special_if_still_open()

func score_move(move: Dictionary, player: String, energy: int) -> float:
	var gm := _gm()
	if gm == null:
		return 0.0

	var score: float = 0.0

	# ── Capture scoring ──
	if move.is_capture:
		var piece_at_target: Dictionary = gm.get_piece_at(move.to_pos)
		# Engine returns an EMPTY Dictionary for vacant squares — never null.
		if not piece_at_target.is_empty():
			var piece_type: int = piece_at_target.type  # field is .type, per engine
			# Piece values: pawn=1, knight/bishop=3, rook=5, queen=9
			if piece_type == main.PieceType.PAWN:
				score += 1.0
			elif piece_type == main.PieceType.KNIGHT or piece_type == main.PieceType.BISHOP:
				score += 3.0
			elif piece_type == main.PieceType.ROOK:
				score += 5.0
			elif piece_type == main.PieceType.QUEEN:
				score += 9.0

	# ── Energy efficiency ──
	# Prefer moves that don't burn the whole budget on low-value plays.
	if energy > 0 and score > 0.0:
		var energy_ratio: float = float(move.cost) / float(energy)
		if energy_ratio > 0.0:
			score /= energy_ratio  # cheaper capture of same value = higher score

	# ── Advancement bonus ──
	# Engine speaks "white"/"black". White advances +y, black advances -y.
	var from_y: int = move.from_pos.y
	var to_y: int = move.to_pos.y
	if player == "white":
		if to_y > from_y:
			score += 0.5
	else:
		if to_y < from_y:
			score += 0.5

	return score

func _take_turn(player: String) -> void:
	if main.game_over_flag:
		print("🤖 Kenji (", player, ") aborted: game already over.")
		return

	if main.current_turn != player:
		print("🤖 Kenji (", player, ") aborted: turn mismatch (now ", main.current_turn, ").")
		return

	# ── STAGE ALL NUMBER CARDS (re-scan every pass — index-shift safe) ──
	var staged_values: Array = []
	var staged_refs: Array = []
	var safety := 0

	while safety < 20:
		safety += 1
		var hand: Array = main.get_active_hand()
		var target_index := -1

		for i in range(hand.size()):
			var stage_card = hand[i]
			if stage_card.type == main.CardType.NUMBER and not stage_card.locked and not staged_refs.has(stage_card):
				target_index = i
				break

		if target_index == -1:
			break  # no more stageable number cards

		var chosen_card = main.get_active_hand()[target_index]
		if main.stage_number_card(target_index):
			staged_refs.append(chosen_card)
			staged_values.append(chosen_card.value)
		else:
			break  # engine refused (max reached / phase issue) — stop cleanly

	if staged_values.size() > 0:
		print("🤖 Kenji (%s) staged %d card(s): %s" % [player, staged_values.size(), staged_values])

	# ── INTERRUPT RESOLUTION ──
	if _resolve_bot_interrupts(player):
		if main.game_over_flag or main.current_turn != player:
			return
		if main.game_phase != main.GamePhase.PLAY_CARDS:
			print("🤖 Kenji (%s) interrupt resolved outside PLAY_CARDS (phase=%d). Ending turn." % [player, main.game_phase])
			main.end_turn()
			return

	# ── CONFIRM CARDS FOR ENERGY ──
	if main.game_phase != main.GamePhase.PLAY_CARDS:
		print("🤖 Kenji (%s) warning: not in PLAY_CARDS phase (phase=%d). Ending turn." % [player, main.game_phase])
		main.end_turn()
		return

	main.confirm_cards_and_move()
	var energy: int = main.current_energy
	print("🤖 Kenji (%s) confirmed energy: %d" % [player, energy])

	# ── RESOLVE GRID MANAGER ──
	if _gm() == null:
		print("🤖 Kenji (%s) FATAL: cannot find GridManager. Ending turn." % player)
		main.end_turn()
		return

	# ── ENUMERATE LEGAL MOVES & FILTER AFFORDABLE ──
	if main.game_phase != main.GamePhase.MOVE_PIECE:
		print("🤖 Kenji (%s) warning: not in MOVE_PIECE phase after confirmation. Ending turn." % player)
		main.end_turn()
		return

	var all_legal_moves: Array = _gm().get_all_legal_moves(player)
	var affordable_moves: Array = []

	for move_data in all_legal_moves:
		var move_distance: int = main.calculate_distance(
			move_data.piece_type,
			move_data.from_pos,
			move_data.to_pos,
			move_data.is_capture,
			player
		)
		if move_distance <= 0:
			continue

		var move_cost: int = main.get_move_cost(move_data.piece_type, move_distance, player, move_data.from_pos)
		if move_cost <= energy:
			affordable_moves.append({
				"from_pos": move_data.from_pos,
				"to_pos": move_data.to_pos,
				"piece_type": move_data.piece_type,
				"cost": move_cost,
				"is_capture": move_data.is_capture,
			})

	# ── NO AFFORDABLE MOVES ──
	if affordable_moves.is_empty():
		print("🤖 Kenji (%s) has no affordable moves (energy=%d). Skipping movement phase." % [player, energy])
		main.skip_movement()
		_after_move_wrapup(player)
		return

	# ── SCORE, SORT, SELECT ──
	for move in affordable_moves:
		move["score"] = score_move(move, player, energy)

	affordable_moves.sort_custom(func(a, b): return a.score > b.score)

	var profile: Dictionary = PROFILES[active_profile]
	var blunder_rate: float = profile["blunder_rate"]
	var pick_from_top: int = profile["pick_from_top"]

	var chosen_move: Dictionary
	if randf() <= blunder_rate:
		# Blunder: pick a completely random move
		chosen_move = affordable_moves[randi_range(0, affordable_moves.size() - 1)]
	else:
		# Pick from the top N moves
		var top_count: int = mini(pick_from_top, affordable_moves.size())
		var top_index: int = randi_range(0, top_count - 1)
		chosen_move = affordable_moves[top_index]

	var pname: String = main.piece_name(chosen_move.piece_type)
	print("🤖 Kenji (%s) moves: %s from %s → %s (cost %d, energy left: %d, score %.2f)" % [
		player, pname, chosen_move.from_pos, chosen_move.to_pos,
		chosen_move.cost, energy - chosen_move.cost, chosen_move.score
	])

	if not main.execute_move(chosen_move.from_pos, chosen_move.to_pos):
		print("🤖 Kenji (%s) ERROR: execute_move() returned false. This should not happen." % player)

	_after_move_wrapup(player)

func _after_move_wrapup(player: String) -> void:
	if main.game_phase == main.GamePhase.SPECIAL_CARD:
		_handle_special_phase(player)
	if main.game_over_flag or main.current_turn != player:
		return
	_resolve_bot_interrupts(player)
	if main.game_over_flag or main.current_turn != player:
		return
	_skip_special_if_still_open()
	if main.game_over_flag or main.current_turn != player:
		return
	main.end_turn() 
