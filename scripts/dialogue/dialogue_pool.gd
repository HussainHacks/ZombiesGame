class_name DialoguePool
extends Resource
## Resource mapping dialogue category names to arrays of short subtitle lines.

@export var pool_id: String = ""
@export var categories: Dictionary = {}


func get_lines(category: String) -> Array[String]:
	var raw: Variant = categories.get(category, [])
	var out: Array[String] = []
	if raw is Array:
		for item: Variant in raw:
			var s: String = str(item).strip_edges()
			if not s.is_empty():
				out.append(s)
	return out
