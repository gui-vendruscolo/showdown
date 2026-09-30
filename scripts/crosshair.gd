extends Control

@export_group("Shape")
@export_range(0.0, 40.0, 0.5) var center_gap: float = 5.0
@export_range(1.0, 40.0, 0.5) var line_length: float = 8.0
@export_range(1.0, 10.0, 0.5) var line_thickness: float = 2.0
@export_range(0.0, 8.0, 0.5) var center_dot_radius: float = 1.5

@export_group("Style")
@export var reticle_color: Color = Color.WHITE
@export var outline_enabled: bool = true
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.85)
@export_range(0.0, 4.0, 0.5) var outline_thickness: float = 1.0

@export_group("Feedback")
@export_range(0.0, 40.0, 0.5) var movement_gap: float = 2.0
@export_range(0.0, 40.0, 0.5) var aim_gap_scale: float = 0.65
@export_range(1.0, 40.0, 1.0) var bloom_recovery_speed: float = 12.0

var _shot_bloom: float = 0.0
var _current_movement_gap: float = 0.0
var _is_aiming: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("hud_crosshair")
	queue_redraw()


func _process(delta: float) -> void:
	if _shot_bloom <= 0.0:
		return
	_shot_bloom = move_toward(_shot_bloom, 0.0, bloom_recovery_speed * delta)
	queue_redraw()


func set_movement_gap(value: float) -> void:
	_current_movement_gap = maxf(value, 0.0)
	queue_redraw()


func set_aiming(is_aiming: bool) -> void:
	_is_aiming = is_aiming
	queue_redraw()


func add_shot_bloom(amount: float = 3.0) -> void:
	_shot_bloom = minf(_shot_bloom + maxf(amount, 0.0), 40.0)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var gap := center_gap + _current_movement_gap + _shot_bloom
	if _is_aiming:
		gap *= aim_gap_scale

	_draw_arm(center + Vector2(0.0, -gap - line_length), center + Vector2(0.0, -gap))
	_draw_arm(center + Vector2(gap, 0.0), center + Vector2(gap + line_length, 0.0))
	_draw_arm(center + Vector2(0.0, gap), center + Vector2(0.0, gap + line_length))
	_draw_arm(center + Vector2(-gap - line_length, 0.0), center + Vector2(-gap, 0.0))

	if center_dot_radius > 0.0:
		if outline_enabled:
			draw_circle(center, center_dot_radius + outline_thickness, outline_color)
		draw_circle(center, center_dot_radius, reticle_color)


func _draw_arm(from: Vector2, to: Vector2) -> void:
	if outline_enabled:
		draw_line(from, to, outline_color, line_thickness + outline_thickness * 2.0, true)
	draw_line(from, to, reticle_color, line_thickness, true)
