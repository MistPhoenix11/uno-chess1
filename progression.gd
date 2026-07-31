extends Node

const SAVE_PATH := "user://progress.cfg"

# Launch params — set by menu BEFORE changing scene, read by main_game._ready()
var next_mode: String = "hotseat"        # "hotseat" | "vs_bot" | "tutorial"
var next_bot_profile: String = ""        # "kenji" | "yuki" | "takeshi"

var tutorial_complete: bool = false
var defeated := {"kenji": false, "yuki": false, "takeshi": false}

func _ready() -> void:
    load_progress()

func load_progress() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_PATH) != OK:
        return  # first run — defaults stand
    tutorial_complete = cfg.get_value("progress", "tutorial_complete", false)
    for key in defeated.keys():
        defeated[key] = cfg.get_value("defeated", key, false)

func save_progress() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("progress", "tutorial_complete", tutorial_complete)
    for key in defeated.keys():
        cfg.set_value("defeated", key, defeated[key])
    cfg.save(SAVE_PATH)

func mark_defeated(profile: String) -> void:
    if defeated.has(profile):
        defeated[profile] = true
        save_progress()

func is_unlocked(profile: String) -> bool:
    match profile:
        "kenji":
            return true
        "yuki":
            return defeated["kenji"]
        "takeshi":
            return defeated["yuki"]
    return false
