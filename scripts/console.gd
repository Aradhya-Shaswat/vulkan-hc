extends CanvasLayer

var is_open: bool = false
var command_history: Array[String] = []
var history_index: int = -1

@onready var console_panel: Panel = $ConsolePanel
@onready var output_label: RichTextLabel = $ConsolePanel/VBoxContainer/OutputScroll/Output
@onready var input_field: LineEdit = $ConsolePanel/VBoxContainer/InputContainer/InputField

const COMMANDS = {
	"help": "  Show all available commands",
	"clear": "  Clear console output",
	"sensitivity": "  Set mouse sensitivity (0.001 - 0.02)",
	"sens": "  Alias for sensitivity",
	"sfx_volume": "  Set SFX volume (0 - 100)",
	"music_volume": "  Set music volume (0 - 100)",
	"crosshair_color": "  Set crosshair color (red/green/white/cyan/yellow/pink)",
	"fov": "  Set field of view (60 - 120)",
	"noclip": "  Toggle noclip/fly mode",
	"respawn": "  Respawn at spawn point",
	"tp": "  Teleport to coordinates (x y z)",
	"tpp": "  Teleport to player by nickname",
	"speed": "  Set player walk speed",
	"version": "  Show game version",
	"quit": "  Quit the game",
}

var noclip_mode: bool = false
var custom_fov: float = 75.0
var custom_speed: float = 8.5
var _original_collision_state: bool = false

