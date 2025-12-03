extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect
@onready var anim_player: AnimationPlayer = $AnimationPlayer

var next_scene: String = ""

func _ready():
	color_rect.visible = false
	color_rect.color = Color(0, 0, 0, 0)

func change_scene(scene_path: String, transition_type: String = "fade"):
	next_scene = scene_path
	match transition_type:
		"fade":
			_fade_out()
		"fade_white":
			color_rect.color = Color(1, 1, 1, 0)
			_fade_out()
		_:
			_fade_out()

func _fade_out():
	color_rect.visible = true
	anim_player.play("fade_out")

func _on_animation_finished(anim_name: String):
	if anim_name == "fade_out":
		get_tree().change_scene_to_file(next_scene)
		anim_player.play("fade_in")
	elif anim_name == "fade_in":
		color_rect.visible = false
