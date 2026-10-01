extends Node
## Autoload: estado compartido del prototipo (puntuacion, arma/antibiotico actual,
## estabilidad del paciente, oleadas).
##
## Los antibioticos y microorganismos son una simplificacion de la logica real de
## "tratamiento empirico": cada antibiotico solo tiene cobertura fuerte contra una
## categoria de microorganismo, igual que en la practica clinica. Acertar la
## cobertura = arma potente y precisa; fallarla = arma debil.
##
## Cada antibiotico tiene ademas su propia identidad como arma (cargador, cadencia,
## precision de cadera/mira, color de identificacion) para que elegirlo tambien sea
## una decision de estilo de juego, no solo de cobertura clinica.

signal score_changed(new_score: int)
signal weapon_changed(weapon_id: String)
signal patient_health_changed(new_health: float)
signal wave_started(current: int, total: int)
signal wave_cleared(current: int)
signal game_over(won: bool)

const ANTIBIOTICS := {
	"amoxicilina": {
		"label": "Amoxicilina",
		"weapon_name": "Fusil ligero",
		"strong_vs": ["gram_positivo"],
		"color": Color(0.3, 0.55, 0.95),
		"magazine_size": 30,
		"reload_time": 1.4,
		"fire_rate": 0.1,
		"spread_hip_deg": 4.0,
		"spread_ads_deg": 1.0,
	},
	"ceftriaxona": {
		"label": "Ceftriaxona",
		"weapon_name": "Ametralladora estandar",
		"strong_vs": ["gram_negativo"],
		"color": Color(0.3, 0.8, 0.4),
		"magazine_size": 25,
		"reload_time": 1.6,
		"fire_rate": 0.12,
		"spread_hip_deg": 4.0,
		"spread_ads_deg": 1.0,
	},
	"vancomicina": {
		"label": "Vancomicina",
		"weapon_name": "Rifle de precision",
		"strong_vs": ["gram_positivo_resistente"],
		"color": Color(0.7, 0.4, 0.9),
		"magazine_size": 6,
		"reload_time": 2.0,
		"fire_rate": 0.5,
		"spread_hip_deg": 2.0,
		"spread_ads_deg": 0.3,
	},
	"azitromicina": {
		"label": "Azitromicina",
		"weapon_name": "Subfusil rapido",
		"strong_vs": ["atipico"],
		"color": Color(0.95, 0.8, 0.2),
		"magazine_size": 35,
		"reload_time": 1.3,
		"fire_rate": 0.08,
		"spread_hip_deg": 5.5,
		"spread_ads_deg": 1.5,
	},
	"anfotericina_b": {
		"label": "Anfotericina B",
		"weapon_name": "Lanzagranadas antifungico",
		"strong_vs": ["hongo"],
		"color": Color(0.95, 0.55, 0.15),
		"magazine_size": 4,
		"reload_time": 2.6,
		"fire_rate": 0.9,
		"spread_hip_deg": 7.0,
		"spread_ads_deg": 2.0,
	},
}

const WEAPON_ORDER := ["amoxicilina", "ceftriaxona", "vancomicina", "azitromicina", "anfotericina_b"]

const PATHOGENS := {
	"gram_positivo": {
		"label": "Staphylococcus aureus",
		"color": Color(0.3, 0.55, 0.95),
		"shape": "cluster",
	},
	"gram_negativo": {
		"label": "Escherichia coli",
		"color": Color(0.3, 0.8, 0.4),
		"shape": "rod",
	},
	"gram_positivo_resistente": {
		"label": "SARM (resistente)",
		"color": Color(0.7, 0.4, 0.9),
		"shape": "spiky_cluster",
	},
	"atipico": {
		"label": "Mycoplasma pneumoniae",
		"color": Color(0.95, 0.8, 0.2),
		"shape": "spiky_ball",
	},
	"hongo": {
		"label": "Candida albicans",
		"color": Color(0.95, 0.55, 0.15),
		"shape": "branching",
	},
}

const WAVE_SIZES := [6, 8, 10, 12]

const WEAK_HIT_DAMAGE := 8.0
const PATIENT_DAMAGE_PER_WRONG_KILL := 6.0
const PATIENT_DAMAGE_PER_ESCAPE := 12.0

var score: int = 0
var current_weapon: String = WEAPON_ORDER[0]
var patient_health: float = 100.0
var current_wave: int = 0
var targets_killed_this_wave: int = 0
var targets_total_this_wave: int = 0
var _game_over_fired: bool = false


func reset_run() -> void:
	score = 0
	patient_health = 100.0
	current_wave = 0
	targets_killed_this_wave = 0
	targets_total_this_wave = 0
	current_weapon = WEAPON_ORDER[0]
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


## Avanza a la siguiente oleada. Devuelve false si ya se jugaron todas.
func start_next_wave() -> bool:
	if current_wave >= WAVE_SIZES.size():
		return false
	current_wave += 1
	targets_killed_this_wave = 0
	targets_total_this_wave = WAVE_SIZES[current_wave - 1]
	wave_started.emit(current_wave, WAVE_SIZES.size())
	return true


func register_kill() -> void:
	targets_killed_this_wave += 1
	if targets_killed_this_wave >= targets_total_this_wave:
		if current_wave >= WAVE_SIZES.size():
			_fire_game_over(true)
		else:
			wave_cleared.emit(current_wave)


func _fire_game_over(won: bool) -> void:
	if _game_over_fired:
		return
	_game_over_fired = true
	game_over.emit(won)
