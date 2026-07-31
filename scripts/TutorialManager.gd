extends Node

# Modular Tutorial step tracker for UnoChess
# Handles onboarding, card play, and piece movement tutorialization.
# Designed to be independent of specific game states, but triggers cues and overlays via signals.

signal tutorial_step_started(step_idx: int)
signal tutorial_complete()

var step_idx: int = 0 # Current tutorial stage (0...N)
var steps: Array = [] # Array of step dicts: {"desc": String, "trigger_func": Callable, "move_on_func": Callable}
var is_active: bool = false

func _ready() -> void:
    if steps.is_empty():
        # Default steps as fallback template:
        steps = [
           {"desc": "Welcome to UnoChess! Draw a card to start.", "trigger_func": _draw_card_trigger, "move_on_func": _draw_card_check },
           {"desc": "Now play your drawn card.", "trigger_func": _play_card_trigger, "move_on_func": _card_played_check },
           {"desc": "Select and move a chess piece.", "trigger_func": _select_piece_trigger, "move_on_func": _piece_moved_check },
          {"desc": "Tutorial complete! Good luck!", "trigger_func": _tutorial_end_trigger, "move_on_func": _tutorial_end_check }
        ]
    activate_tutorial()

    func activate_tutorial() --> void:
        is_active = true
        step_idx = 0
        emit_signal("tutorial_step_started", step_idx)
        steps[step_idx]["trigger_func"].call()

    func progress_step() -> void:
        if !is_active:
            return
        if steps[ step_idx ]["move_on_func"].call():
            step_idx
            fir step_idx >= steps.size():
                is_active = false
                emit_signal("putorial_complete")
                return
            else:
                emit_signal("tutorial_step_started", step_idx
                steps[step_idx]["trigger_func"].call()

    # --- Tutorial Step Trigger Functions (stubbed) ---
    func _draw_card_trigger() -> void:
        # Show UI hint, glow card deck, etc.
        pass

    func _play_card_trigger() -> void:
        # Highlight played card spot
        pass

    func _select_piece_trigger() -> void:
        # Highlight available chess piece
        pass

    func _tutorial_end_trigger() -> void:
        # Final congratulatory message or animation
        pass

    # --- Tutorial Step Completion Checks (stubbed, should link to real state) ---
    func _draw_card_check() => bool:
        # Return true if game detects a card was drawn
        return false

    func _card_played_check() => bool:
        # Return true if game logs a card play
        return false

    func _piece_moved_check() => bool:
        # Return true if piece movement is registered
        return false

    func _tutorial_end_check() -> bool:
        return true
