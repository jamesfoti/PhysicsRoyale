extends Area3D

# Notifies the player which planet's gravity field they are in.
# Based on Pigeonaut's walk-around-planet demo:
# https://www.youtube.com/watch?v=aL8TB_mB3j8

const StellarBody = preload("res://solar_system/stellar_body.gd")

var stellar_body: StellarBody


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("set_gravity_planet"):
		body.set_gravity_planet(stellar_body)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("clear_gravity_planet"):
		body.clear_gravity_planet(stellar_body)
