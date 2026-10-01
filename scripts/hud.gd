extends CanvasLayer
class_name GameHUD
## Interfaz construida enteramente por codigo (sin escena .tscn propia): puntuacion,
## municion, barra de estabilidad del paciente, indicador de oleada, barra de
## seleccion de los 5 antibioticos, radar de objetivos, mira (cadera/optica) y
## pantalla de resultados.

var _score_label: Label
var _ammo_label: Label
var _reload_label: Label
var _wave_label: Label
var _health_bar: ProgressBar
var _crosshair: Label
var _results_panel: Control
var _radar: RadarDisplay
var _weapon_slots: Dictionary = {} # weapon_id -> Panel


func _ready() -> void:
	layer = 1
	_build_hud()
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.patient_health_changed.connect(_on_health_changed)
	_on_score_changed(GameManager.score)
	_on_health_changed(GameManager.patient_health)


func _build_hud() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 32)
	rows.add_child(top_row)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(_score_label)

	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(_ammo_label)

	_wave_label = Label.new()
	_wave_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(_wave_label)

	var health_box := VBoxContainer.new()
	var health_title := Label.new()
	health_title.text = "Estabilidad del paciente"
	health_box.add_child(health_title)
	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = 100
	_health_bar.custom_minimum_size = Vector2(200, 16)
	_health_bar.show_percentage = false
	health_box.add_child(_health_bar)
	top_row.add_child(health_box)

	_build_weapon_bar()
	_build_radar()

	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 32)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_crosshair)

	_reload_label = Label.new()
	_reload_label.text = "RECARGANDO..."
	_reload_label.add_theme_font_size_override("font_size", 24)
	_reload_label.set_anchors_preset(Control.PRESET_CENTER)
	_reload_label.position += Vector2(0, 50)
	_reload_label.visible = false
	add_child(_reload_label)

	var help := Label.new()
	help.text = ("1-5: elegir antibiotico  |  Click izq: disparar  |  " +
		"Click der (mantener): apuntar con optica  |  R: recargar  |  ESC: liberar el raton")
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.position.y -= 24
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(help)


func _build_weapon_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.position.y -= 70
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	for i in range(GameManager.WEAPON_ORDER.size()):
		var weapon_id: String = GameManager.WEAPON_ORDER[i]
		var data: Dictionary = GameManager.ANTIBIOTICS[weapon_id]
		var color: Color = data.get("color", Color.WHITE)

		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(170, 40)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color.r, color.g, color.b, 0.15)
		style.border_color = color
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		slot.add_theme_stylebox_override("panel", style)

		var label := Label.new()
		label.text = "%d  %s" % [i + 1, data.get("label", weapon_id).to_upper()]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", color)
		slot.add_child(label)

		bar.add_child(slot)
		_weapon_slots[weapon_id] = slot


func _build_radar() -> void:
	_radar = RadarDisplay.new()
	_radar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_radar.position = Vector2(24, -170)
	_radar.custom_minimum_size = Vector2(140, 140)
	add_child(_radar)


func _on_score_changed(new_score: int) -> void:
	_score_label.text = "Puntuacion: %d" % new_score


func set_active_weapon(weapon_id: String) -> void:
	for id in _weapon_slots.keys():
		var slot: PanelContainer = _weapon_slots[id]
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel")
		var color: Color = GameManager.ANTIBIOTICS[id].get("color", Color.WHITE)
		if id == weapon_id:
			style.bg_color = Color(color.r, color.g, color.b, 0.55)
			style.set_border_width_all(4)
		else:
			style.bg_color = Color(color.r, color.g, color.b, 0.15)
			style.set_border_width_all(2)


func _on_health_changed(new_health: float) -> void:
	_health_bar.value = new_health


func update_ammo(current: int, max_ammo: int, reloading: bool) -> void:
	_ammo_label.text = "Municion: %d / %d" % [current, max_ammo]
	_reload_label.visible = reloading


func show_wave(current: int, total: int) -> void:
	_wave_label.text = "Oleada %d / %d" % [current, total]


func show_wave_cleared(current: int) -> void:
	_wave_label.text = "Oleada %d superada" % current


func update_radar(points: Array) -> void:
	if _radar:
		_radar.set_points(points)


func set_aiming(is_aiming: bool) -> void:
	if is_aiming:
		_crosshair.text = "."
		_crosshair.add_theme_font_size_override("font_size", 16)
	else:
		_crosshair.text = "+"
		_crosshair.add_theme_font_size_override("font_size", 32)


func show_results(won: bool) -> void:
	if _results_panel:
		return

	_results_panel = ColorRect.new()
	_results_panel.color = Color(0, 0, 0, 0.75)
	_results_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_results_panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_results_panel.add_child(box)

	var title := Label.new()
	title.text = "Mision cumplida" if won else "El paciente se ha desestabilizado"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var score_lbl := Label.new()
	score_lbl.text = "Puntuacion final: %d" % GameManager.score
	score_lbl.add_theme_font_size_override("font_size", 24)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(score_lbl)

	var restart_btn := Button.new()
	restart_btn.text = "Reintentar"
	restart_btn.pressed.connect(_on_restart_pressed)
	box.add_child(restart_btn)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


## Radar circular simple: un punto por objetivo activo, en coordenadas relativas al
## helicoptero (ya rotadas para que "arriba" sea el frente). Se dibuja a mano con
## _draw(), sin necesidad de texturas.
class RadarDisplay extends Control:
	const RANGE := 45.0
	var _points: Array = []

	func set_points(points: Array) -> void:
		_points = points
		queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		var radius: float = min(size.x, size.y) / 2.0
		draw_circle(center, radius, Color(0, 0, 0, 0.45))
		draw_arc(center, radius, 0, TAU, 32, Color(0.4, 0.9, 0.5, 0.8), 2.0)
		draw_line(center, center + Vector2(0, -radius), Color(0.4, 0.9, 0.5, 0.5), 1.0)

		for p in _points:
			var dist_ratio: float = clamp(Vector2(p.x, p.y).length() / RANGE, 0.0, 1.0)
			var dir: Vector2 = Vector2(p.x, p.y).normalized() if Vector2(p.x, p.y).length() > 0.01 else Vector2.ZERO
			# "Arriba" del radar = delante del helicoptero -> invertimos Y de pantalla.
			var screen_pos := center + Vector2(dir.x, -dir.y) * dist_ratio * (radius - 6)
			draw_circle(screen_pos, 4.0, Color(0.95, 0.3, 0.3))
