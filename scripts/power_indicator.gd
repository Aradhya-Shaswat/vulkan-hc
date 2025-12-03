extends Control

@export var radius: float = 30.0
@export var thickness: float = 4.0
@export var bg_color: Color = Color(0.2, 0.2, 0.2, 0.5)
@export var fill_color: Color = Color(1.0, 0.5, 0.0, 1.0)
@export var full_color: Color = Color(1.0, 0.2, 0.0, 1.0)

var current_power: float = 0.0

func _ready():
	visible = false
	current_power = 0.0

func set_power(power: float):
	current_power = clamp(power, 0.0, 1.0)
	queue_redraw()

func _draw():
	var center = size / 2.0
	var start_angle = -PI / 2.0
	var end_angle = start_angle + (current_power * TAU)
	
	draw_arc(center, radius, 0, TAU, 64, bg_color, thickness, true)
	
	if current_power > 0.0:
		var color = fill_color.lerp(full_color, current_power)
		draw_arc(center, radius, start_angle, end_angle, 64, color, thickness, true)
