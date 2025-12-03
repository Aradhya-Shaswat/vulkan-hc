extends Control

func _ready():
	pass

func _on_back_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/main_menu.tscn")
