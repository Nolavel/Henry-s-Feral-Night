extends TextureRect

func _ready():
	# Получаем текстуру от SubViewport
	var minimap_viewport = $"../../MinimapViewport" # Путь к вашему Viewport
	texture = minimap_viewport.get_texture()
