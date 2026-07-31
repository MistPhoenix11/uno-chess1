extends Node2D
# ═══════════════════════════════════════════════════════════════════
# UNOCHESS ENGINE — main_game.gd · v1.7.0 "The Rewind Tax"
# Rulebook v1.3 compliant · Patches 1 & 3 merged · Chess Clock integrated
# Rulings baked in: frozen=no-threat · emergency=no-bounty
#   failed Spring/Ice=spent · Landmine=Dud Rule
# Coronation March (Rule C) — survival measured in OPPONENT turns
# Public Gamble Rule — flips visible IFF stake AND outcome are public
# Draw Conditions · Coin Toss (toggle) · Rematch Exorcism
# v1.7.0: Option C Reverse (Rewind Tax) · King Save exception ·
#   return_to_movement escape hatch · greyout leak sealed ·
#   per-player ledger active · fizzle ≠ consumed everywhere
# ═══════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════
# SIGNALS
# ══════════════════════════════════════════════════════════
signal turn_started(player: String, turn_number: int)
signal phase_changed(phase: int)
signal energy_confirmed(amount: int, bonus: int)
signal piece_moved(piece_type: int, from_pos: Vector2i, to_pos: Vector2i)
signal capture_made(pos: Vector2i, bounty_count: int)
signal trap_placed(trap_type: String)  # NO position — secret!
signal trap_triggered(trap_type: String, pos: Vector2i, result: String)
signal card_played(card_name: String, player: String)
signal cards_drawn(player: String, count: int)
signal stadium_changed(stadium_name: String, turns_remaining: int)
signal king_wounded(player: String, wound_count: int)
signal emergency_protocol_offered(player: String)
signal skip_choice_offered(player: String)
signal game_over(winner: String, reason: String, data: Dictionary)
signal ui_message(text: String)

# Animation / VFX Hooks
signal piece_promoted(pos: Vector2i, piece_owner: String)
signal time_stolen(victim: String, amount: float)
signal blessing_applied(pos: Vector2i)
signal legendary_played(card_name: String, player: String)
signal piece_frozen(pos: Vector2i, duration: int)
signal piece_thawed(pos: Vector2i)

# Public Gamble Rule — PUBLIC gambles ONLY. Trap rolls can NEVER use this:
# the emit does not exist in check_trap_trigger. Secrecy by architecture.
signal gamble_flipped(context: String, success: bool)

# Coin Toss (match-start ONLY)
signal coin_flip_started()
signal coin_flip_result(winner: String)  # "player_one" / "player_two"
signal color_chosen(first_player: String)

# ══════════════════════════════════════════════════════════
# ENUMS
# ══════════════════════════════════════════════════════════
enum CardType { NUMBER, TRAP, COUNTER, DISRUPTION, DRAW, UTILITY,
		COMPETITIVE, STADIUM, LEGENDARY }
enum CardColor { RED, BLUE, GREEN, YELLOW, NONE }
enum GamePhase { PRE_MATCH, PLAY_CARDS, MOVE_PIECE, SPECIAL_CARD,
		AWAITING_SKIP_CHOICE, AWAITING_EMERGENCY_CHOICE, END_TURN,
		AWAITING_COLOR_CHOICE }
enum PieceType { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING }

# ══════════════════════════════════════════════════════════
# EXPORTED SETTINGS
# ══════════════════════════════════════════════════════════
@export_group("Match Settings")
@export var starting_time: float = 450.0  # 7.5 min per player
@export var starting_hand_numbers: int = 3
@export var starting_hand_specials: int = 1
@export var end_of_turn_draw: int = 2  # Arsenal overrides → 3
@export var time_steal_amount: float = 30.0
@export var time_steal_floor: float = 10.0  # ⚠️ PLAYTEST-CONDITIONAL. 0.0 = instant-kill allowed
@export var enable_coin_toss: bool = false  # ⚠️ requires UI to call choose_color()!

@export_group("Trap Settings")
@export var landmine_chance: float = 0.50
@export var spring_trap_chance: float = 0.60
@export var ice_trap_chance: float = 0.50
@export var wasteland_bonus: float = 0.15
@export var ice_trap_duration: int = 2

@export_group("Rules Settings")
@export var king_wound_cap: int = 2  # HARD CAP — §9
@export var max_number_cards_per_turn: int = 3
@export var stadium_duration: int = 4
@export var amaterasu_duration: int = 5
@export var castle_base_cost: int = 6  # King 4 + Rook 2
@export var draw_moves_threshold: int = 40  # capture-less turns → forced draw

@export_group("Debug")
@export var debug_infinite_energy: bool = false  # Phase 1 headless testing ONLY

# ══════════════════════════════════════════════════════════
# CONSTANTS
# ══════════════════════════════════════════════════════════
const DEBUG_FORCE_LEGENDARY := ""  # set to "Izanagi" etc. to force-deal. "" = off

const PYRAMID := {1: 5, 2: 4, 3: 4, 4: 3, 5: 2, 6: 2}  # 5/4/4/3/2/2 per color = 20 cards per color
const COLORS := [CardColor.RED, CardColor.BLUE, CardColor.GREEN, CardColor.YELLOW]

const ENERGY_COSTS := {
	PieceType.PAWN: {"per_square": 1, "flat": false, "max_squares": 2},
	PieceType.KNIGHT: {"per_square": 3, "flat": true},
	PieceType.BISHOP: {"per_square": 2, "flat": false},
	PieceType.ROOK: {"per_square": 2, "flat": false},
	PieceType.QUEEN: {"per_square": 3, "flat": false},
	PieceType.KING: {"per_square": 4, "flat": true},
}

const POST_CAPTURE_BLOCKED := ["Discard 4", "Equalize", "Sabotage", "Skip", "+4 Draw"]
const DISRUPTION_CARDS := ["Discard 4", "Equalize", "Sabotage", "Skip"]
const GLOBAL_STADIUMS := ["Wasteland", "War Zone", "Arsenal"]
const TARGETED_STADIUMS := ["Knight's Pride", "Rook's Fortress", "Bishop's Cathedral",
		"Queen's Domain", "King's Sanctuary", "Pawn's Rebellion"]

const BOARD_COLS := 8
const BOARD_ROWS := 10
const PENULT_RANK := {"white": 9, "black": 2}  # promotion geometry (8×10)
const FINAL_RANK := {"white": 10, "black": 1}

const CARD_UI_SCENE := preload("res://card_ui.tscn")
const TRAP_CARDS := ["Landmine", "Spring Trap", "Ice Trap"]

const PIECE_NAMES := ["Pawn", "Knight", "Bishop", "Rook", "Queen", "King"]
const COLOR_NAMES := ["Red", "Blue", "Green", "Yellow", "None"]

# Ladder Constants
const LADDER_START := 100
const LADDER_WIN := 30
const LADDER_LOSS := 15

# ══════════════════════════════════════════════════════════
# NODES
# ══════════════════════════════════════════════════════════
@onready var grid_manager = $GridManager
@onready var chess_clock = $ChessClock
@onready var hand_container = $CanvasLayer/RootHBox/SidebarMargin/GameHUD/HandScroll/HandContainer
@onready var board_ui: Control = $CanvasLayer/RootHBox/BoardPanel/BoardCenter/BoardUI
@onready var game_hud: VBoxContainer = $CanvasLayer/RootHBox/SidebarMargin/GameHUD
@onready var game_over_screen: Control = $CanvasLayer/GameOverScreen

# ══════════════════════════════════════════════════════════
# GAME STATE
# ══════════════════════════════════════════════════════════
var bot_players := {"white": false, "black": true}
var tutorial_active: bool = false  # TUTORIAL HOOK -- set by TutorialDirector
var shared_deck: Array = []
var discard_pile: Array = []
var exiled_cards: Array = []  # Legendaries + Sabotaged. NEVER reshuffled.
var white_hand: Array = []
var black_hand: Array = []

var current_turn: String = "white"
var turn_number: int = 0
var player_turn_count := {"white": 0, "black": 0}
var game_phase: int = GamePhase.PRE_MATCH
var game_over_flag: bool = false
var coin_toss_winner: String = ""  # "player_one" / "player_two" — SEAT, not color

# Mirrors — SOURCE OF TRUTH lives in chess_clock. Kept for read-only convenience.
var white_time: float = 0.0
var black_time: float = 0.0

# Turn-scoped
var staged_cards: Array = []
var current_energy: int = 0
var capture_occurred_this_turn: bool = false
var special_played_this_turn: bool = false
var moved_this_turn: bool = false  # ← OPTION C: the Rewind Tax flag
var was_in_check_at_turn_start: bool = false

# Board-adjacent
var last_move: Dictionary = {}
var last_move_by_player := {"white": {}, "black": {}}  # ⚖️ RULED: Reverse's source of truth
var traps: Array = []  # [{position, type, owner}]
var frozen_pieces: Dictionary = {}  # pos → {turns_remaining, owner}
var king_wounds := {"white": 0, "black": 0}
var promotion_watch: Array = []  # [{position, owner, arrived_opp, rank}]

# Match tracking (Draw Rules & End Screen)
var moves_since_capture: int = 0
var position_history: Dictionary = {}  # hash → count
var draw_offered_by: String = ""
var match_stats := {
	"white": {"captures": 0, "cards_played": 0, "legendaries": 0,
			"traps_placed": 0, "traps_survived": 0, "promotions": 0},
	"black": {"captures": 0, "cards_played": 0, "legendaries": 0,
			"traps_placed": 0, "traps_survived": 0, "promotions": 0},
}

