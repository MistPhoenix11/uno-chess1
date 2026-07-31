extends Control

const GAME_SCENE := "res://main_game.tscn"
const LADDER_SCENE := "res://ladder_screen.tscn"

# TUTORIAL HOOK -- retargeted to standalone rules slideshow
func _on_tutorial_pressed() -> void:
    get_tree().change_scene_to_file("res://slideshow.tscn")

func _on_ladder_pressed() -> void:
    get_tree().change_scene_to_file(LADDER_SCENE)

func _on_hotseat_pressed() -> void:
    Progression.next_mode = "hotseat"
    Progression.next_bot_profile = ""
    get_tree().change_scene_to_file(GAME_SCENE)

func _on_quit_pressed() -> void:
    get_tree().quit()
