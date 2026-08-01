extends Node

# Bot difficulty levels
enum Difficulties { EASY, MEDIUM, AGGRESSIVE }

@export var current_difficulty: Difficulties = Difficulties.MEDIUM

# Signal to communicate selected bot move to MainGame.gd
signal bot_move_selected(move_data: Dictionary)

# Piece valuation table for chess heuristics
const PIECE_VALUES = {
	"pawn": 100,
	"knight": 320,
	"bishop": 330,
	"rook": 500,
	"queen": 900,
	"king": 20000
}

# Public entry point called by MainGame.gd when it's the Bot's turn
func trigger_bot_action(board_state: Dictionary, bot_hand: Array, bot_energy: int) -> void:
	var selected_action = evaluate_moves_and_cards(board_state, bot_hand, bot_energy)
	if not selected_action.is_empty():
		emit_signal("bot_move_selected", selected_action)
	else:
		# Fallback pass/end turn if no valid moves or cards exist
		emit_signal("bot_move_selected", {"type": "PASS"})

# Core evaluation dispatcher
func evaluate_moves_and_cards(board_state: Dictionary, bot_hand: Array, bot_energy: int) -> Dictionary:
	var legal_moves = _get_legal_chess_moves(board_state)
	var card_plays = _get_available_card_plays(bot_hand, bot_energy, board_state)
	
	match current_difficulty:
		Difficulties.EASY:
			return _select_easy_move(legal_moves, card_plays)
		Difficulties.MEDIUM:
			return _select_medium_move(legal_moves, card_plays, board_state)
		Difficulties.AGGRESSIVE:
			return _select_aggressive_move(legal_moves, card_plays, board_state)
			
	return {}

# --- HELPER 1: CHESS MOVE EVALUATION ---
func _get_legal_chess_moves(board_state: Dictionary) -> Array:
	var moves = []
	if board_state.has("bot_pieces"):
		for piece in board_state["bot_pieces"]:
			if is_instance_valid(piece) and piece.has_method("get_legal_moves"):
				var valid_tiles = piece.get_legal_moves(board_state)
				for tile in valid_tiles:
					moves.append({
						"type": "CHESS_MOVE",
						"piece": piece,
						"from_pos": piece.board_position,
						"to_pos": tile,
						"target_piece": board_state["grid"].get(tile, null)
					})
	return moves

# --- HELPER 2: CARD PLAY EVALUATION ---
func _get_available_card_plays(bot_hand: Array, bot_energy: int, board_state: Dictionary) -> Array:
	var plays = []
	for card in bot_hand:
		if is_instance_valid(card) and card.energy_cost <= bot_energy:
			plays.append({
				"type": "CARD_PLAY",
				"card": card,
				"card_type": card.card_type,
				"energy_cost": card.energy_cost
			})
	return plays

# --- DIFFICULTY STRATEGIES ---

func _select_easy_move(moves: Array, cards: Array) -> Dictionary:
	var all_actions = moves + cards
	if all_actions.size() > 0:
		return all_actions[randi() % all_actions.size()]
	return {}

func _select_medium_move(moves: Array, cards: Array, board_state: Dictionary) -> Dictionary:
	var best_action = {}
	var highest_score = -999999
	
	for move in moves:
		var score = 0
		if move["target_piece"] != null:
			score += PIECE_VALUES.get(move["target_piece"].piece_type, 100)
		score += 10 - int(abs(move["to_pos"].x - 4) + abs(move["to_pos"].y - 4))
		
		if score > highest_score:
			highest_score = score
			best_action = move
			
	for card_play in cards:
		var card_score = 150
		if card_play["card_type"] == "DRAW_TWO":
			card_score += 200
		elif card_play["card_type"] == "SKIP":
			card_score += 250
			
		if card_score > highest_score:
			highest_score = card_score
			best_action = card_play
			
	return best_action if not best_action.is_empty() else _select_easy_move(moves, cards)

func _select_aggressive_move(moves: Array, cards: Array, board_state: Dictionary) -> Dictionary:
	var best_action = {}
	var highest_impact = -999999
	
	for card_play in cards:
		var impact = 300
		if card_play["card_type"] in ["DRAW_FOUR", "WILD_DISRUPT"]:
			impact = 1000
		if impact > highest_impact:
			highest_impact = impact
			best_action = card_play
			
	for move in moves:
		var impact = 0
		if move["target_piece"] != null:
			impact = PIECE_VALUES.get(move["target_piece"].piece_type, 100) * 2
			
		if impact > highest_impact:
			highest_impact = impact
			best_action = move
			
	return best_action if not best_action.is_empty() else _select_easy_move(moves, cards)