# Card-effect
var reverse_greyout := {"white": false, "black": false}
var skip_debuff := {"white": false, "black": false}
var active_stadium: Dictionary = {}
var amaterasu_blessing: Dictionary = {}
var pending_amaterasu: bool = false
var pending_trap_type: String = ""
var pending_trap_hand_index: int = -1
var susanoo_extra_turn: bool = false
var susanoo_played := {"white": false, "black": false}
var reshuffle_occurred: bool = false

# ══════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════
func _ready():
	randomize()
	cards_drawn.connect(func(_p, _c): refresh_hand_ui())
	card_played.connect(func(_n, _p): refresh_hand_ui())
	turn_started.connect(func(_p, _t): refresh_hand_ui())
	ui_message.connect(game_hud.show_message)
	chess_clock.time_updated.connect(_on_clock_time_updated)
	chess_clock.time_expired.connect(_on_clock_time_expired)
	game_over.connect(_on_game_finished)
	_apply_launch_params()
	initialize_game()

func _apply_launch_params() -> void:
	var mode: String = Progression.next_mode
	match mode:
		"hotseat":
			bot_players = {"white": false, "black": false}
		"tutorial":  # TUTORIAL HOOK -- tutorial drives Kenji, not NPCController
			bot_players = {"white": false, "black": false}
		"vs_bot":
			bot_players = {"white": false, "black": true}
			var npc_controller = get_node_or_null("NPCController")
			if npc_controller != null:
				npc_controller.active_profile = Progression.next_bot_profile

func _on_game_finished(winner: String, _reason: String, _data: Dictionary) -> void:
	# TUTORIAL HOOK -- director handles tutorial wins
	if tutorial_active:
		return
	if Progression.next_mode == "vs_bot" and winner == "white":
		var beaten: String = Progression.next_bot_profile
		Progression.mark_defeated(beaten)
		var next_up: String = {"kenji": "YUKI UNLOCKED! 🌸", "yuki": "TAKESHI UNLOCKED! ⚔️", "takeshi": "LADDER COMPLETE! 🏆"}.get(beaten, "") 
		if next_up != "":
			if game_over_screen != null and game_over_screen.has_method("set_next_up_message"):
				game_over_screen.set_next_up_message(next_up)

func _on_clock_time_updated(w_time: float, b_time: float):
	white_time = w_time
	black_time = b_time
	if game_hud:
		game_hud.update_clock_display(w_time, b_time, current_turn)

func _on_clock_time_expired(player: String):
	declare_winner(opponent_of(player), "%s ran out of time!" % player.capitalize())

func initialize_game():
	game_over_flag = false
	reshuffle_occurred = false
	moves_since_capture = 0
	position_history.clear()
	draw_offered_by = ""

	for player in ["white", "black"]:
		for key in match_stats[player]:
			match_stats[player][key] = 0

	# TUTORIAL HOOK -- fix 2: director handles all initialization
	if tutorial_active:
		return

	build_deck()
	deal_starting_hands()

	if enable_coin_toss:
		print("♟️🎴 UNOCHESS v1.7.0 — Match initialized. Flipping for first move...")
		perform_coin_toss()
	else:
		print("♟️🎴 UNOCHESS v1.7.0 — Match initialized. White to move (coin toss disabled).")
		begin_match()

# ── REMATCH EXORCISM — every ghost from the previous match, banished ──
func rematch():
	reset_match_state()
	initialize_game()

func reset_match_state():
	king_wounds = {"white": 0, "black": 0}
	traps.clear()
	frozen_pieces.clear()
	promotion_watch.clear()
	susanoo_played = {"white": false, "black": false}
	susanoo_extra_turn = false
	active_stadium.clear()
	amaterasu_blessing.clear()
	pending_amaterasu = false
	pending_trap_type = ""
	pending_trap_hand_index = -1
	reverse_greyout = {"white": false, "black": false}
	skip_debuff = {"white": false, "black": false}
	last_move = {}
	last_move_by_player = {"white": {}, "black": {}}
	staged_cards.clear()
	current_energy = 0
	capture_occurred_this_turn = false
	special_played_this_turn = false
	moved_this_turn = false  # ← OPTION C
	was_in_check_at_turn_start = false
	player_turn_count = {"white": 0, "black": 0}
	coin_toss_winner = ""
	grid_manager.reset_board()

# ── COIN TOSS — the ONE ceremonial flip ──
func perform_coin_toss():
	set_phase(GamePhase.PRE_MATCH)
	coin_flip_started.emit()
	coin_toss_winner = "player_one" if randf() <= 0.5 else "player_two"
	print("🪙 COIN TOSS! ", coin_toss_winner.to_upper(), " wins the flip — choose your color.")
	set_phase(GamePhase.AWAITING_COLOR_CHOICE)
	coin_flip_result.emit(coin_toss_winner)

func choose_color(color: String) -> bool:
	if game_phase != GamePhase.AWAITING_COLOR_CHOICE:
		return false
	if color != "white" and color != "black":
		return false
	print("🎨 ", coin_toss_winner.to_upper(), " chooses ", color.to_upper(), ". Let the match begin!")
	color_chosen.emit(color)
	begin_match()
	return true

func begin_match():
	# White ALWAYS moves first — the coin toss decides WHICH SEAT is white.
	current_turn = "white"
	turn_number = 0
	chess_clock.start_match(starting_time, "white")
	start_new_turn()

# ══════════════════════════════════════════════════════════
# DECK CONSTRUCTION
# ══════════════════════════════════════════════════════════
func make_card(cname: String, ctype: int, color: int = CardColor.NONE, value: int = 0) -> Dictionary:
	return {"name": cname, "type": ctype, "color": color, "value": value, "locked": false}

func build_deck():
	# TUTORIAL HOOK -- director builds the deck
	if tutorial_active:
		return
	shared_deck.clear()
	discard_pile.clear()
	exiled_cards.clear()

	for color in COLORS:
		for value in PYRAMID.keys():
			for _i in range(PYRAMID[value]):
				shared_deck.append(make_card(str(value), CardType.NUMBER, color, value))

	for card in select_match_specials():
		shared_deck.append(card)

	shared_deck.shuffle()
	print("🃏 Deck built: ", shared_deck.size(), " cards.")

func _take_pool(names: Array, copies: int, ctype: int, take: int) -> Array:
	var pool: Array = []
	for n in names:
		for _i in range(copies):
			pool.append(make_card(n, ctype))
	pool.shuffle()
	var out: Array = []
	for _i in range(take):
		out.append(pool.pop_back())
	return out

func select_match_specials() -> Array:
	var specials: Array = []

	# TRAPS: 3–4 from pool of 6
	specials += _take_pool(TRAP_CARDS, 2, CardType.TRAP, randi_range(3, 4))

	# COUNTERS: exactly 2 Trap Diffusers — GUARANTEED
	specials.append(make_card("Trap Diffuser", CardType.COUNTER))
	specials.append(make_card("Trap Diffuser", CardType.COUNTER))

	# DISRUPTION: 3–4 from pool of 8
	specials += _take_pool(DISRUPTION_CARDS, 2, CardType.DISRUPTION, randi_range(3, 4))

	# DRAW: 2–3 ×(+2 Draw); 25% chance one +4 Draw
	for _i in range(randi_range(2, 3)):
		specials.append(make_card("+2 Draw", CardType.DRAW))
	if randf() <= 0.25:
		specials.append(make_card("+4 Draw", CardType.DRAW))

	# UTILITY: 4–5 from pool of 8
	specials += _take_pool(["Reverse", "Refresh", "Scavenge", "Trade"], 2, CardType.UTILITY, randi_range(4, 5))

	# TIME STEAL: 50% chance → 2 copies
	if randf() <= 0.50:
		specials.append(make_card("Time Steal", CardType.COMPETITIVE))
		specials.append(make_card("Time Steal", CardType.COMPETITIVE))

	# STADIUMS: 2–3 from pool of 9
	specials += _take_pool(GLOBAL_STADIUMS + TARGETED_STADIUMS, 1, CardType.STADIUM, randi_range(2, 3))

	# LEGENDARIES: independent rolls. NEVER announced.
	if randf() <= 0.10: specials.append(make_card("Izanagi", CardType.LEGENDARY))
	if randf() <= 0.10: specials.append(make_card("Amaterasu", CardType.LEGENDARY))
	if randf() <= 0.05: specials.append(make_card("Susanoo", CardType.LEGENDARY))
	if randf() <= 0.07: specials.append(make_card("Raijin", CardType.LEGENDARY))
	if randf() <= 0.075: specials.append(make_card("Kaguya", CardType.LEGENDARY))

	return specials

func deal_starting_hands():
	# TUTORIAL HOOK -- director sets hands
	if tutorial_active:
		return
	var numbers: Array = []
	var dealable_specials: Array = []
	var legendaries: Array = []
	for card in shared_deck:
		match card.type:
			CardType.NUMBER: numbers.append(card)
			CardType.LEGENDARY: legendaries.append(card)
			_: dealable_specials.append(card)

	numbers.shuffle()
	dealable_specials.shuffle()
	white_hand.clear()
	black_hand.clear()

	for _i in range(starting_hand_numbers):
		white_hand.append(numbers.pop_back())
		black_hand.append(numbers.pop_back())
	for _i in range(starting_hand_specials):
		white_hand.append(dealable_specials.pop_back())
		black_hand.append(dealable_specials.pop_back())

	shared_deck = numbers + dealable_specials + legendaries
	shared_deck.shuffle()
	print("🤝 Starting hands dealt: 3 Number + 1 Special each (no Legendaries).")

	if DEBUG_FORCE_LEGENDARY != "":
		white_hand.append(make_card(DEBUG_FORCE_LEGENDARY, CardType.LEGENDARY))
		print("🐞 DEBUG: forced ", DEBUG_FORCE_LEGENDARY, " into White's hand.")

