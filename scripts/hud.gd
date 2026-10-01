extends CanvasLayer
class_name GameHUD
## Interfaz construida enteramente por codigo (sin escena .tscn propia): puntuacion,
## arma/antibiotico equipado, municion, barra de estabilidad del paciente, mira
## (cadera/optica) y pantalla de resultados.

var _score_label: Label
var _weapon_label: Label
var _ammo_label: Label
var _reload_label: Label
var _health_bar: ProgressBar
var _crosshair: Label
var _results_panel: Control


func _ready() -> void:
	layer = 1
	_build_hud()
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.weapon_changed.connect(_on_weapon_changed)
	GameManager.patient_health_changed.connect(_on_health_changed)
	_on_score_changed(GameManager.score)
	_on_weapon_changed(GameManager.current_weapon)
	_on_health_changed(GameManager.patient_health)


func _build_hud() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	add_child(margin)

	# Dos filas en vez de una sola, para que quepan en pantallas estrechas sin que
	# la barra de estabilidad se salga por el borde derecho.
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

	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 18)
	rows.add_child(_weapon_label)

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
	help.text = ("1/2/3: elegir antibiotico  |  Click izq: disparar  |  " +
		"Click der (mantener): apuntar con optica  |  R: recargar  |  ESC: liberar el raton")
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.position.y -= 40
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(help)


func _on_score_changed(new_score: int) -> void:
	_score_label.text = "Puntuacion: %d" % new_score


func _on_weapon_changed(weapon_id: String) -> void:
	var data: Dictionary = GameManager.ANTIBIOTICS.get(weapon_id, {})
	_weapon_label.text = "Arma: %s (%s)" % [data.get("weapon_name", "?"), data.get("label", weapon_id)]


func _on_health_changed(new_health: float) -> void:
	_health_bar.value = new_health


func update_ammo(current: int, max_ammo: int, reloading: bool) -> void:
	_ammo_label.text = "Municion: %d / %d" % [current, max_ammo]
	_reload_label.visible = reloading


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
