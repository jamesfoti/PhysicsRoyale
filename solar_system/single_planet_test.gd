extends SolarSystem
class_name SinglePlanetTest

@export var planet_name: String = "Earth"


func _create_bodies() -> Array[StellarBody]:
	return SolarSystemSetup.create_single_planet_data(planet_name, _settings)


func set_reference_body(ref_id: int):
	# Stay in sun-centric coordinates so lighting and shadows behave like flying near a planet.
	if ref_id != 0:
		return
	super.set_reference_body(ref_id)


func _on_game_loaded():
	if len(_bodies) < 2:
		return
	_update_body_transforms()
	var planet := _bodies[1]
	var planet_pos := planet.node.global_transform.origin
	_ship.global_position = planet_pos + Vector3(0.0, planet.radius + 800.0, 0.0)
	_update_directional_light()