# ══════════════════════════════════════════════════════════
# DRAWING & RESHUFFLE
# ══════════════════════════════════════════════════════════
func draw_cards(hand: Array, count: int, from_capture: bool = false) -> int:
	# TUTORIAL HOOK -- deterministic draws, never return zero
	if tutorial_active:
		var tdrawn := 0
		for _i in range(count):
			if shared_deck.size() == 0:
				# TUTORIAL HOOK: recycle discard pile when deck exhausted
				if discard_pile.size() > 0:
					for card in discard_pile:
						shared_deck.append(card)
					discard_pile.clear()
				else:
					# TUTORIAL HOOK: deterministic filler when everything exhausted
					shared_deck.append(make_card("1", CardType.NUMBER, CardColor.YELLOW, 1))
			var card = shared_deck.pop_back()
			card.locked = from_capture
			hand.append(card)
			tdrawn += 1
		if tdrawn > 0:
			cards_drawn.emit("white" if hand == white_hand else "black", tdrawn)
		return tdrawn
	var drawn := 0
	for _i in range(count):
		if shared_deck.size() == 0:
			recycle_discard_pile()
			if shared_deck.size() == 0:
				break
		var card = shared_deck.pop_back()
		card.locked = from_capture
		hand.append(card)
		drawn += 1
	if drawn > 0:
		cards_drawn.emit("white" if hand == white_hand else "black", drawn)
	return drawn

func recycle_discard_pile():
	if discard_pile.size() == 0:
		return
	print("♻️ RESHUFFLE! Discard pile becomes the new deck. 🌸 Kaguya is now permanently dead.")
	reshuffle_occurred = true
	shared_deck = discard_pile.duplicate()
	discard_pile.clear()
	shared_deck.shuffle()

