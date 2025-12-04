extends Control

func _ready():
	SoundManager.start_menu_music()

func _on_back_button_pressed() -> void:
	SoundManager.play_ui_back()
	SceneTransition.change_scene("res://scenes/main_menu.tscn")
