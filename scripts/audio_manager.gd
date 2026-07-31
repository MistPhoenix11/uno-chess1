# audio_manager.gd - handles SFx and BGM for UnoChess
extends Node

var bgm_stream: AudioStream = null
var card_sfx: AudioStream = null
var piece_move_sfx: AudioStream = null
var bgm_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer

func _ready() -> void:
    # Create and add audio players if not already in scene
    bgm_player = AudioStreamPlayer.new()
    bgm_player.bus = "Music"
    add_child(bgm_player)

    sfx_player = AudioStreamPlayer.new()
    sfx_player.bus = "SFX"
    add_child(sfx_player)

func play_bgm() -> void:
    if bgm_stream:
        bgm_player.stream = bgm_stream
        bgm_player.play()

func stop_bgm() -> void:
    bgm_player.stop()

func play_card_sfx() -> void:
    if card_sfx:
        sfx_player.stream = card_sfx
        sfx_player.play()

func play_piece_move_sfx() -> void:
    if piece_move_sfx:
        sfx_player.stream = piece_move_sfx
        sfx_player.play()

 # Extend or link Inspector with scene audio resources in asssign)
