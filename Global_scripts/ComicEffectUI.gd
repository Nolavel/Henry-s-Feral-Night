# ComicEffectUI.gd - ОПТИМИЗИРОВАННАЯ версия БЕЗ шейдеров
extends Control

@onready var label: Label = $Label
@onready var audio_player: AudioStreamPlayer = $Sound_Voice_HIT_Damage

# ОПТИМИЗАЦИЯ: Один переиспользуемый tween
var effect_tween: Tween

# ОПТИМИЗАЦИЯ: Кешированные звуки
@export var player_hit_sounds: Array[AudioStream] = []

# ОПТИМИЗАЦИЯ: Простые цвета вместо шейдеров
var effect_texts = {
	ComicEffects.EffectType.PLAYER_SHOOT: ["BANG!", "POW!", "BLAM!", "FIRE!", "BOOM!", "SHOT!", "PEW!", "ZAP!"],
	ComicEffects.EffectType.PLAYER_HIT: ["OUCH!", "ARGH!", "UGH!", "PAIN!", "OW!", "HURT!", "AGH!", "DAMN!"],
	ComicEffects.EffectType.PLAYER_DEATH: ["NOOO!", "DEAD!", "GAME OVER!", "RIP!", "DIED!", "FINISH!", "END!"],
	ComicEffects.EffectType.ENEMY_HIT: ["UGH!", "GRUNT!", "HIT!", "PAIN!", "OW!", "HURT!", "SMACK!", "THUD!"],
	ComicEffects.EffectType.ENEMY_DEATH: ["DEAD!", "X_X", "KILLED!", "DOWN!", "FINISH!", "DONE!", "RIP!"],
	ComicEffects.EffectType.EXPLOSION: ["BOOM!", "KABOOM!", "BLAST!", "EXPLODE!", "CRASH!", "WHAM!", "BURST!"],
	ComicEffects.EffectType.HEADSHOT: ["HEADSHOT!", "CRITICAL!", "PERFECT!", "NICE!", "BULLSEYE!", "CRIT!", "AMAZING!"],
	ComicEffects.EffectType.PICKUP: ["GOT IT!", "NICE!", "PICKUP!", "ITEM!", "YES!", "COOL!", "SWEET!"],
	ComicEffects.EffectType.OBJECT_HIT: ["DING!", "CLANG!", "MISS!", "RICOCHET!", "SPARK!", "PLINK!", "CLANK!", "PING!"]
}

# ОПТИМИЗАЦИЯ: Более яркие цвета для лучшей видимости
var effect_colors = {
	ComicEffects.EffectType.PLAYER_SHOOT: Color(1.0, 1.0, 0.0, 1.0),      # Ярко-желтый
	ComicEffects.EffectType.PLAYER_HIT: Color(1.0, 0.2, 0.2, 1.0),        # Ярко-красный
	ComicEffects.EffectType.PLAYER_DEATH: Color(0.8, 0.0, 0.0, 1.0),      # Темно-красный
	ComicEffects.EffectType.ENEMY_HIT: Color(1.0, 0.5, 0.0, 1.0),         # Оранжевый
	ComicEffects.EffectType.ENEMY_DEATH: Color(0.6, 0.6, 0.6, 1.0),       # Серый
	ComicEffects.EffectType.EXPLOSION: Color(1.0, 0.3, 0.0, 1.0),         # Красно-оранжевый
	ComicEffects.EffectType.HEADSHOT: Color(0.0, 1.0, 1.0, 1.0),          # Циан
	ComicEffects.EffectType.PICKUP: Color(0.0, 1.0, 0.0, 1.0),            # Зеленый
	ComicEffects.EffectType.OBJECT_HIT: Color(0.8, 0.8, 0.8, 1.0)         # Светло-серый
}

# ОПТИМИЗАЦИЯ: Кешированные стили для разных эффектов
var effect_styles = {
	ComicEffects.EffectType.PLAYER_SHOOT: {"size": 1.2, "outline": true},
	ComicEffects.EffectType.PLAYER_HIT: {"size": 1.4, "outline": true},
	ComicEffects.EffectType.PLAYER_DEATH: {"size": 1.6, "outline": true},
	ComicEffects.EffectType.ENEMY_HIT: {"size": 1.0, "outline": false},
	ComicEffects.EffectType.ENEMY_DEATH: {"size": 1.2, "outline": false},
	ComicEffects.EffectType.EXPLOSION: {"size": 1.8, "outline": true},
	ComicEffects.EffectType.HEADSHOT: {"size": 1.5, "outline": true},
	ComicEffects.EffectType.PICKUP: {"size": 1.1, "outline": false},
	ComicEffects.EffectType.OBJECT_HIT: {"size": 0.9, "outline": false}
}

