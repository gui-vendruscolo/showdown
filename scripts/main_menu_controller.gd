extends Control

const ARENA_SCENE_PATH := "res://scenes/arena.tscn"

@onready var main_panel: Control = $CenterContainer/Panels/MainPanel
@onready var join_menu: Control = $CenterContainer/Panels/JoinMenu
@onready var options_menu: OptionsMenuController = $CenterContainer/Panels/OptionsMenu
@onready var join_ip_input: LineEdit = $CenterContainer/Panels/JoinMenu/IpAddressInput
@onready var join_status: Label = $CenterContainer/Panels/JoinMenu/JoinStatus

var _launching := false


func _ready() -> void:
	$CenterContainer/Panels/MainPanel/CreateGameButton.pressed.connect(_on_create_game_pressed)
	$CenterContainer/Panels/MainPanel/JoinGameButton.pressed.connect(_show_join_menu)
	$CenterContainer/Panels/MainPanel/OptionsButton.pressed.connect(_show_options_menu)
	$CenterContainer/Panels/MainPanel/QuitButton.pressed.connect(get_tree().quit)
	$CenterContainer/Panels/JoinMenu/ConnectButton.pressed.connect(_on_connect_pressed)
	$CenterContainer/Panels/JoinMenu/BackButton.pressed.connect(_show_main_menu)
	options_menu.back_requested.connect(_show_main_menu)
	main_panel.visible = true
	join_menu.visible = false
	options_menu.visible = false
	if not GameSettings.last_network_message.is_empty():
		join_status.text = GameSettings.last_network_message
		join_menu.visible = true
		main_panel.visible = false
		GameSettings.last_network_message = ""


func _unhandled_input(event: InputEvent) -> void:
	if _launching or not event.is_action_pressed("ui_cancel"):
		return
	if event is InputEventKey and event.echo:
		return
	if join_menu.visible or options_menu.visible:
		_show_main_menu()
		get_viewport().set_input_as_handled()


func _show_join_menu() -> void:
	join_status.text = ""
	main_panel.visible = false
	options_menu.visible = false
	join_menu.visible = true
	join_ip_input.grab_focus()


func _show_options_menu() -> void:
	main_panel.visible = false
	join_menu.visible = false
	options_menu.visible = true


func _show_main_menu() -> void:
	main_panel.visible = true
	join_menu.visible = false
	options_menu.visible = false


func _on_create_game_pressed() -> void:
	_launch_match(true, "")


func _on_connect_pressed() -> void:
	var address := join_ip_input.text.strip_edges()
	if address.is_empty():
		join_status.text = "Digite o IP local do host."
		return
	join_status.text = "Conectando a %s..." % address
	_launch_match(false, address)


func _launch_match(host: bool, address: String) -> void:
	if _launching:
		return
	_launching = true
	GameSettings.last_network_message = ""
	GameSettings.pending_session_mode = &"host" if host else &"client"
	GameSettings.pending_server_address = address
	var scene_tree := get_tree()
	var error := scene_tree.change_scene_to_file(ARENA_SCENE_PATH)
	if error != OK:
		_launching = false
		GameSettings.pending_session_mode = &""
		GameSettings.pending_server_address = ""
		join_menu.visible = true
		main_panel.visible = false
		join_status.text = "Não foi possível abrir a arena."
