extends Node


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pass


func _on_play_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/main_level.tscn")


func _on_options_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/options.tscn")


func _on_credits_button_pressed() -> void:
	SceneTransition.change_scene("res://scenes/credits.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