func _ready():
	visible = false
	modulate.a = 0.0
	scale = Vector2.ZERO
	
	# ОПТИМИЗАЦИЯ: Настраиваем AudioStreamPlayer один раз
	if not audio_player:
		audio_player = AudioStreamPlayer.new()
		add_child(audio_player)
	
	audio_player.volume_db = -5  # Немного тише для комфорта

func setup_optimized(screen_pos: Vector2, effect_type, custom_text: String = ""):
	"""ОПТИМИЗИРОВАННАЯ функция настройки эффекта"""
	position = screen_pos
	scale = Vector2.ZERO
	modulate.a = 1.0
	
	# Выбираем текст
	var text = custom_text
	if text.is_empty():
		var texts = effect_texts.get(effect_type, ["EFFECT!"])
		text = texts[randi() % texts.size()]
	
	label.text = text
	
	# ОПТИМИЗАЦИЯ: Применяем цвет и стиль
	var color = effect_colors.get(effect_type, Color.WHITE)
	var style = effect_styles.get(effect_type, {"size": 1.0, "outline": false})
	
	label.modulate = color
	
	# ОПТИМИЗАЦИЯ: Простое изменение размера шрифта вместо шейдеров
	if label.get_theme_font_size("font_size") != null:
		var base_font_size = 24  # Базовый размер
		var new_size = int(base_font_size * style.size)
		label.add_theme_font_size_override("font_size", new_size)
	
	# ОПТИМИЗАЦИЯ: Простая обводка вместо шейдеров
	if style.outline:
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 2)
	else:
		label.add_theme_constant_override("outline_size", 0)
	
	visible = true
	
	# Воспроизводим звук только для попаданий по игроку
	if effect_type == ComicEffects.EffectType.PLAYER_HIT and player_hit_sounds.size() > 0:
		play_hit_sound()

func play_hit_sound():
	"""ОПТИМИЗИРОВАННАЯ функция воспроизведения звука"""
	if audio_player.playing:
		return  # Не прерываем уже играющий звук
	
	var random_sound = player_hit_sounds[randi() % player_hit_sounds.size()]
	if random_sound:
		audio_player.stream = random_sound
		audio_player.play()

func play_animation_optimized():
	"""ОПТИМИЗИРОВАННАЯ анимация без создания нового tween"""
	# ОПТИМИЗАЦИЯ: Останавливаем предыдущую анимацию вместо пересоздания
	if effect_tween:
		effect_tween.kill()
	
	effect_tween = create_tween()
	effect_tween.set_parallel(true)
	
	# Быстрое появление
	effect_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	effect_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.05).set_delay(0.1)
	
	# Исчезновение
	effect_tween.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(0.6)
	
	# Небольшое движение вверх
	effect_tween.tween_property(self, "position:y", position.y - 20, 1.0)
	
	# Возврат в пул
	effect_tween.tween_callback(return_to_pool).set_delay(1.0)

func force_stop():
	"""НОВАЯ ФУНКЦИЯ: Принудительно останавливает эффект"""
	if effect_tween:
		effect_tween.kill()
	
	if audio_player and audio_player.playing:
		audio_player.stop()
	
	visible = false
	scale = Vector2.ZERO
	modulate.a = 0.0

func return_to_pool():
	"""ОПТИМИЗИРОВАННАЯ функция возврата в пул"""
	# Останавливаем звук если играет
	if audio_player and audio_player.playing:
		audio_player.stop()
	
	# Сбрасываем состояние
	visible = false
	scale = Vector2.ZERO
	modulate.a = 0.0
	
	# Очищаем переопределения темы
	label.remove_theme_font_size_override("font_size")
	label.remove_theme_color_override("font_outline_color")
	label.remove_theme_constant_override("outline_size")
	
	# Возвращаем в пул
	ComicEffects.return_effect_to_pool(self)

# ОТЛАДОЧНЫЕ ФУНКЦИИ
func is_playing() -> bool:
	"""Проверяет, проигрывается ли эффект"""
	return visible and modulate.a > 0.0

func get_effect_duration() -> float:
	"""Возвращает оставшуюся длительность эффекта"""
	if effect_tween and effect_tween.is_valid():
		return 1.0 - effect_tween.get_total_elapsed_time()
	return 0.0
