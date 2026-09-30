class_name WeaponDefinition
extends Resource

enum FireMode {
	SEMI_AUTO,
	AUTOMATIC,
}

@export_group("Identity")
@export var display_name: String = "Prototype Rifle"
@export var fire_mode: FireMode = FireMode.AUTOMATIC

@export_group("Ballistics")
@export_range(0.1, 200.0, 0.1) var damage: float = 25.0
@export_range(1.0, 1200.0, 1.0) var rounds_per_minute: float = 360.0
@export_range(1.0, 1000.0, 1.0) var max_range: float = 100.0
@export_range(1, 500, 1) var magazine_capacity: int = 30
@export_range(0.1, 20.0, 0.1) var reload_duration: float = 1.8
@export_range(0.0, 15.0, 0.1) var spread_degrees: float = 0.0

@export_group("Presentation")
@export var weapon_scene: PackedScene
@export var impact_effect_scene: PackedScene
@export var aim_animation: StringName = &""
@export var fire_animation: StringName = &""
@export var reload_animation: StringName = &""
