extends VBoxContainer
class_name OptionsMenuController

signal back_requested

const RESOLUTION_PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

@onready var resolution_option: OptionButton = $ResolutionRow/ResolutionOption
@onready var window_option: OptionButton = $WindowModeRow/WindowOption
@onready var sensitivity_slider: HSlider = $SensitivityRow/SensitivitySlider
@onready var sensitivity_value: LineEdit = $SensitivityRow/SensitivityValue
@onready var back_button: Button = $BackButton

var _resolutions: Array[Vector2i] = []


func _ready() -> void:
	_setup_resolution_options()
	resolution_option.tooltip_text = "A resolução pode ser alterada no modo janela; tela cheia usa a resolução do monitor."
	window_option.add_item("Windowed")
	window_option.set_item_metadata(0, false)
	window_option.add_item("Fullscreen")
	window_option.set_item_metadata(1, true)
	resolution_option.item_selected.connect(_on_resolution_selected)
	window_option.item_selected.connect(_on_window_mode_selected)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	back_button.pressed.connect(_on_back_pressed)
	sensitivity_value.editable = false
	sensitivity_value.focus_mode = Control.FOCUS_NONE
	_refresh_from_settings()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused and event.is_action_pressed("ui_cancel"):
		if event is InputEventKey and event.echo:
			return
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _setup_resolution_options() -> void:
	_resolutions = RESOLUTION_PRESETS.duplicate()
	var current_resolution: Vector2i = GameSettings.windowed_resolution
	if not _resolutions.has(current_resolution):
		_resolutions.append(current_resolution)
	for resolution in _resolutions:
		resolution_option.add_item("%d x %d" % [resolution.x, resolution.y])


func _refresh_from_settings() -> void:
	for index in range(_resolutions.size()):
		if _resolutions[index] == GameSettings.windowed_resolution:
			resolution_option.select(index)
			break
	window_option.select(1 if GameSettings.fullscreen else 0)
	resolution_option.disabled = GameSettings.fullscreen
	sensitivity_slider.value = GameSettings.mouse_sensitivity_multiplier
	_update_sensitivity_text(GameSettings.mouse_sensitivity_multiplier)


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < _resolutions.size():
		GameSettings.set_resolution(_resolutions[index])


func _on_window_mode_selected(index: int) -> void:
	GameSettings.set_fullscreen(bool(window_option.get_item_metadata(index)))
	resolution_option.disabled = GameSettings.fullscreen


func _on_sensitivity_changed(value: float) -> void:
	GameSettings.set_mouse_sensitivity_multiplier(value)
	_update_sensitivity_text(value)


func _update_sensitivity_text(value: float) -> void:
	sensitivity_value.text = "%.2f" % value


func _on_back_pressed() -> void:
	back_requested.emit()
