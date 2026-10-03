class_name ShadowCasterPolicy
extends Node

## Keeps low-value generated geometry out of directional shadow passes while
## preserving shadows from authored/near buildings, roofs, utility poles and
## other large silhouettes. Generated city nodes use stable names, so the same
## policy also applies when streaming creates them later.

const SHADOW_OFF_NAMES: Dictionary = {
	&"PowerWires": true,
	&"Crossings": true,
	&"Curbs": true,
	&"Sidewalks": true,
	&"WhiteMarkings": true,
	&"YellowCenterlines": true,
	&"OneWayArrows": true,
	&"MappedSidewalks": true,
	&"CoastlineEdge": true,
	&"Runways": true,
	&"Taxiways": true,
	&"AirportWhiteMarkings": true,
	&"AirportYellowMarkings": true,
	&"WasteBaskets": true,
	&"FireHydrants": true,
	&"Bollards": true,
	&"PostBoxes": true,
	&"GolfTeeMarkers": true,
	&"Ring0Massing": true,
}

const SHADOW_OFF_PREFIXES: Array[String] = [
	"Ring0_",      # Island-wide far road ribbons.
	"Surface_",    # Streamed local road ribbons.
	"AirportArea_", # Flat runway/taxiway/apron polygons.
]


func _ready() -> void:
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	call_deferred(&"_apply_existing")


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


func _apply_existing() -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	_apply_recursive(root)


func _apply_recursive(node: Node) -> void:
	_apply(node)
	for child: Node in node.get_children():
		_apply_recursive(child)


func _on_node_added(node: Node) -> void:
	_apply(node)


func _apply(node: Node) -> void:
	if not node is GeometryInstance3D:
		return
	if not _should_disable_shadow(node):
		return
	(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _should_disable_shadow(node: Node) -> bool:
	if SHADOW_OFF_NAMES.has(node.name):
		return true
	var node_name := String(node.name)
	for prefix: String in SHADOW_OFF_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	var parent := node.get_parent()
	return parent != null and parent.name == &"ChunkGrid"
