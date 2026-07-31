extends Panel
# ═══ UNOCHESS — game_over_screen.gd · v1 "The Autopsy Table" ═══

const STAT_LABELS := {
	"captures": "⚔️ Captures",
	"cards_played": "🎴 Cards Played",
	"legendaries": "🌟 Legendaries",
	"traps_placed": "💣 Traps Placed",
	"traps_survived": "😅 Traps Survived",
	"promotions": "👸 Promotions",
}

@onready var main = get_node("/root/MainGame") # ⚠️ adjust if your root node name differs!
@onready var result_label: Label = $CenterBox/ResultVBox/ResultLabel
@onready var reason_label: Label = $CenterBox/ResultVBox/ReasonLabel
@onready var stats_grid: GridContainer = $CenterBox/ResultVBox/StatsGrid
@onready var rematch_btn: Button = $CenterBox/ResultVBox/ButtonRow/RematchButton
@onready var quit_btn: Button = $CenterBox/ResultVBox/ButtonRow/QuitButton
@onready var menu_btn: Button = $CenterBox/ResultVBox/ButtonRow/MenuButton

func _ready():
	main.game_over.connect(_on_game_over)
	rematch_btn.pressed.connect(_on_rematch)
	quit_btn.pressed.connect(func(): get_tree().quit())
	menu_btn.pressed.connect(_on_menu)

func _on_game_over(winner: String, reason: String, data: Dictionary):
	# TUTORIAL HOOK -- director handles tutorial game over
	if main.tutorial_active:
		return
	result_label.text = "🤝 DRAW" if winner == "draw" else "🏆 %s WINS" % winner.to_upper()
	reason_label.text = reason
	var next_up: String = data.get("next_up", "")
	if next_up != "":
		set_next_up_message(next_up)
	_fill_stats(data)
	visible = true

func set_next_up_message(text: String) -> void:
	if text.is_empty():
		return
	var base_text := reason_label.text
	if base_text.contains("\nNEXT UP:"):
		base_text = base_text.split("\nNEXT UP:", false)[0]
	reason_label.text = "%s\nNEXT UP: %s" % [base_text, text]

func _fill_stats(data: Dictionary):
	for child in stats_grid.get_children():
		child.queue_free()
	_add_cell("") # header row
	_add_cell("♔ White")
	_add_cell("♚ Black")
	for key in STAT_LABELS:
		_add_cell(STAT_LABELS[key])
		_add_cell(str(data.stats.white[key]))
		_add_cell(str(data.stats.black[key]))
	_add_cell("⏱️ Time Left")
	_add_cell("%d:%02d" % [int(data.white_time_left) / 60, int(data.white_time_left) % 60])
	_add_cell("%d:%02d" % [int(data.black_time_left) / 60, int(data.black_time_left) % 60])

func _add_cell(text: String):
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_grid.add_child(l)

func _on_rematch():
	visible = false
	main.rematch() # 👻 the Exorcism finally gets a doorbell

func _on_menu():
	get_tree().change_scene_to_file("res://main_menu.tscn")
