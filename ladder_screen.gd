extends Control

const GAME_SCENE := "res://main_game.tscn"
const OPPONENTS := [
	{"profile": "kenji", "title": "🥋 Kenji — Random Violence", "unlock_hint": ""},
	{"profile": "yuki", "title": "🌸 Yuki — Patient & Sneaky", "unlock_hint": "Defeat Kenji to unlock"},
	{"profile": "takeshi", "title": "⚔️ Takeshi — The Final Exam", "unlock_hint": "Defeat Yuki to unlock"},
]

@onready var list: VBoxContainer = $CenterContainer/VBoxContainer/OpponentList

func _ready() -> void:
	for opp in OPPONENTS:
		var btn := Button.new()
		var unlocked: bool = Progression.is_unlocked(opp["profile"])
		btn.text = opp["title"] if unlocked else opp["title"] + "  🔒 " + opp["unlock_hint"]
		btn.disabled = not unlocked
		if Progression.defeated.get(opp["profile"], false):
			btn.text += "  ✅"
		btn.pressed.connect(_on_opponent_pressed.bind(opp["profile"]))
		list.add_child(btn)

func _on_opponent_pressed(profile: String) -> void:
	Progression.next_mode = "vs_bot"
	Progression.next_bot_profile = profile
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")