# ══════════════════════════════════════════════════════════
# TURN LIFECYCLE
# ══════════════════════════════════════════════════════════
func start_new_turn():
	if game_over_flag:
		return
	turn_number += 1
	player_turn_count[current_turn] += 1

	chess_clock.switch_to(current_turn)

	# Draw offers die when the offerer's turn comes back around
	if draw_offered_by == current_turn:
		draw_offered_by = ""
		ui_message.emit("Your draw offer expired.")

	if staged_cards.size() > 0:
		for card in staged_cards:
			discard_pile.append(card)
		staged_cards.clear()

	current_energy = 0
	capture_occurred_this_turn = false
	special_played_this_turn = false
	moved_this_turn = false  # ← OPTION C

	for card in get_active_hand():
		card.locked = false

	tick_frozen_pieces()
	check_pending_coronations()

	_activate_stadium_if_ready(GLOBAL_STADIUMS)

	turn_started.emit(current_turn, turn_number)
	ui_message.emit("%s's turn begins (Turn %d)." % [current_turn.capitalize(), turn_number])
	print("
══════ TURN ", turn_number, " — ", current_turn.to_upper(), " ══════")

	var report := ""
	if active_stadium.has("name") and active_stadium.live:
		report += "🏟️ " + active_stadium.name + " (" + str(active_stadium.turns_remaining) + "t)  "
	if amaterasu_blessing.has("position"):
		report += "☀️ Blessing (" + str(amaterasu_blessing.turns_remaining) + "t)  "
	if frozen_pieces.size() > 0:
		report += "❄️ Frozen Pieces: " + str(frozen_pieces.size())
	if report != "":
		ui_message.emit("Active Effects: " + report)

	if skip_debuff[current_turn]:
		skip_debuff[current_turn] = false
		set_phase(GamePhase.AWAITING_SKIP_CHOICE)
		skip_choice_offered.emit(current_turn)
		print("⏭️ You are being SKIPPED. resolve_skip(true) = discard 2 to resist; (false) = accept.")
		return

	begin_check_evaluation()

func resolve_skip(resist: bool):
	if game_phase != GamePhase.AWAITING_SKIP_CHOICE:
		return
	var hand := get_active_hand()
	if resist and hand.size() >= 2:
		hand.sort_custom(func(a, b): return card_priority(a) < card_priority(b))
		for _i in range(2):
			discard_pile.append(hand.pop_front())
		print("💪 SKIP RESISTED! Discarded 2 cards. Play on.")
		begin_check_evaluation()
	else:
		print("⏭️ Turn skipped. You still draw.")
		finish_turn_and_switch()

func begin_check_evaluation():
	was_in_check_at_turn_start = grid_manager.is_in_check(current_turn)
	if was_in_check_at_turn_start:
		print("⚠️ ", current_turn.to_upper(), " is IN CHECK!")
		var escapes: Array = grid_manager.get_legal_check_escapes(current_turn)
		if escapes.size() == 0:
			declare_winner(opponent_of(current_turn), "CHECKMATE!")
			return
		if not any_escape_affordable(escapes):
			set_phase(GamePhase.AWAITING_EMERGENCY_CHOICE)
			emergency_protocol_offered.emit(current_turn)
			print("🚨 EMERGENCY PROTOCOL AVAILABLE: no affordable escape.")
			return
	set_phase(GamePhase.PLAY_CARDS)

func any_escape_affordable(escapes: Array) -> bool:
	if debug_infinite_energy:
		return true
	var budget := max_guaranteed_energy(get_active_hand())
	for esc in escapes:
		var dist := calculate_distance(esc.piece_type, esc.from_pos, esc.to_pos, esc.is_capture, current_turn)
		if dist > 0 and get_move_cost(esc.piece_type, dist, current_turn, esc.from_pos) <= budget:
			return true
	return false

func max_guaranteed_energy(hand: Array) -> int:
	var numbers: Array = []
	for card in hand:
		if card.type == CardType.NUMBER and not card.locked:
			numbers.append(card)
	if numbers.size() == 0:
		return 0
	numbers.sort_custom(func(a, b): return a.value > b.value)

	var best: int = numbers[0].value
	if numbers.size() >= 2:
		best = maxi(best, numbers[0].value + numbers[1].value)
	if numbers.size() >= 3:
		best = maxi(best, numbers[0].value + numbers[1].value + numbers[2].value)
	for color in COLORS:
		var same := numbers.filter(func(c): return c.color == color)
		if same.size() >= 3:
			best = maxi(best, same[0].value + same[1].value + same[2].value + 2)
	var best_diff := best_all_different_triple(numbers)
	if best_diff > 0:
		best = maxi(best, best_diff + 1)
	return best

func best_all_different_triple(sorted_numbers: Array) -> int:
	var best := 0
	var n := sorted_numbers.size()
	for i in range(n):
		for j in range(i + 1, n):
			if sorted_numbers[j].color == sorted_numbers[i].color:
				continue
			for k in range(j + 1, n):
				if sorted_numbers[k].color == sorted_numbers[i].color \
						or sorted_numbers[k].color == sorted_numbers[j].color:
					continue
				best = maxi(best, sorted_numbers[i].value + sorted_numbers[j].value + sorted_numbers[k].value)
	return best

func resolve_emergency_protocol(accept: bool):
	if game_phase != GamePhase.AWAITING_EMERGENCY_CHOICE:
		return
	if not accept:
		print("🎲 Protocol declined. Playing the turn normally (check must still be addressed).")
		set_phase(GamePhase.PLAY_CARDS)
		return
	var safe_squares: Array = grid_manager.get_king_safe_squares(current_turn)
	if safe_squares.size() == 0:
		declare_winner(opponent_of(current_turn), "CHECKMATE!")
		return
	emergency_move_king(safe_squares[0])

func emergency_move_king(to_pos: Vector2i):
	var hand := get_active_hand()
	print("🚨 EMERGENCY PROTOCOL! Discarding ENTIRE hand (", hand.size(), " cards).")
	for card in hand:
		discard_pile.append(card)
	hand.clear()
	refresh_hand_ui()

	var king_pos: Vector2i = grid_manager.get_king_pos(current_turn)

	var target: Dictionary = grid_manager.get_piece_at(to_pos)
	var was_capture: bool = not target.is_empty()
	if was_capture:
		print("⚔️ Emergency capture! ", opponent_of(current_turn), "'s ",
				piece_name(target.type), " falls. NO bounty.")
		grid_manager.destroy_piece(to_pos)
		on_piece_destroyed(to_pos)

	grid_manager.move_piece(king_pos, to_pos)
	update_tracked_position(king_pos, to_pos)
	record_last_move(PieceType.KING, king_pos, to_pos, was_capture,
			target.duplicate() if was_capture else {})
	piece_moved.emit(PieceType.KING, king_pos, to_pos)
	print("👑 King steps to ", to_pos, " — FREE. Special Phase forfeited.")

	check_trap_trigger(to_pos, PieceType.KING, current_turn)
	finish_turn_and_switch()

# ══════════════════════════════════════════════════════════
# HAND UI (PATCH 3)
# ══════════════════════════════════════════════════════════
func refresh_hand_ui():
	if hand_container == null:
		return

	# BOT-TURN GUARD: Don't show bot's hand
	if bot_players.get(current_turn, false):
		for child in hand_container.get_children():
			child.queue_free()
		var thinking_label = Label.new()
		thinking_label.text = "🤖 Kenji is thinking..."
		thinking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hand_container.add_child(thinking_label)
		return

	for child in hand_container.get_children():
		child.queue_free()
	var hand := get_active_hand()
	for i in range(hand.size()):
		var card_ui = CARD_UI_SCENE.instantiate()
		hand_container.add_child(card_ui)
		var disabled := false
		if hand[i].get("locked", false):
			disabled = true
		elif hand[i].name in ["Reverse", "Izanagi"] \
				and not can_play_reverse(hand[i].name == "Izanagi").ok:
			# OPTION C: greys out the moment you move, the moment the target
			# dies to a mine, when frozen, when greyed by anti-chain — all of it.
			disabled = true
		elif pending_trap_hand_index == i:
			disabled = false
		card_ui.setup(hand[i], i, disabled)
		card_ui.card_clicked.connect(_on_card_clicked)
	if game_hud:
		game_hud.update_trap_cancel(pending_trap_type != "")

func _on_card_clicked(index: int):
	# BOT-TURN GUARD: Ignore clicks during bot turns
	if bot_players.get(current_turn, false):
		return

	# TUTORIAL HOOK -- gate cards through director
	if tutorial_active:
		var td = get_node_or_null("TutorialDirector")
		if td:
			if td.has_method("notify_card_clicked"):
				td.notify_card_clicked(index)
			if td.has_method("is_card_allowed") and not td.is_card_allowed(index):
				return

	var hand := get_active_hand()
	if index < 0 or index >= hand.size():
		return
	if hand[index].type == CardType.NUMBER:
		if game_phase == GamePhase.PLAY_CARDS:
			stage_number_card(index)
	else:
		if game_phase == GamePhase.SPECIAL_CARD:
			play_special_card(index)
	refresh_hand_ui()

# ══════════════════════════════════════════════════════════
# PLAY PHASE — staging & energy
# ══════════════════════════════════════════════════════════
func stage_number_card(hand_index: int) -> bool:
	if game_phase != GamePhase.PLAY_CARDS:
		ui_message.emit("Cannot stage cards — not the Play Cards phase.")
		return false
	var hand := get_active_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card = hand[hand_index]
	if card.type != CardType.NUMBER:
		ui_message.emit("Only Number Cards generate energy.")
		return false
	if card.locked:
		ui_message.emit("Bounty card — locked until next turn.")
		return false
	if staged_cards.size() >= max_number_cards_per_turn:
		ui_message.emit("Max %d Number Cards per turn." % max_number_cards_per_turn)
		return false
	staged_cards.append(card)
	hand.remove_at(hand_index)
	ui_message.emit("Staged %s (%s) — %d card(s) staged." % [card.value, color_name(card.color), staged_cards.size()])
	return true

func unstage_card(staged_index: int) -> bool:
	if game_phase != GamePhase.PLAY_CARDS:
		return false
	if staged_index < 0 or staged_index >= staged_cards.size():
		return false
	get_active_hand().append(staged_cards.pop_at(staged_index))
	refresh_hand_ui()
	return true

func confirm_cards_and_move():
	if game_phase != GamePhase.PLAY_CARDS:
		return
	var base := 0
	for card in staged_cards:
		base += card.value
	var bonus := roll_color_bonus(staged_cards)
	current_energy = base + bonus
	if debug_infinite_energy:
		current_energy = 999

	match_stats[current_turn].cards_played += staged_cards.size()

	for card in staged_cards:
		discard_pile.append(card)
	staged_cards.clear()

	energy_confirmed.emit(current_energy, bonus)
	var bonus_text := " (+%d color bonus!)" % bonus if bonus > 0 else ""
	ui_message.emit("Energy confirmed: %d%s" % [current_energy, bonus_text])
	set_phase(GamePhase.MOVE_PIECE)

func roll_color_bonus(cards: Array) -> int:
	if cards.size() == 3:
		if cards[0].color == cards[1].color and cards[1].color == cards[2].color:
			return 2
		if cards[0].color != cards[1].color and cards[1].color != cards[2].color \
				and cards[0].color != cards[2].color:
			return 1
	elif cards.size() == 2 and cards[0].color == cards[1].color:
		# PUBLIC GAMBLE — stake (2 staged cards) and outcome (energy) both public
		var won := randf() <= 0.50
		gamble_flipped.emit("pair_bonus", won)
		return 1 if won else 0
	return 0

func skip_movement():
	if game_phase != GamePhase.PLAY_CARDS and game_phase != GamePhase.MOVE_PIECE:
		ui_message.emit("Cannot skip movement now.")
		return

	if was_in_check_at_turn_start and grid_manager.is_in_check(current_turn):
		# OPTION C EXCEPTION — "The King Save": you may forfeit movement
		# while in check ONLY if you hold a legal Reverse/Izanagi to answer it.
		if not _holds_legal_reverse():
			ui_message.emit("You are in check — address it (or use Emergency Protocol).")
			return
		ui_message.emit("⚠️ Skipping movement while in check — your Reverse had better work.")

	if game_phase == GamePhase.PLAY_CARDS:
		confirm_cards_and_move()

	ui_message.emit("Movement skipped — Special Card phase.")
	set_phase(GamePhase.SPECIAL_CARD)

func _holds_legal_reverse() -> bool:
	for card in get_active_hand():
		if card.name in ["Reverse", "Izanagi"] and not card.get("locked", false) \
				and can_play_reverse(card.name == "Izanagi").ok:
			return true
	return false

func return_to_movement() -> bool:
	# Escape hatch: you skipped movement, but still need (or want) to move.
	# Energy confirmed earlier is still available — end_turn hasn't zeroed it.
	if game_phase != GamePhase.SPECIAL_CARD or moved_this_turn:
		return false
	if pending_trap_type != "" or pending_amaterasu:
		return false

	set_phase(GamePhase.MOVE_PIECE)
	ui_message.emit("Returned to movement phase — %d energy available." % current_energy)
	return true

# ══════════════════════════════════════════════════════════
# MOVEMENT — costs, geometry, path blocking
# ══════════════════════════════════════════════════════════
func get_move_cost(piece_type: int, distance: int, mover: String, from_pos: Vector2i) -> int:
	var spec: Dictionary = ENERGY_COSTS[piece_type]
	var per_square: int = spec.per_square
	
	# Slider Highway Rule: squares 1-3 at full rate; 4+ at half rate; cap at 8
	# Only applies to sliding pieces (Bishop, Rook, Queen)
	var cost: int
	if piece_type in [PieceType.BISHOP, PieceType.ROOK, PieceType.QUEEN]:
		cost = per_square * mini(distance, 3) + ceili(per_square / 2.0) * maxi(0, distance - 3)
		cost = mini(cost, 8)
	else:
		cost = per_square if spec.flat else per_square * distance

	# Apply Amaterasu blessing (50% discount)
	if amaterasu_blessing.has("position") and amaterasu_blessing.position == from_pos \
			and amaterasu_blessing.owner == mover:
		cost = ceili(cost / 2.0)

	# Apply stadium discount
	if is_stadium_active(stadium_for_piece(piece_type)):
		if spec.flat:
			cost = maxi(cost - 1, 2 if piece_type == PieceType.KING else 1)
		else:
			cost = maxi(cost - distance, distance)

	# Apply king wounds tax
	if piece_type == PieceType.KING:
		cost += king_wounds[mover]
	return cost

func stadium_for_piece(piece_type: int) -> String:
	match piece_type:
		PieceType.KNIGHT: return "Knight's Pride"
		PieceType.ROOK: return "Rook's Fortress"
		PieceType.BISHOP: return "Bishop's Cathedral"
		PieceType.QUEEN: return "Queen's Domain"
		PieceType.KING: return "King's Sanctuary"
	return ""

func calculate_distance(piece_type: int, from_pos: Vector2i, to_pos: Vector2i,
		is_capture: bool, mover: String) -> int:
	var dx: int = absi(to_pos.x - from_pos.x)
	var dy: int = to_pos.y - from_pos.y
	var ady: int = absi(dy)
	var forward: int = 1 if mover == "white" else -1

	match piece_type:
		PieceType.PAWN:
			if is_capture:
				return 1 if (dx == 1 and dy == forward) else -1
			var max_sq: int = 3 if is_stadium_active("Pawn's Rebellion") else ENERGY_COSTS[PieceType.PAWN].max_squares
			if dx == 0 and dy * forward > 0 and ady <= max_sq:
				return ady
			return -1
		PieceType.KNIGHT:
			return 1 if ((dx == 1 and ady == 2) or (dx == 2 and ady == 1)) else -1
		PieceType.BISHOP:
			return dx if (dx == ady and dx > 0) else -1
		PieceType.ROOK:
			if dx > 0 and ady == 0: return dx
			if ady > 0 and dx == 0: return ady
			return -1
		PieceType.QUEEN:
			if dx == ady and dx > 0: return dx
			if dx > 0 and ady == 0: return dx
			if ady > 0 and dx == 0: return ady
			return -1
		PieceType.KING:
			return 1 if (maxi(dx, ady) == 1) else -1
	return -1

func execute_move(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	if game_phase != GamePhase.MOVE_PIECE:
		ui_message.emit("Not the movement phase.")
		return false
	var mover: Dictionary = grid_manager.get_piece_at(from_pos)
	if mover.is_empty():
		ui_message.emit("No piece at that square.")
		return false
	if mover.owner != current_turn:
		ui_message.emit("That's not your piece.")
		return false
	if frozen_pieces.has(from_pos):
		ui_message.emit("That piece is frozen (%d turns left)." % frozen_pieces[from_pos].turns_remaining)
		return false

	var piece_type: int = mover.type
	var target: Dictionary = grid_manager.get_piece_at(to_pos)
	var is_capture: bool = not target.is_empty()
	if is_capture:
		if target.owner == current_turn:
			ui_message.emit("Can't capture your own piece.")
			return false
		if frozen_pieces.has(to_pos):
			ui_message.emit("Frozen pieces cannot be captured.")
			return false

	var distance := calculate_distance(piece_type, from_pos, to_pos, is_capture, current_turn)
	if distance <= 0:
		ui_message.emit("Illegal move for %s." % piece_name(piece_type))
		return false

	if piece_type != PieceType.KNIGHT and distance > 1:
		if not grid_manager.is_path_clear(from_pos, to_pos):
			ui_message.emit("Path blocked — pieces cannot phase through others.")
			return false

	var cost := get_move_cost(piece_type, distance, current_turn, from_pos)
	if cost > current_energy:
		if piece_type == PieceType.KING and king_wounds[current_turn] > 0:
			ui_message.emit("Costs %d energy (%d base + %d wound tax); you have %d." %
					[cost, cost - king_wounds[current_turn], king_wounds[current_turn], current_energy])
		else:
			ui_message.emit("Costs %d energy; you have %d." % [cost, current_energy])
		return false

	if grid_manager.move_leaves_king_in_check(from_pos, to_pos, current_turn):
		ui_message.emit("Illegal — that leaves your King in check.")
		return false

	# ── EXECUTE ──
	current_energy -= cost
	moved_this_turn = true  # ← OPTION C: Reverse dies for this turn
	var captured_piece: Dictionary = target.duplicate() if is_capture else {}
	if is_capture:
		handle_capture(to_pos, captured_piece)
		if game_over_flag:
			return true
	grid_manager.move_piece(from_pos, to_pos)
	update_tracked_position(from_pos, to_pos)
	record_last_move(piece_type, from_pos, to_pos, is_capture, captured_piece)
	piece_moved.emit(piece_type, from_pos, to_pos)
	ui_message.emit("%s moved %s → %s (cost %d)." % [piece_name(piece_type), from_pos, to_pos, cost])

	handle_promotion_tracking(piece_type, from_pos, to_pos)
	check_trap_trigger(to_pos, piece_type, current_turn)

	# ONE move per turn — Rulebook §3. Movement phase ENDS here, capture or not.
	if current_energy > 0:
		ui_message.emit("Move complete — %d unspent energy lost." % current_energy)
	current_energy = 0
	set_phase(GamePhase.SPECIAL_CARD)
	return true

func record_last_move(piece_type: int, from_pos: Vector2i, to_pos: Vector2i,
		was_capture: bool, captured_piece: Dictionary,
		was_castle: bool = false, castle_data: Dictionary = {}):
	last_move = {
		"mover": current_turn, "piece_type": piece_type,
		"from_pos": from_pos, "to_pos": to_pos,
		"was_capture": was_capture, "captured_piece": captured_piece,
		"was_castle": was_castle, "castle_data": castle_data,
	}
	last_move_by_player[current_turn] = last_move.duplicate(true)

# ── CASTLING — atomic, 6 + wounds ──
func execute_castle(side: String) -> bool:
	if game_phase != GamePhase.MOVE_PIECE:
		ui_message.emit("Cannot castle — not the movement phase.")
		return false
	if not grid_manager.can_castle(current_turn, side):
		ui_message.emit("Castling %s is not legal right now." % side)
		return false
	var cost: int = castle_base_cost + king_wounds[current_turn]
	if cost > current_energy:
		ui_message.emit("Castling costs %d energy; you have %d." % [cost, current_energy])
		return false
	current_energy -= cost
	moved_this_turn = true  # ← OPTION C: castling is moving
	var data: Dictionary = grid_manager.execute_castle_on_board(current_turn, side)
	update_tracked_position(data.king_from, data.king_to)
	update_tracked_position(data.rook_from, data.rook_to)
	record_last_move(PieceType.KING, data.king_from, data.king_to, false, {}, true, data)
	ui_message.emit("Castled %s! (cost %d)" % [side, cost])
	check_trap_trigger(data.king_to, PieceType.KING, current_turn)
	check_trap_trigger(data.rook_to, PieceType.ROOK, current_turn)
	set_phase(GamePhase.SPECIAL_CARD)
	return true

# ── PROMOTION — Coronation March (Rule C) ──
# Survival measured in OPPONENT turns — closes the Susanoo instant-crown
# exploit: extra turns for YOU don't age your pawns.
func handle_promotion_tracking(piece_type: int, _from_pos: Vector2i, to_pos: Vector2i): 
	if piece_type != PieceType.PAWN:
		return
	if to_pos.y == PENULT_RANK[current_turn]:
		promotion_watch.append({"position": to_pos, "owner": current_turn,
				"arrived_opp": player_turn_count[opponent_of(current_turn)], "rank": "penult"})
		print("👀 Pawn on the penultimate rank — survive one opponent turn to earn promotion.")
	elif to_pos.y == FINAL_RANK[current_turn]:
		# ⚠️ LOAD-BEARING: update_tracked_position runs BEFORE this in
		# execute_move — watch entries already slid to to_pos. Match to_pos.
		for i in range(promotion_watch.size()):
			var w = promotion_watch[i]
			if w.owner == current_turn and w.position == to_pos \
					and w.get("rank", "penult") == "penult" \
					and player_turn_count[opponent_of(current_turn)] > w.arrived_opp:
				promotion_watch.remove_at(i)
				grid_manager.promote_piece(to_pos, PieceType.QUEEN)
				match_stats[current_turn].promotions += 1
				piece_promoted.emit(to_pos, current_turn)
				print("👸 PROMOTION! Pawn becomes a QUEEN at ", to_pos, "!")
				return
		for i in range(promotion_watch.size() - 1, -1, -1):
			if promotion_watch[i].position == to_pos and promotion_watch[i].owner == current_turn:
				promotion_watch.remove_at(i)
		promotion_watch.append({"position": to_pos, "owner": current_turn,
				"arrived_opp": player_turn_count[opponent_of(current_turn)], "rank": "final"})
		print("👑 CORONATION MARCH! Survive one opponent turn on the FINAL rank to be crowned.")

func check_pending_coronations():
	for i in range(promotion_watch.size() - 1, -1, -1):
		var w = promotion_watch[i]
		if w.owner == current_turn and w.get("rank", "penult") == "final" \
				and player_turn_count[opponent_of(current_turn)] > w.arrived_opp:
			var pos: Vector2i = w.position
			promotion_watch.remove_at(i)
			grid_manager.promote_piece(pos, PieceType.QUEEN)
			match_stats[current_turn].promotions += 1
			piece_promoted.emit(pos, current_turn)
			print("👸 CORONATION! QUEEN at ", pos, "!")
			ui_message.emit("👑 Coronation! Queen at %s" % str(pos))

func update_tracked_position(from_pos: Vector2i, to_pos: Vector2i):
	if amaterasu_blessing.has("position") and amaterasu_blessing.position == from_pos:
		amaterasu_blessing.position = to_pos
	for w in promotion_watch:
		if w.position == from_pos:
			w.position = to_pos
	if frozen_pieces.has(from_pos):
		frozen_pieces[to_pos] = frozen_pieces[from_pos]
		frozen_pieces.erase(from_pos)

# ══════════════════════════════════════════════════════════
# CAPTURE FLOW
# ══════════════════════════════════════════════════════════
func handle_capture(pos: Vector2i, captured_piece: Dictionary):
	print("⚔️ CAPTURED: ", opponent_of(current_turn), "'s ", piece_name(captured_piece.type), " at ", pos, "!")
	if captured_piece.type == PieceType.KING:
		declare_winner(current_turn, "King captured!")
		return
	grid_manager.destroy_piece(pos)
	on_piece_destroyed(pos)
	capture_occurred_this_turn = true
	moves_since_capture = 0
	position_history.clear()  # material left the board — old positions can never recur
	match_stats[current_turn].captures += 1
	var bounty: int = 3 if is_stadium_active("War Zone") else 1
	var got := draw_cards(get_active_hand(), bounty, true)
	capture_made.emit(pos, got)
	ui_message.emit("Capture! Drew %d bounty card(s) — locked until next turn." % got)

func on_piece_destroyed(pos: Vector2i):
	if amaterasu_blessing.has("position") and amaterasu_blessing.position == pos:
		print("☀️💔 The Amaterasu blessing dies with its piece.")
		amaterasu_blessing.clear()
	frozen_pieces.erase(pos)
	for i in range(promotion_watch.size() - 1, -1, -1):
		if promotion_watch[i].position == pos:
			promotion_watch.remove_at(i)

# ══════════════════════════════════════════════════════════
# TRAP SYSTEM
# ══════════════════════════════════════════════════════════
func place_trap(pos: Vector2i) -> bool:
	if pending_trap_type == "":
		return false
	if not grid_manager.is_square_empty(pos):
		ui_message.emit("Traps go on empty squares only.")
		return false
	for trap in traps:
		if trap.position == pos:
			ui_message.emit("One trap per square.")
			return false
	traps.append({"position": pos, "type": pending_trap_type, "owner": current_turn})
	ui_message.emit("%s placed at %s." % [pending_trap_type, pos])
	print("💣 A ", pending_trap_type, " has been placed... somewhere. 🤫")
	trap_placed.emit(pending_trap_type)

	match_stats[current_turn].traps_placed += 1

	var hand := get_active_hand()
	var card = hand[pending_trap_hand_index]
	hand.remove_at(pending_trap_hand_index)
	_spend_special(card)
	pending_trap_type = ""
	pending_trap_hand_index = -1
	refresh_hand_ui()
	board_ui.clear_trap_hover()
	_finish_special_if_resolved()
	return true

func cancel_trap_placement() -> void:
	if pending_trap_type == "":
		return
	ui_message.emit("Trap placement cancelled — %s returned to hand." % pending_trap_type)
	pending_trap_type = ""
	pending_trap_hand_index = -1
	refresh_hand_ui()
	board_ui.clear_trap_hover()

func check_trap_trigger(pos: Vector2i, piece_type: int, piece_owner: String):
	# RULING: traps trigger on ANYONE, owner included.
	# SECRECY: NO gamble_flipped here, EVER. trap_triggered fires only on detonation.
	for i in range(traps.size()):
		var trap = traps[i]
		if trap.position != pos:
			continue
		var chance: float
		match trap.type:
			"Landmine": chance = landmine_chance
			"Spring Trap": chance = spring_trap_chance
			"Ice Trap": chance = ice_trap_chance
			_: chance = 0.0
		if is_stadium_active("Wasteland"):
			chance += wasteland_bonus

		# TUTORIAL HOOK: force 100% detonation in tutorial
		if tutorial_active:
			chance = 1.0

		if randf() <= chance:
			traps.remove_at(i)
			resolve_trap_effect(trap.type, pos, piece_type, piece_owner)
		else:
			if trap.type == "Landmine":
				match_stats[piece_owner].traps_survived += 1
				print("…")  # silent. stays armed. opponent learns NOTHING.
			else:
				traps.remove_at(i)
				match_stats[piece_owner].traps_survived += 1
				print("💨 A trap fizzled harmlessly at ", pos, ".")
		return

func resolve_trap_effect(trap_type: String, pos: Vector2i, piece_type: int, piece_owner: String):
	match trap_type:
		"Landmine":
			if piece_type == PieceType.KING:
				if king_wounds[piece_owner] < king_wound_cap:
					king_wounds[piece_owner] += 1
					king_wounded.emit(piece_owner, king_wounds[piece_owner])
					print("💥🩸 LANDMINE! King WOUNDED (", king_wounds[piece_owner], "/", king_wound_cap, ")")
				else:
					print("💥 LANDMINE hits a maximally-wounded King — no further effect.")
			else:
				print("💥☠️ LANDMINE! The ", piece_name(piece_type), " at ", pos, " is DESTROYED!")
				grid_manager.destroy_piece(pos)
				on_piece_destroyed(pos)
			trap_triggered.emit("Landmine", pos, "detonated")
		"Spring Trap":
			var dest: Vector2i = grid_manager.fling_to_random_empty(pos, piece_type)
			if dest == pos:
				print("🌀💢 SPRING TRAP strains... and FAILS under the ", piece_name(piece_type), "'s weight!")
				trap_triggered.emit("Spring Trap", pos, "failed")
				return
			update_tracked_position(pos, dest)
			print("🌀 SPRING TRAP! ", piece_name(piece_type), " FLUNG ", pos, " → ", dest, "!")
			trap_triggered.emit("Spring Trap", pos, "sprung")
			check_trap_trigger(dest, piece_type, piece_owner)  # chains still LEGAL 🎆
		"Ice Trap":
			frozen_pieces[pos] = {"turns_remaining": ice_trap_duration, "owner": piece_owner}
			piece_frozen.emit(pos, ice_trap_duration)
			print("❄️ ICE TRAP! FROZEN for ", ice_trap_duration, " turns.")
			trap_triggered.emit("Ice Trap", pos, "frozen")

func tick_frozen_pieces():
	var thawed: Array = []
	for pos in frozen_pieces.keys():
		if frozen_pieces[pos].owner == current_turn:
			frozen_pieces[pos].turns_remaining -= 1
			if frozen_pieces[pos].turns_remaining <= 0:
				thawed.append(pos)
	for pos in thawed:
		frozen_pieces.erase(pos)
		piece_thawed.emit(pos)
		print("💧 A piece at ", pos, " has THAWED.")

# ══════════════════════════════════════════════════════════
# SPECIAL PHASE — legality gates + effects
# ══════════════════════════════════════════════════════════
func play_special_card(hand_index: int) -> bool:
	if game_phase != GamePhase.SPECIAL_CARD:
		ui_message.emit("Not the Special Card phase.")
		return false
	var hand := get_active_hand()
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card = hand[hand_index]
	if card.type == CardType.NUMBER:
		ui_message.emit("Number cards belong in the Play Cards phase.")
		return false

	if special_played_this_turn:
		ui_message.emit("One Special Card per turn.")
		return false
	if capture_occurred_this_turn and card.name in POST_CAPTURE_BLOCKED:
		ui_message.emit("%s is blocked on capture turns." % card.name)
		return false
	if card.name in DISRUPTION_CARDS and grid_manager.is_in_check(opponent_of(current_turn)):
		ui_message.emit("Cannot play %s while the enemy King is in check." % card.name)
		return false
	if card.locked:
		ui_message.emit("Bounty card — locked until next turn.")
		return false

	# ── OPTION C GATE: Reverse & Izanagi pay the Rewind Tax ──
	# Fizzle = card NOT consumed. We return false BEFORE removal, always.
	if card.name == "Reverse" or card.name == "Izanagi":
		var verdict: Dictionary = can_play_reverse(card.name == "Izanagi")
		if not verdict.ok:
			ui_message.emit(verdict.reason)
			return false

	if card.name in TRAP_CARDS:
		if pending_trap_type != "":
			ui_message.emit("Finish placing your current trap first (or Cancel).")
			return false
		pending_trap_type = card.name
		pending_trap_hand_index = hand_index
		ui_message.emit("Placing %s — click an empty square (or Cancel)." % card.name)
		refresh_hand_ui()
		return true

	var success := execute_special_effect(card)
	if not success:
		return false

	hand.remove_at(hand_index)
	_spend_special(card)
	refresh_hand_ui()
	_finish_special_if_resolved()
	return true

func _spend_special(card: Dictionary):
	match_stats[current_turn].cards_played += 1
	if card.type == CardType.LEGENDARY:
		exiled_cards.append(card)
		match_stats[current_turn].legendaries += 1
		legendary_played.emit(card.name, current_turn)
		print("🌟 ", card.name, " is EXILED from the game.")
	else:
		discard_pile.append(card)
	special_played_this_turn = true
	card_played.emit(card.name, current_turn)

func skip_special_phase():
	if game_phase != GamePhase.SPECIAL_CARD:
		ui_message.emit("Cannot skip special now.")
		return
	if pending_trap_type != "":
		ui_message.emit("Finish placing or cancel your trap before skipping special.")
		return
	if pending_amaterasu:
		ui_message.emit("Choose a piece to bless before skipping special.")
		return
	ui_message.emit("Special phase skipped.")
	end_turn()

func _finish_special_if_resolved() -> void:
	if pending_trap_type != "" or pending_amaterasu:
		return
	if game_phase == GamePhase.SPECIAL_CARD and special_played_this_turn:
		end_turn()

func execute_special_effect(card: Dictionary) -> bool:
	match card.name:
		"Landmine", "Spring Trap", "Ice Trap":
			return false

		"Trap Diffuser":
			if traps.size() == 0:
				ui_message.emit("Trap Diffuser: no traps on the board.")
			else:
				ui_message.emit("Trap Diffuser destroyed %d trap(s)!" % traps.size())
				traps.clear()
			return true

		"Discard 4":
			var opp := get_opponent_hand()
			var n: int = mini(4, opp.size())
			for _i in range(n):
				discard_pile.append(opp.pop_at(randi_range(0, opp.size() - 1)))
			print("💥 DISCARD 4! Opponent loses ", n, " random card(s).")
			return true
		"Equalize":
			var opp := get_opponent_hand()
			var mine := get_active_hand()
			if opp.size() <= mine.size():
				print("⚖️ Equalize fizzles — card is spent.")
				return true
			var to_discard: int = opp.size() - mine.size()
			opp.sort_custom(func(a, b): return card_priority(a) < card_priority(b))
			for _i in range(to_discard):
				discard_pile.append(opp.pop_front())
			print("⚖️ EQUALIZE! Opponent discards ", to_discard, ".")
			return true
		"Sabotage":
			var opp := get_opponent_hand()
			var special_indices: Array = []
			for i in range(opp.size()):
				if opp[i].type != CardType.NUMBER:
					special_indices.append(i)
			if special_indices.size() == 0:
				print("🕵️ Sabotage fizzles — card is spent.")
				return true
			var victim_i: int = special_indices[randi_range(0, special_indices.size() - 1)]
			exiled_cards.append(opp.pop_at(victim_i))
			print("🕵️ SABOTAGE executed. (They'll find out eventually...)")
			return true
		"Skip":
			skip_debuff[opponent_of(current_turn)] = true
			print("⏭️ SKIP! Opponent must skip next turn OR discard 2 to resist.")
			return true

		"+2 Draw":
			return _draw_effect(2, 1)
		"+4 Draw":
			return _draw_effect(4, 2)

		"Reverse":
			return execute_reverse(false)
		"Refresh":
			var hand := get_active_hand()
			if discard_pile.size() < hand.size():
				print("🔄 Refresh failed — discard pile too small.")
				return false
			var old := hand.duplicate()
			hand.clear()
			discard_pile.shuffle()
			for _i in range(old.size()):
				hand.append(discard_pile.pop_back())
			for c in old:
				discard_pile.append(c)
			print("🔄 REFRESH! Whole hand swapped.")
			return true
		"Scavenge":
			if discard_pile.size() == 0:
				print("🔍 Scavenge fizzles — card is spent.")
				return true
			discard_pile.shuffle()
			var got: int = mini(2, discard_pile.size())
			for _i in range(got):
				get_active_hand().append(discard_pile.pop_back())
			print("🔍 SCAVENGE! +", got, ".")
			return true
		"Trade":
			var hand := get_active_hand()
			if hand.size() < 3 or discard_pile.size() < 2:
				print("🤝 Trade failed — need 2 other cards in hand AND 2 in discard.")
				return false
			var give := hand.filter(func(c): return c != card)
			give.sort_custom(func(a, b): return card_priority(a) < card_priority(b))
			for i in range(2):
				hand.erase(give[i])
				discard_pile.append(give[i])
			discard_pile.shuffle()
			for _i in range(2):
				hand.append(discard_pile.pop_back())
			print("🤝 TRADE! Gave 2, received 2.")
			return true

		"Time Steal":
			var opp := opponent_of(current_turn)
			var victim_time := black_time if opp == "black" else white_time
			var actual := minf(time_steal_amount, maxf(victim_time - time_steal_floor, 0.0))
			if actual <= 0.0:
				print("⏱️ Time Steal fizzles — victim already at the floor. Card is spent.")
				return true
			chess_clock.steal_time(opp, current_turn, actual)
			time_stolen.emit(opp, actual)
			print("⏱️ TIME STEAL! ", actual, "s ripped from ", opp, "'s clock!")
			return true

		"Knight's Pride", "Rook's Fortress", "Bishop's Cathedral", "Queen's Domain", \
		"King's Sanctuary", "Pawn's Rebellion", "Wasteland", "War Zone", "Arsenal":
			active_stadium = {"name": card.name, "caster": current_turn,
					"turns_remaining": stadium_duration, "live": false}
			if card.name in GLOBAL_STADIUMS:
				print("🌍 GLOBAL STADIUM: ", card.name, " — live at YOUR next turn.")
			else:
				print("♟️ TARGETED STADIUM: ", card.name, " — live at end of this turn.")
			return true

		"Izanagi":
			return execute_izanagi()
		"Amaterasu":
			pending_amaterasu = true
			print("☀️ AMATERASU! bless_piece(pos). end_turn() LOCKED until chosen.")
			return true
		"Susanoo":
			if susanoo_played[current_turn]:
				print("⚔️ Susanoo cannot chain — once per game.")
				return false
			susanoo_extra_turn = true
			susanoo_played[current_turn] = true
			print("⚔️ SUSANOO! FULL EXTRA TURN after this one!")
			return true
		"Raijin":
			return execute_raijin()
		"Kaguya":
			return execute_kaguya()

	print("❌ Unknown card: ", card.name)
	return false

func _draw_effect(mine: int, backlash_amt: int) -> bool:
	draw_cards(get_active_hand(), mine)
	print("📥 +%d DRAW!" % mine)
	# PUBLIC GAMBLE — the whole table watches the karma coin
	var backlash := randf() <= 0.50
	gamble_flipped.emit("draw_backlash", backlash)
	if backlash:
		draw_cards(get_opponent_hand(), backlash_amt)
		print("   ↪️ Backlash: opponent draws %d." % backlash_amt)
	return true

# ══════════════════════════════════════════════════════════
# REVERSE & LEGENDARIES — Option C "The Rewind Tax"
# Rule: Reverse undoes the OPPONENT'S last piece movement.
# COST: your movement phase. If you moved this turn → illegal.
# Fizzle = card NOT consumed (returns false → play_special_card keeps it).
# Ledger: last_move_by_player is the source of truth, NOT global last_move.
# ══════════════════════════════════════════════════════════

# Side-effect-free validator. Called by the UI (grey-out + tooltip reason),
# by play_special_card (gate), and by execute_reverse (double validation).
func can_play_reverse(is_izanagi: bool = false) -> Dictionary:
	# --- THE TAX (Option C core rule) ---
	if moved_this_turn:
		return {"ok": false, "reason": "Reverse costs your movement phase — you already moved. Skip movement to use it."}

	# --- Anti-chain greyout (Izanagi exempt — a legendary outranks a common's cooldown) ---
	if reverse_greyout[current_turn] and not is_izanagi:
		return {"ok": false, "reason": "Cannot Reverse a Reverse — anti-chain rule."}

	# --- Anything on the opponent's ledger? ---
	var m: Dictionary = last_move_by_player[opponent_of(current_turn)]
	if m.is_empty():
		return {"ok": false, "reason": "Your opponent has no move to undo."}

	if m.was_castle:
		var d: Dictionary = m.castle_data
		var king_now: Dictionary = grid_manager.get_piece_at(d.king_to)
		var rook_now: Dictionary = grid_manager.get_piece_at(d.rook_to)
		if king_now.is_empty() or king_now.owner != m.mover or king_now.type != PieceType.KING:
			return {"ok": false, "reason": "The castle cannot be undone — the King is no longer there."}
		if rook_now.is_empty() or rook_now.owner != m.mover or rook_now.type != PieceType.ROOK:
			return {"ok": false, "reason": "The castle cannot be undone — the Rook is no longer there."}
		if not grid_manager.is_square_empty(d.king_from) or not grid_manager.is_square_empty(d.rook_from):
			return {"ok": false, "reason": "The castle cannot be undone — a home square is occupied."}
		if frozen_pieces.has(d.king_to) or frozen_pieces.has(d.rook_to):
			return {"ok": false, "reason": "A frozen piece cannot be moved — not even backwards."}
	else:
		# --- TIMELINE GUARD 1: piece still where it landed? ---
		# (A Landmine may have killed it; a Spring Trap may have flung it.)
		var piece_now: Dictionary = grid_manager.get_piece_at(m.to_pos)
		if piece_now.is_empty() or piece_now.owner != m.mover or piece_now.type != m.piece_type:
			return {"ok": false, "reason": "That piece is no longer there — the timeline was disrupted."}
		# --- TIMELINE GUARD 2: origin clear? Near-impossible under Option C
		# (you haven't moved), but a Spring fling earns one line of insurance.
		if not grid_manager.is_square_empty(m.from_pos):
			return {"ok": false, "reason": "The square it came from is now occupied."}
		# --- FROZEN GUARD — default ruling: frozen = immovable by ANY effect.
		# ⚠️ If you rule "the freeze travels with it," delete this block.
		if frozen_pieces.has(m.to_pos):
			return {"ok": false, "reason": "That piece is frozen solid — nothing can move it."}

	return {"ok": true, "reason": ""}

func execute_reverse(is_izanagi: bool) -> bool:
	# Double validation — cheap insurance against board changes between gate and execution
	var verdict: Dictionary = can_play_reverse(is_izanagi)
	if not verdict.ok:
		ui_message.emit(verdict.reason)
		return false  # fizzle — card NOT consumed

	var opp := opponent_of(current_turn)
	var m: Dictionary = last_move_by_player[opp]

	if m.was_castle:
		var d: Dictionary = m.castle_data
		grid_manager.move_piece(d.king_to, d.king_from)
		grid_manager.move_piece(d.rook_to, d.rook_from)
		update_tracked_position(d.king_to, d.king_from)
		update_tracked_position(d.rook_to, d.rook_from)
		ui_message.emit("↩️ REVERSE! The castle is undone.")
		# The timeline shows no mercy on the way back — traps re-check
		check_trap_trigger(d.king_from, PieceType.KING, m.mover)
		check_trap_trigger(d.rook_from, PieceType.ROOK, m.mover)
	else:
		grid_manager.move_piece(m.to_pos, m.from_pos)
		update_tracked_position(m.to_pos, m.from_pos)
		ui_message.emit("↩️ REVERSE! %s returns %s → %s." % [piece_name(m.piece_type), m.to_pos, m.from_pos])
		if m.was_capture and not is_izanagi:
			ui_message.emit("Captured piece stays dead — only the movement was undone.")
		# Return trip is a REAL move — mines re-roll. 💥 The signature play lives here.
		check_trap_trigger(m.from_pos, m.piece_type, m.mover)

	# Consume ONLY the opponent's ledger entry; keep global in sync
	last_move_by_player[opp] = {}
	if last_move.get("mover", "") == opp:
		last_move = {}

	reverse_greyout[opp] = true
	return true

func execute_izanagi() -> bool:
	var m: Dictionary = last_move_by_player[opponent_of(current_turn)]
	# Snapshot the revive BEFORE the reverse consumes the ledger
	var revive: Dictionary = {}
	var revive_pos: Vector2i = Vector2i.ZERO
	if not m.is_empty() and m.was_capture:
		revive = m.captured_piece.duplicate()
		revive_pos = m.to_pos
	if not execute_reverse(true):
		print("🌊 Izanagi finds nothing to undo. Card stays in hand.")
		return false  # fizzle — NOT exiled, stays in hand
	if not revive.is_empty():
		grid_manager.revive_piece(revive.type, revive_pos, current_turn)
		print("🌊✨ IZANAGI! Your ", piece_name(revive.type), " RETURNS TO LIFE at ", revive_pos, "!")
	return true

func bless_piece(pos: Vector2i) -> bool:
	if not pending_amaterasu:
		return false
	if not grid_manager.is_owned_by(pos, current_turn):
		print("❌ You can only bless YOUR OWN pieces.")
		return false
	amaterasu_blessing = {"position": pos, "turns_remaining": amaterasu_duration,
			"owner": current_turn}
	pending_amaterasu = false
	blessing_applied.emit(pos)
	print("☀️ GOLDEN GLOW! Piece at ", pos, " blessed.")
	return true

func execute_raijin() -> bool:
	var opp := opponent_of(current_turn)
	var targets: Array = []
	for piece in grid_manager.get_player_pieces(opp):
		if piece.type != PieceType.KING and piece.type != PieceType.QUEEN:
			targets.append(piece)
	if targets.size() == 0:
		print("⚡ Raijin fizzles — DEAD CARD (stays in hand).")
		return false
	var struck = targets[randi_range(0, targets.size() - 1)]
	print("⚡⚡⚡ RAIJIN STRIKES the ", piece_name(struck.type), " at ", struck.position, "!")
	grid_manager.destroy_piece(struck.position)
	on_piece_destroyed(struck.position)
	return true

func execute_kaguya() -> bool:
	if reshuffle_occurred:
		print("🌸 Kaguya is dead — DEAD CARD (stays in hand).")
		return false
	if shared_deck.size() == 0:
		print("🌸 Kaguya fizzles — DEAD CARD (stays in hand).")
		return false
	var peek_count: int = mini(10, shared_deck.size())
	var peeked: Array = []
	for _i in range(peek_count):
		peeked.append(shared_deck.pop_back())
	print("🌸 KAGUYA! Top ", peek_count, " card(s) revealed to you.")
	peeked.sort_custom(func(a, b): return card_priority(a) > card_priority(b))
	for _i in range(mini(3, peeked.size())):
		get_active_hand().append(peeked.pop_front())
	_kaguya_stack_remaining(peeked)
	print("🌸 The deck is RIGGED.")
	return true

func _kaguya_stack_remaining(cards: Array):
	var n := cards.size()
	if n == 0:
		return
	var seq: Array = []
	if n >= 7:
		seq = [cards[0], cards[1], cards[5], cards[6], cards[2], cards[3], cards[4]]
	elif n >= 4:
		seq = [cards[0], cards[1]]
		for i in range(2, n):
			seq.append(cards[i])
	else:
		seq = cards.duplicate()
	for i in range(seq.size() - 1, -1, -1):
		shared_deck.append(seq[i])

# ══════════════════════════════════════════════════════════
# STADIUM HELPERS
# ══════════════════════════════════════════════════════════
func is_stadium_active(stadium_name: String) -> bool:
	if stadium_name == "" or not active_stadium.has("name"):
		return false
	return active_stadium.name == stadium_name and active_stadium.live

func _activate_stadium_if_ready(pool: Array):
	if active_stadium.has("name") and not active_stadium.live \
			and active_stadium.name in pool and active_stadium.caster == current_turn:
		active_stadium.live = true
		print("🏟️ STADIUM LIVE: ", active_stadium.name)
		stadium_changed.emit(active_stadium.name, active_stadium.turns_remaining)

func get_draw_amount() -> int:
	return 3 if is_stadium_active("Arsenal") else end_of_turn_draw

# ══════════════════════════════════════════════════════════
# DRAW CONDITIONS
# ══════════════════════════════════════════════════════════
func check_draw_conditions():
	# TUTORIAL HOOK -- scripted passes repeat positions; no draws in class
	if tutorial_active:
		return
	moves_since_capture += 1
	if moves_since_capture >= draw_moves_threshold:
		declare_draw("%d capture-less turns — forced draw." % draw_moves_threshold)
		return
	if grid_manager.has_method("get_position_hash"):
		var h: String = grid_manager.get_position_hash()
		position_history[h] = position_history.get(h, 0) + 1
		if position_history[h] >= 3:
			declare_draw("Threefold repetition.")

func offer_draw():
	if draw_offered_by != "":
		return
	draw_offered_by = current_turn
	ui_message.emit("%s offers a draw." % current_turn.capitalize())

func respond_to_draw(accept: bool):
	if draw_offered_by == "":
		return
	if accept:
		declare_draw("Mutual agreement.")
	else:
		draw_offered_by = ""
		ui_message.emit("Draw declined. Fight on!")

func resign():
	declare_winner(opponent_of(current_turn), "%s resigned." % current_turn.capitalize())

# ══════════════════════════════════════════════════════════
# END TURN
# ══════════════════════════════════════════════════════════
func end_turn():
	if game_over_flag:
		return
	if pending_trap_type != "":
		print("🔒 Place your trap first! place_trap(pos)")
		return
	if pending_amaterasu:
		print("🔒 Choose a piece to bless first! bless_piece(pos)")
		return
	if was_in_check_at_turn_start and grid_manager.is_in_check(current_turn):
		# TUTORIAL HOOK: let Kenji end turn even when still in check during tutorial
		if not (tutorial_active and current_turn == "black"):
			print("❌ You are STILL in check — address it or use the Emergency Protocol.")
			return

	if current_energy > 0:
		ui_message.emit("⚠️ %d unspent energy will be LOST." % current_energy)

	set_phase(GamePhase.END_TURN)
	current_energy = 0

	_activate_stadium_if_ready(TARGETED_STADIUMS)

	finish_turn_and_switch()

func finish_turn_and_switch():
	# Cleared HERE — the only exit all turns share, preventing the anti-chain leak.
	# (Before the Susanoo branch = lenient ruling: a Susanoo extra turn un-greys you.)
	reverse_greyout[current_turn] = false

	check_draw_conditions()
	if game_over_flag:
		return

	var drew := draw_cards(get_active_hand(), get_draw_amount())
	print("🃏 Draw Phase: +", drew, " card(s).")

	if amaterasu_blessing.has("owner") and amaterasu_blessing.owner == current_turn:
		amaterasu_blessing.turns_remaining -= 1
		if amaterasu_blessing.turns_remaining <= 0:
			print("☀️🌅 The Amaterasu blessing fades.")
			amaterasu_blessing.clear()

	if active_stadium.has("name") and active_stadium.live:
		active_stadium.turns_remaining -= 1
		if active_stadium.turns_remaining <= 0:
			print("🏟️ ", active_stadium.name, " crumbles.")
			active_stadium.clear()
		else:
			stadium_changed.emit(active_stadium.name, active_stadium.turns_remaining)

	if susanoo_extra_turn:
		susanoo_extra_turn = false
		print("⚔️🌩️ SUSANOO TURN — ", current_turn.to_upper(), " GOES AGAIN!")
		start_new_turn()
		return

	current_turn = opponent_of(current_turn)
	start_new_turn()

# ══════════════════════════════════════════════════════════
# GAME END — one funeral home, two doors
# ══════════════════════════════════════════════════════════
func declare_winner(winner: String, reason: String):
	_end_game(winner, reason)

func declare_draw(reason: String):
	_end_game("draw", reason)

func _end_game(result: String, reason: String):
	if game_over_flag:
		return
	game_over_flag = true
	set_phase(GamePhase.PRE_MATCH)  # signal-emitting — HUD hears it, buttons die
	chess_clock.stop()
	if result == "draw":
		print("🤝 DRAW — ", reason)
	else:
		print("
🏆🏆🏆 ", result.to_upper(), " WINS — ", reason, " 🏆🏆🏆")
	game_over.emit(result, reason, {
		"stats": match_stats,
		"turns": turn_number,
		"white_time_left": white_time,
		"black_time_left": black_time,
		"next_up": "",
	})

# ══════════════════════════════════════════════════════════
# UTILITIES
# ══════════════════════════════════════════════════════════
func set_phase(phase: int):
	game_phase = phase
	phase_changed.emit(phase)

func get_active_hand() -> Array:
	return white_hand if current_turn == "white" else black_hand

func get_opponent_hand() -> Array:
	return black_hand if current_turn == "white" else white_hand

func opponent_of(player: String) -> String:
	return "black" if player == "white" else "white"

func apply_ladder_result(points: int, won: bool) -> int:
	return points + LADDER_WIN if won else maxi(points - LADDER_LOSS, 0)

func card_priority(card: Dictionary) -> int:
	match card.type:
		CardType.LEGENDARY: return 100
		CardType.STADIUM: return 60
		CardType.COUNTER: return 55
		CardType.DISRUPTION: return 50
		CardType.UTILITY: return 45
		CardType.DRAW: return 40
		CardType.TRAP: return 35
		CardType.COMPETITIVE: return 30
		CardType.NUMBER: return card.value * 5
	return 0

func piece_name(t: int) -> String:
	return PIECE_NAMES[t] if t >= 0 and t < PIECE_NAMES.size() else "???"

func color_name(c: int) -> String:
	return COLOR_NAMES[c] if c >= 0 and c < COLOR_NAMES.size() else "None" 
