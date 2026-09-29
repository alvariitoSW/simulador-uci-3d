extends Node
## Autoload: estado compartido del prototipo (puntuacion, arma/antibiotico actual,
## estabilidad del paciente).
##
## Los antibioticos y microorganismos son una simplificacion de la logica real de
## "tratamiento empirico" del proyecto hermano de neutropenia febril (protocolo
## SEIMC-SEHH 2020): cada antibiotico solo tiene cobertura fuerte contra ciertas
## categorias de microorganismo, igual que en la practica clinica. Acertar la
## cobertura = arma potente y precisa; fallarla = arma debil.

signal score_changed(new_score: int)
signal weapon_changed(weapon_id: String)
signal patient_health_changed(new_health: float)
signal game_over(won: bool)

const ANTIBIOTICS := {
	"pip_tazo": {
		"label": "Piperacilina-tazobactam",
		"weapon_name": "Ametralladora estandar",
		"strong_vs": ["gram_negativo_sensible"],
	},
	"vancomicina": {
		"label": "Vancomicina",
		"weapon_name": "Escopeta de precision",
		"strong_vs": ["gram_positivo"],
	},
	"meropenem": {
		"label": "Meropenem (carbapenem)",
		"weapon_name": "Lanzagranadas de amplio espectro",
		"strong_vs": ["gram_negativo_mdr", "gram_negativo_sensible"],
	},
}

const PATHOGENS := {
	"gram_positivo": {
		"label": "Staphylococcus aureus",
		"color": Color(0.85, 0.2, 0.25),
	},
	"gram_negativo_sensible": {
		"label": "E. coli sensible",
		"color": Color(0.2, 0.55, 0.9),
	},
	"gram_negativo_mdr": {
		"label": "BGN productor de BLEE (MDR)",
		"color": Color(0.85, 0.55, 0.1),
	},
}

const WEAK_HIT_DAMAGE := 8.0
const PATIENT_DAMAGE_PER_WRONG_KILL := 6.0

var score: int = 0
var current_weapon: String = "pip_tazo"
var patient_health: float = 100.0
var targets_killed: int = 0
var targets_total: int = 0
var _game_over_fired: bool = false


func reset_run() -> void:
	score = 0
	patient_health = 100.0
	targets_killed = 0
	targets_total = 0
	current_weapon = "pip_tazo"
	_game_over_fired = false
	score_changed.emit(score)
	patient_health_changed.emit(patient_health)
	weapon_changed.emit(current_weapon)


func set_weapon(weapon_id: String) -> void:
	if not ANTIBIOTICS.has(weapon_id):
		return
	current_weapon = weapon_id
	weapon_changed.emit(current_weapon)


func is_effective(weapon_id: String, pathogen_id: String) -> bool:
	var data: Dictionary = ANTIBIOTICS.get(weapon_id, {})
	var strong_vs: Array = data.get("strong_vs", [])
	return pathogen_id in strong_vs


func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)


func damage_patient(amount: float) -> void:
	patient_health = clamp(patient_health - amount, 0.0, 100.0)
	patient_health_changed.emit(patient_health)
	if patient_health <= 0.0:
		_fire_game_over(false)


func register_kill() -> void:
	targets_killed += 1
	if targets_total > 0 and targets_killed >= targets_total:
		_fire_game_over(true)


func _fire_game_over(won: bool) -> void:
	if _game_over_fired:
		return
	_game_over_fired = true
	game_over.emit(won)
