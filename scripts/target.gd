extends Area3D
class_name PathogenTarget
## Un microorganismo objetivo, con aspecto de criatura (cuerpo con bultos + ojos),
## que avanza lentamente hacia el helicoptero. Se crea enteramente por codigo desde
## main.gd: setup() construye su propia malla, etiqueta y forma de colision.

signal killed(was_correct: bool)
signal escaped

@export var speed: float = 1.2
@export var escape_z: float = 4.5

var pathogen_id: String = ""
var health: float = 30.0
var _material: StandardMaterial3D
var _base_y: float = 0.0
var _time: float = 0.0
var _resolved: bool = false


func setup(p_pathogen_id: String, spawn_position: Vector3) -> void:
	pathogen_id = p_pathogen_id
	position = spawn_position
	_base_y = spawn_position.y
	collision_layer = 2
	collision_mask = 0

	var data: Dictionary = GameManager.PATHOGENS.get(pathogen_id, {})
	_material = StandardMaterial3D.new()
	_material.albedo_color = data.get("color", Color.WHITE)

	_build_monster_body()

	var label := Label3D.new()
	label.text = String(data.get("label", pathogen_id))
	label.position = Vector3(0, 1.5, 0)
	label.font_size = 40
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.75
	collision.shape = shape
	add_child(collision)


func _build_monster_body() -> void:
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.7
	body_mesh.height = 1.1
	body.mesh = body_mesh
	body.scale = Vector3(1.0, 0.85, 1.0)
	body.material_override = _material
	add_child(body)

	# Bultos/verrugas alrededor del cuerpo, para que lea como criatura organica en
	# vez de una forma geometrica limpia. Usamos esferas (no conos) para no tener
	# que resolver su orientacion exacta hacia fuera.
	var wart_positions := [
		Vector3(0.55, 0.35, 0.1), Vector3(-0.55, 0.3, -0.15),
		Vector3(0.1, 0.6, 0.5), Vector3(-0.2, 0.55, -0.45),
		Vector3(0.35, -0.1, -0.55), Vector3(-0.4, -0.2, 0.4),
	]
	for wart_pos in wart_positions:
		var wart := MeshInstance3D.new()
		var wart_mesh := SphereMesh.new()
		wart_mesh.radius = 0.18
		wart_mesh.height = 0.36
		wart.mesh = wart_mesh
		wart.material_override = _material
		wart.position = wart_pos
		add_child(wart)

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.95, 0.95, 0.9)
	var pupil_mat := StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.05, 0.05, 0.05)

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.14
		eye_mesh.height = 0.28
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.28, 0.15, -0.55)
		add_child(eye)

		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.06
		pupil_mesh.height = 0.12
		pupil.mesh = pupil_mesh
		pupil.material_override = pupil_mat
		pupil.position = Vector3(side * 0.28, 0.15, -0.66)
		add_child(pupil)


func _process(delta: float) -> void:
	if _resolved:
		return
	_time += delta
	position.z += speed * delta
	position.y = _base_y + sin(_time * 2.5) * 0.12
	rotation.y += delta * 0.6

	if position.z >= escape_z:
		_escape()


func hit(weapon_id: String) -> void:
	if _resolved:
		return
	var effective: bool = GameManager.is_effective(weapon_id, pathogen_id)
	if effective:
		_die(true)
	else:
		health -= GameManager.WEAK_HIT_DAMAGE
		_flash_weak_hit()
		if health <= 0.0:
			_die(false)


func _flash_weak_hit() -> void:
	if not _material:
		return
	var original := _material.albedo_color
	_material.albedo_color = Color.WHITE
	var t := create_tween()
	t.tween_property(_material, "albedo_color", original, 0.15)


func _die(was_correct: bool) -> void:
	_resolved = true
	killed.emit(was_correct)
	queue_free()


func _escape() -> void:
	_resolved = true
	escaped.emit()
	queue_free()
