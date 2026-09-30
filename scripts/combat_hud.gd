extends Control

@export var health_bar_path: NodePath = ^"HealthBar"
@export var health_label_path: NodePath = ^"HealthLabel"
@export var ammo_label_path: NodePath = ^"AmmoLabel"

@export_group("Default Style")
@export var health_fill_color: Color = Color("#d94b3d")
@export var health_background_color: Color = Color("#20242ddd")
@export var hud_text_color: Color = Color("#fff4dc")
@export_range(12, 48, 1) var hud_font_size: int = 24

@onready var health_bar: ProgressBar = get_node_or_null(health_bar_path) as ProgressBar
@onready var health_label: Label = get_node_or_null(health_label_path) as Label
@onready var ammo_label: Label = get_node_or_null(ammo_label_path) as Label

var _player: Node
var _weapon_controller: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_default_style()
	call_deferred("_bind_local_player")


func _apply_default_style() -> void:
	if health_bar != null:
		health_bar.visible = true
		health_bar.show_percentage = false
		health_bar.custom_minimum_size = Vector2(320.0, 28.0)
		var background := StyleBoxFlat.new()
		background.bg_color = health_background_color
		background.set_corner_radius_all(5)
		health_bar.add_theme_stylebox_override("background", background)
		var fill := StyleBoxFlat.new()
		fill.bg_color = health_fill_color
		fill.set_corner_radius_all(5)
		health_bar.add_theme_stylebox_override("fill", fill)

	for label in [health_label, ammo_label]:
		if label == null:
			continue
		label.visible = true
		label.add_theme_color_override("font_color", hud_text_color)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_font_size_override("font_size", hud_font_size)
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		label.custom_minimum_size.y = 32.0

	if health_label != null:
		health_label.custom_minimum_size.x = 140.0
	if ammo_label != null:
		ammo_label.custom_minimum_size = Vector2(140.0, 44.0)
		ammo_label.add_theme_font_size_override("font_size", hud_font_size + 8)


func _bind_local_player() -> void:
	_player = get_tree().get_first_node_in_group("local_player")
	if _player == null:
		push_warning("Combat HUD could not find a node in the 'local_player' group.")
		return

	if _player.has_signal("health_changed"):
		_player.connect("health_changed", Callable(self, "_on_health_changed"))
		_on_health_changed(
			float(_player.get("current_health")),
			float(_player.get("maximum_health"))
		)
	else:
		push_warning("The node in 'local_player' has no health_changed signal.")

	_weapon_controller = _player.get_node_or_null("WeaponController")
	if _weapon_controller == null:
		push_warning("Combat HUD could not find Player/WeaponController.")
		return

	if _weapon_controller.has_signal("ammo_changed"):
		_weapon_controller.connect("ammo_changed", Callable(self, "_on_ammo_changed"))
		var definition := _weapon_controller.get("definition") as WeaponDefinition
		if definition != null:
			_on_ammo_changed(
				int(_weapon_controller.get("current_ammo")),
				definition.magazine_capacity
			)
	if _weapon_controller.has_signal("reload_started"):
		_weapon_controller.connect("reload_started", Callable(self, "_on_reload_started"))

	if health_bar == null:
		push_warning("Combat HUD is missing a ProgressBar at '%s'." % health_bar_path)
	if health_label == null:
		push_warning("Combat HUD is missing a Label at '%s'." % health_label_path)
	if ammo_label == null:
		push_warning("Combat HUD is missing a Label at '%s'." % ammo_label_path)


func _on_health_changed(current_health: float, maximum_health: float) -> void:
	if health_bar != null:
		health_bar.max_value = maximum_health
		health_bar.value = current_health
	if health_label != null:
		health_label.text = "%d / %d" % [roundi(current_health), roundi(maximum_health)]


func _on_ammo_changed(current_ammo: int, magazine_capacity: int) -> void:
	if ammo_label != null:
		ammo_label.text = "%d / %d" % [current_ammo, magazine_capacity]


func _on_reload_started() -> void:
	if ammo_label != null:
		ammo_label.text = "RELOAD"
