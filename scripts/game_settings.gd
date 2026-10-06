extends Node

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_RESOLUTION := Vector2i(1280, 720)

var windowed_resolution: Vector2i = DEFAULT_RESOLUTION
var fullscreen: bool = false
var mouse_sensitivity_multiplier: float = 1.0
var last_network_message: String = ""
var pending_session_mode: StringName = &""
var pending_server_address: String = ""


func _ready() -> void:
	_load_settings()


func set_resolution(resolution: Vector2i) -> void:
	windowed_resolution = resolution
	if not fullscreen:
		DisplayServer.window_set_size(windowed_resolution)
	_save_settings()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(windowed_resolution)
	_save_settings()


func set_mouse_sensitivity_multiplier(value: float) -> void:
	mouse_sensitivity_multiplier = clampf(value, 0.01, 1.0)
	_save_settings()


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		var initial_size := DisplayServer.window_get_size()
		if initial_size.x > 0 and initial_size.y > 0:
			windowed_resolution = initial_size
		return

	var stored_resolution: Variant = config.get_value("display", "windowed_resolution", DEFAULT_RESOLUTION)
	if stored_resolution is Vector2i:
		windowed_resolution = stored_resolution
	fullscreen = bool(config.get_value("display", "fullscreen", false))
	mouse_sensitivity_multiplier = clampf(
		float(config.get_value("input", "mouse_sensitivity_multiplier", 1.0)),
		0.01,
		1.0
	)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(windowed_resolution)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "windowed_resolution", windowed_resolution)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("input", "mouse_sensitivity_multiplier", mouse_sensitivity_multiplier)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save user settings. Error: %s" % error)
