class_name BarricadeInteract
extends StaticBody3D
## Interactable collider proxy for a Barricade so the player can hold E
## to repair even when all boards are broken.

@export var barricade_path: NodePath = NodePath("..")


func get_barricade() -> Barricade:
	return get_node_or_null(barricade_path) as Barricade
