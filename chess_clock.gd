class_name ChessClock
extends Node

## UnoChess Chess Clock — v1.1 FINAL
## Default 7.5 min per player, +2s increment per completed turn,
## low-time warning at 30s, instant loss at 0:00. No Time Steal floor.

signal time_updated(white_time: float, black_time: float)
signal low_time_entered(player: String)
signal time_expired(player: String)
signal active_player_changed(player: String)

const STARTING_TIME := 450.0      # fallback; engine passes its export in
const TURN_INCREMENT := 5.0       # added AFTER you complete your turn
const LOW_TIME_THRESHOLD := 30.0  # red pulse territory

var time_left := {"white": STARTING_TIME, "black": STARTING_TIME}
var active_player := "white"
var running := false              # master switch (match live?)
var paused := false               # temporary freeze (forced modals)

var _low_warned := {"white": false, "black": false}
var _expired := false

func _process(delta: float) -> void:
	if not running or paused or _expired:
		return
	time_left[active_player] -= delta
	if time_left[active_player] <= 0.0:
		time_left[active_player] = 0.0
		_expired = true
		running = false
		time_expired.emit(active_player)
	elif time_left[active_player] <= LOW_TIME_THRESHOLD and not _low_warned[active_player]:
		_low_warned[active_player] = true
		low_time_entered.emit(active_player)
	time_updated.emit(time_left["white"], time_left["black"])

func start_match(time_per_player: float = STARTING_TIME, first_player: String = "white") -> void:
	# Added assertion to strictly enforce valid player strings
	assert(first_player == "white" or first_player == "black", "Invalid first_player string provided.")
	
	time_left = {"white": time_per_player, "black": time_per_player}
	active_player = first_player
	_low_warned = {"white": false, "black": false}
	_expired = false
	running = true
	paused = false
	active_player_changed.emit(active_player)
	time_updated.emit(time_left["white"], time_left["black"])

func end_turn(switch_player: bool = true) -> void:
	## Call ONCE when a turn fully completes. Increments the mover.
	## switch_player=false → Susanoo: increment earned, clock stays on you.
	if _expired:
		return
	time_left[active_player] += TURN_INCREMENT
	if time_left[active_player] > LOW_TIME_THRESHOLD:
		_low_warned[active_player] = false  # increment lifted you out — re-arm warning
	if switch_player:
		active_player = "black" if active_player == "white" else "white"
		active_player_changed.emit(active_player)
	time_updated.emit(time_left["white"], time_left["black"])

func switch_to(player: String) -> void:
	## Hard-sync the clock to a player. IDEMPOTENT — safe to call
	## every turn start, even when end_turn() already switched.
	if _expired:
		return
	if active_player == player:
		return   # already synced — no-op
	active_player = player
	active_player_changed.emit(active_player)
	time_updated.emit(time_left["white"], time_left["black"])

func set_paused(value: bool) -> void:
	paused = value

func stop() -> void:
	## Game over — freeze everything.
	running = false

func steal_time(victim: String, thief: String, amount: float) -> float:
	## Time Steal card. Returns amount actually stolen.
	## NO floor — hitting 0.0 via theft is an instant execution.
	var stolen: float = minf(amount, time_left[victim])
	time_left[victim] -= stolen
	time_left[thief] += stolen
	if time_left[victim] <= 0.0:
		time_left[victim] = 0.0
		_expired = true
		running = false
		time_expired.emit(victim)
	time_updated.emit(time_left["white"], time_left["black"])
	return stolen

func get_time_left(player: String) -> float:
	return time_left[player]

static func format_time(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [int(s / 60.0), s % 60]