func _ready():
	console_panel.hide()
	input_field.text_submitted.connect(_on_command_submitted)
	_print_line("  [color=cyan]VULKAN Console[/color] - Type 'help' for commands")

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_QUOTELEFT or event.keycode == KEY_ASCIITILDE:
			_toggle_console()
			get_viewport().set_input_as_handled()
		elif is_open:
			if event.keycode == KEY_UP:
				_navigate_history(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				_navigate_history(1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ESCAPE:
				_toggle_console()
				get_viewport().set_input_as_handled()

func _toggle_console():
	is_open = not is_open
	console_panel.visible = is_open
	if is_open:
		input_field.grab_focus()
		input_field.clear()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_restore_mouse_state()

func _restore_mouse_state():
	if not _is_in_game():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	
	if GameSettings.is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	
	var player = _get_local_player()
	if player:
		if player.get("is_dead") == true:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			return
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _is_in_game() -> bool:
	var scene_name = get_tree().current_scene.name.to_lower() if get_tree().current_scene else ""
	return scene_name == "main" or scene_name == "main_level"

func _navigate_history(direction: int):
	if command_history.is_empty():
		return
	history_index += direction
	history_index = clamp(history_index, 0, command_history.size() - 1)
	input_field.text = command_history[history_index]
	input_field.caret_column = input_field.text.length()

func _on_command_submitted(text: String):
	var cmd = text.strip_edges()
	if cmd.is_empty():
		return
	
	command_history.push_front(cmd)
	if command_history.size() > 50:
		command_history.pop_back()
	history_index = -1
	
	_print_line("] " + cmd)
	_execute_command(cmd)
	input_field.clear()

func _print_line(text: String):
	output_label.append_text(text + "\n")

func _execute_command(cmd: String):
	var parts = cmd.split(" ", false)
	if parts.is_empty():
		return
	
	var command = parts[0].to_lower()
	var args = parts.slice(1)
	
	match command:
		"help":
			_cmd_help()
		"clear":
			output_label.clear()
		"sensitivity", "sens":
			_cmd_sensitivity(args)
		"sfx_volume":
			_cmd_sfx_volume(args)
		"music_volume":
			_cmd_music_volume(args)
		"crosshair_color":
			_cmd_crosshair_color(args)
		"fov":
			_cmd_fov(args)
		"noclip":
			_cmd_noclip()
		"respawn":
			_cmd_respawn()
		"tp":
			_cmd_teleport(args)
		"tpp":
			_cmd_teleport_to_player(args)
		"speed":
			_cmd_speed(args)
		"version":
			_print_line("  [color=gray]VULKAN-HC BETA 1.0[/color]")
		"quit", "exit":
			get_tree().quit()
		_:
			_print_line("  [color=red]Unknown command: " + command + "[/color]")

func _cmd_help():
	_print_line("  [color=yellow]Available commands:[/color]")
	for cmd_name in COMMANDS:
		_print_line("  [color=lime]" + cmd_name + "[/color] - " + COMMANDS[cmd_name])

func _cmd_sensitivity(args: Array):
	if args.is_empty():
		_print_line("  sensitivity = " + str(GameSettings.sensitivity))
		return
	var value = float(args[0])
	value = clamp(value, 0.001, 0.02)
	GameSettings.set_sensitivity(value)
	GameSettings.save_settings()
	_print_line("  [color=lime]Sensitivity set to " + str(value) + "[/color]")

func _cmd_sfx_volume(args: Array):
	if args.is_empty():
		_print_line("  sfx_volume = " + str(int(GameSettings.sfx_volume * 100)))
		return
	var value = float(args[0]) / 100.0
	value = clamp(value, 0.0, 1.0)
	GameSettings.set_sfx_volume(value)
	GameSettings.save_settings()
	_print_line("  [color=lime]SFX volume set to " + str(int(value * 100)) + "%[/color]")

func _cmd_music_volume(args: Array):
	if args.is_empty():
		_print_line("  music_volume = " + str(int(GameSettings.music_volume * 100)))
		return
	var value = float(args[0]) / 100.0
	value = clamp(value, 0.0, 1.0)
	GameSettings.set_music_volume(value)
	GameSettings.save_settings()
	_print_line("  [color=lime]Music volume set to " + str(int(value * 100)) + "%[/color]")

func _cmd_crosshair_color(args: Array):
	if args.is_empty():
		_print_line("  Usage: crosshair_color <red/green/white/cyan/yellow/pink>")
		return
	var color_name = args[0].to_lower()
	var color: Color
	match color_name:
		"red":
			color = Color(1, 0.2, 0.2, 1)
		"green":
			color = Color(0.2, 0.92, 0, 1)
		"white":
			color = Color(1, 1, 1, 1)
		"cyan":
			color = Color(0, 1, 1, 1)
		"yellow":
			color = Color(1, 1, 0, 1)
		"pink":
			color = Color(1, 0.4, 0.7, 1)
		_:
			_print_line("  [color=red]Unknown color. Use: red, green, white, cyan, yellow, pink[/color]")
			return
	GameSettings.set_crosshair_color(color)
	GameSettings.save_settings()
	_print_line("  [color=lime]Crosshair color set to " + color_name + "[/color]")

func _cmd_fov(args: Array):
	if args.is_empty():
		_print_line("  fov = " + str(custom_fov))
		return
	var value = float(args[0])
	value = clamp(value, 60.0, 120.0)
	custom_fov = value
	var player = _get_local_player()
	if player and player.has_node("Head/Camera3D"):
		player.get_node("Head/Camera3D").fov = value
	_print_line("  [color=lime]FOV set to " + str(value) + "[/color]")

func _cmd_noclip():
	var player = _get_local_player()
	if not player:
		_print_line("  [color=red]Cannot toggle noclip - not in game[/color]")
		return
	
	if player.get("is_dead") == true:
		_print_line("  [color=red]Cannot toggle noclip while dead[/color]")
		return
	
	if player.get("in_cart") == true:
		_print_line("  [color=red]Cannot toggle noclip while in cart - exit first[/color]")
		return
	
	noclip_mode = not noclip_mode
	
	if player.has_node("CollisionShape3D"):
		player.get_node("CollisionShape3D").disabled = noclip_mode
	
	if player.has_method("set_noclip"):
		player.set_noclip(noclip_mode)
	elif "noclip_enabled" in player:
		player.noclip_enabled = noclip_mode
	
	var status = "enabled (use jump/crouch to fly)" if noclip_mode else "disabled"
	_print_line("  [color=lime]Noclip " + status + "[/color]")

func disable_noclip():
	if noclip_mode:
		noclip_mode = false
		var player = _get_local_player()
		if player:
			if player.has_node("CollisionShape3D"):
				player.get_node("CollisionShape3D").disabled = false
			if "noclip_enabled" in player:
				player.noclip_enabled = false

func _cmd_respawn():
	var player = _get_local_player()
	if not player:
		_print_line("  [color=red]Cannot respawn - not in game[/color]")
		return
	if player.get("is_dead") == true:
		_print_line("  [color=yellow]Already respawning...[/color]")
		return
	if player.has_method("respawn"):
		player.respawn()
		_print_line("  [color=lime]Respawned[/color]")
	else:
		_print_line("  [color=red]Cannot respawn - respawn method not found[/color]")

func _cmd_teleport(args: Array):
	if args.size() < 3:
		_print_line("  Usage: tp <x> <y> <z>")
		return
	var x = float(args[0])
	var y = float(args[1])
	var z = float(args[2])
	var player = _get_local_player()
	if player:
		if player.get("is_dead") == true:
			_print_line("  [color=red]Cannot teleport while dead[/color]")
			return
		if player.get("in_cart") == true:
			_print_line("  [color=red]Cannot teleport while in cart - exit first[/color]")
			return
		player.global_position = Vector3(x, y, z)
		player.velocity = Vector3.ZERO
		_print_line("  [color=lime]Teleported to " + str(x) + ", " + str(y) + ", " + str(z) + "[/color]")
	else:
		_print_line("  [color=red]Cannot teleport - not in game[/color]")

func _cmd_teleport_to_player(args: Array):
	if args.is_empty():
		_print_line("  Usage: tpp <nickname>")
		return
	
	var local_player = _get_local_player()
	if not local_player:
		_print_line("  [color=red]Cannot teleport - local player not found[/color]")
		return
	
	if local_player.get("is_dead") == true:
		_print_line("  [color=red]Cannot teleport while dead[/color]")
		return
	if local_player.get("in_cart") == true:
		_print_line("  [color=red]Cannot teleport while in cart - exit first[/color]")
		return
	
	var target_name = " ".join(args).to_lower()
	var main = get_tree().current_scene
	if not main or not main.has_method("get") or main.get("player_list") == null:
		_print_line("  [color=red]Cannot teleport - not in game[/color]")
		return
	
	var player_list = main.player_list
	var target_id = -1
	for id in player_list:
		if player_list[id].to_lower() == target_name:
			target_id = id
			break
	
	if target_id == -1:
		for id in player_list:
			if player_list[id].to_lower().begins_with(target_name):
				target_id = id
				break
	
	if target_id == -1:
		_print_line("  [color=red]Player '" + target_name + "' not found[/color]")
		_print_line("  [color=gray]Online players: " + ", ".join(player_list.values()) + "[/color]")
		return
	
	var target_player = main.get_node_or_null(str(target_id))
	
	if not target_player:
		_print_line("  [color=red]Target player node not found[/color]")
		return
	
	local_player.global_position = target_player.global_position + Vector3(1, 0, 1)
	local_player.velocity = Vector3.ZERO
	_print_line("  [color=lime]Teleported to " + player_list[target_id] + "[/color]")

func _cmd_speed(args: Array):
	if args.is_empty():
		_print_line("  speed = " + str(custom_speed))
		return
	var value = float(args[0])
	value = clamp(value, 8.5, 500.0)
	custom_speed = value
	var player = _get_local_player()
	if player:
		player.WALK_SPEED = value
		player.SPRINT_SPEED = value * 1.18
	_print_line("  [color=lime]Speed set to " + str(value) + "[/color]")

func _get_local_player() -> Node:
	var main = get_tree().current_scene
	if main and main.multiplayer and main.multiplayer.multiplayer_peer:
		var my_id = main.multiplayer.get_unique_id()
		return main.get_node_or_null(str(my_id))
	return null
