using Godot;

/// <summary>
/// Класс для точных математических расчетов системы день/ночь
/// Все расчеты вынесены в C# для повышения производительности
/// </summary>
public partial class DayNightCalculator : Node
{
	// Константы времени
	private const float LIGHT_START_HOUR = 2.0f;
	private const float MORNING_PEAK_HOUR = 10.0f;
	private const float SUNSET_PEAK_HOUR = 18.0f;
	private const float DUSK_END_HOUR = 22.0f;
	private const float DAWN_PEAK_HOUR = 6.0f;
	private const float PEAK_NIGHT_HOUR_1 = 0.0f;
	private const float PEAK_NIGHT_HOUR_2 = 24.0f;
	
	// Константы для реалистичного освещения
	private const float SUNRISE_HOUR = 6.0f;
	private const float SUNSET_HOUR = 18.0f;
	private const float NOON_HOUR = 12.0f;

	// Enum для периодов дня (аналог GDScript)
	public enum TimeOfDay
	{
		MIDNIGHT = 0, // ~00:00 - 04:00
		DAWN = 1,     // ~04:00 - 06:00 (Начало света)
		MORNING = 2,  // ~06:00 - 10:00 (Яркое утро)
		NOON = 3,     // ~10:00 - 14:00 (Полдень, самый яркий)
		AFTERNOON = 4,// ~14:00 - 18:00 (День, послеполуденное солнце)
		EVENING = 5,  // ~18:00 - 20:00 (Начало сумерек)
		DUSK = 6,     // ~20:00 - 22:00 (Сумерки, темнеет)
		NIGHT = 7     // ~22:00 - 00:00 (Глубокая ночь)
	}

	// Текстовые описания времени (РУССКИЕ)
	private readonly string[] timeDescriptionsRu = new string[]
	{
		"Полночь",   // MIDNIGHT
		"Рассвет",   // DAWN
		"Утро",      // MORNING
		"Полдень",   // NOON
		"День",      // AFTERNOON
		"Вечер",     // EVENING
		"Сумерки",   // DUSK
		"Ночь"       // NIGHT
	};

	// Текстовые описания времени (АНГЛИЙСКИЕ)
	private readonly string[] timeDescriptionsEn = new string[]
	{
		"Midnight",   // MIDNIGHT
		"Dawn",       // DAWN
		"Morning",    // MORNING
		"Noon",       // NOON
		"Afternoon",  // AFTERNOON
		"Evening",    // EVENING
		"Dusk",       // DUSK
		"Night"       // NIGHT
	};

	/// <summary>
	/// Вычисляет азимут солнца (0-360°, где 90°=восток, 180°=юг, 270°=запад)
	/// </summary>
	public float CalculateSunAzimuth(float gameHour)
	{
		if (gameHour >= SUNRISE_HOUR && gameHour <= SUNSET_HOUR)
		{
			// День: солнце движется с востока (90°) на запад (270°) через юг
			float dayProgress = InverseLerp(SUNRISE_HOUR, SUNSET_HOUR, gameHour);
			return Mathf.Lerp(90.0f, 270.0f, dayProgress);
		}
		else
		{
			// Ночь: луна движется с востока на запад (противоположная сторона)
			if (gameHour > SUNSET_HOUR)
			{
				float nightProgress = InverseLerp(SUNSET_HOUR, 24.0f, gameHour);
				return Mathf.Lerp(270.0f, 450.0f, nightProgress) % 360.0f;
			}
			else
			{
				float nightProgress = InverseLerp(0.0f, SUNRISE_HOUR, gameHour);
				return Mathf.Lerp(270.0f, 90.0f, nightProgress);
			}
		}
	}

	/// <summary>
	/// Вычисляет высоту солнца над горизонтом (-10° до 60°)
	/// </summary>
	public float CalculateSunAltitude(float gameHour)
	{
		if (gameHour >= SUNRISE_HOUR && gameHour <= SUNSET_HOUR)
		{
			// Параболическая траектория: максимум в полдень
			float dayProgress = InverseLerp(SUNRISE_HOUR, SUNSET_HOUR, gameHour);
			float parabola = 1.0f - Mathf.Pow((dayProgress - 0.5f) * 2.0f, 2.0f);
			return Mathf.Lerp(-10.0f, 60.0f, parabola); // от -10° (ниже горизонта) до 60° (высоко)
		}
		else
		{
			// Ночь: луна ниже, от -30° до 40°
			float nightProgress;
			if (gameHour > SUNSET_HOUR)
			{
				nightProgress = InverseLerp(SUNSET_HOUR, 24.0f, gameHour);
			}
			else
			{
				nightProgress = InverseLerp(0.0f, SUNRISE_HOUR, gameHour) + 0.25f;
			}
			
			float parabola = 1.0f - Mathf.Pow((nightProgress - 0.5f) * 2.0f, 2.0f);
			return Mathf.Lerp(-30.0f, 40.0f, parabola);
		}
	}

	/// <summary>
	/// Вычисляет цвет света (оранжевый рассвет/закат, белый день, синеватая ночь)
	/// </summary>
	public Color CalculateLightColor(float gameHour)
	{
		Color sunriseColor = new Color(1.0f, 0.6f, 0.4f); // Оранжевый
		Color noonColor = new Color(1.0f, 0.98f, 0.95f);  // Теплый белый
		Color sunsetColor = new Color(1.0f, 0.5f, 0.3f);  // Красно-оранжевый
		Color moonColor = new Color(0.7f, 0.75f, 0.85f);  // Холодный голубоватый

		if (gameHour >= SUNRISE_HOUR - 1.0f && gameHour < SUNRISE_HOUR + 1.0f)
		{
			// Рассвет (5:00-7:00): оранжевый → белый
			float t = InverseLerp(SUNRISE_HOUR - 1.0f, SUNRISE_HOUR + 1.0f, gameHour);
			return sunriseColor.Lerp(noonColor, SmoothStep(0.0f, 1.0f, t));
		}
		else if (gameHour >= SUNRISE_HOUR + 1.0f && gameHour < SUNSET_HOUR - 1.0f)
		{
			// День (7:00-17:00): белый
			return noonColor;
		}
		else if (gameHour >= SUNSET_HOUR - 1.0f && gameHour < SUNSET_HOUR + 1.0f)
		{
			// Закат (17:00-19:00): белый → красно-оранжевый
			float t = InverseLerp(SUNSET_HOUR - 1.0f, SUNSET_HOUR + 1.0f, gameHour);
			return noonColor.Lerp(sunsetColor, SmoothStep(0.0f, 1.0f, t));
		}
		else
		{
			// Ночь: холодный лунный свет
			return moonColor;
		}
	}

	/// <summary>
	/// Вычисляет интенсивность света с плавной кривой
	/// </summary>
	public float CalculateLightIntensity(float gameHour, float maxDayIntensity, float maxNightIntensity)
	{
		if (gameHour >= SUNRISE_HOUR && gameHour <= SUNSET_HOUR)
		{
			// День: параболическая кривая с пиком в полдень
			float dayProgress = InverseLerp(SUNRISE_HOUR, SUNSET_HOUR, gameHour);
			float parabola = 1.0f - Mathf.Pow((dayProgress - 0.5f) * 2.0f, 2.0f);
			return Mathf.Lerp(maxNightIntensity, maxDayIntensity, SmoothStep(0.0f, 1.0f, parabola));
		}
		else
		{
			// Ночь: слабая луна
			return maxNightIntensity;
		}
	}

	/// <summary>
	/// Вычисляет прогресс дня/ночи (0.0 = полная ночь, 1.0 = полный день)
	/// </summary>
	public float CalculateDayNightProgress(float gameHour)
	{
		float progress = 0.0f;

		if (gameHour >= LIGHT_START_HOUR && gameHour < MORNING_PEAK_HOUR)
		{
			// Рассвет: от почти нуля до почти полной дневной яркости
			progress = InverseLerp(LIGHT_START_HOUR, MORNING_PEAK_HOUR, gameHour);
		}
		else if (gameHour >= MORNING_PEAK_HOUR && gameHour < SUNSET_PEAK_HOUR)
		{
			// Полный день: всегда 1.0
			progress = 1.0f;
		}
		else if (gameHour >= SUNSET_PEAK_HOUR && gameHour < DUSK_END_HOUR)
		{
			// Закат: от полной дневной яркости до почти нуля
			progress = InverseLerp(SUNSET_PEAK_HOUR, DUSK_END_HOUR, gameHour);
			progress = 1.0f - progress; // Инвертируем, чтобы шел от 1 до 0
		}
		else
		{
			// Полная ночь: 0.0
			progress = 0.0f;
		}

		return SmoothStep(0.0f, 1.0f, progress);
	}

	/// <summary>
	/// Вычисляет угол поворота солнца по оси X (УСТАРЕВШИЙ - используйте CalculateSunAltitude)
	/// </summary>
	public float CalculateSunRotation(float gameHour)
	{
		if (gameHour >= DAWN_PEAK_HOUR && gameHour <= SUNSET_PEAK_HOUR)
		{
			return Mathf.Lerp(90.0f, -90.0f, InverseLerp(DAWN_PEAK_HOUR, SUNSET_PEAK_HOUR, gameHour));
		}
		else if (gameHour > SUNSET_PEAK_HOUR)
		{
			return Mathf.Lerp(-90.0f, 180.0f, InverseLerp(SUNSET_PEAK_HOUR, PEAK_NIGHT_HOUR_2, gameHour));
		}
		else
		{
			return Mathf.Lerp(180.0f, 90.0f, InverseLerp(PEAK_NIGHT_HOUR_1, DAWN_PEAK_HOUR, gameHour));
		}
	}

	/// <summary>
	/// Определяет период дня на основе часа
	/// </summary>
	public TimeOfDay CalculateTimeOfDay(float gameHour)
	{
		int currentHour = (int)gameHour; // Используем целую часть часа

		return currentHour switch
		{
			22 or 23 => TimeOfDay.NIGHT,        // 22:00 - 23:59
			0 or 1 or 2 or 3 => TimeOfDay.MIDNIGHT,  // 00:00 - 03:59
			4 or 5 => TimeOfDay.DAWN,            // 04:00 - 05:59
			6 or 7 or 8 or 9 => TimeOfDay.MORNING,   // 06:00 - 09:59
			10 or 11 or 12 or 13 => TimeOfDay.NOON, // 10:00 - 13:59
			14 or 15 or 16 or 17 => TimeOfDay.AFTERNOON, // 14:00 - 17:59
			18 or 19 => TimeOfDay.EVENING,       // 18:00 - 19:59
			20 or 21 => TimeOfDay.DUSK,          // 20:00 - 21:59
			_ => TimeOfDay.NIGHT                 // Дефолтное значение
		};
	}

	/// <summary>
	/// Возвращает описание периода дня на русском
	/// </summary>
	public string GetTimeDescriptionRu(TimeOfDay timeOfDay)
	{
		return timeDescriptionsRu[(int)timeOfDay];
	}

	/// <summary>
	/// Возвращает описание периода дня на английском
	/// </summary>
	public string GetTimeDescriptionEn(TimeOfDay timeOfDay)
	{
		return timeDescriptionsEn[(int)timeOfDay];
	}

	/// <summary>
	/// Форматирует время в 12-часовом формате
	/// </summary>
	public string FormatTime(float gameHour)
	{
		int hours24 = (int)gameHour;
		int minutes = (int)((gameHour * 60.0f) % 60.0f);

		int displayHour = hours24;
		string period = "AM";

		if (displayHour >= 12) period = "PM";
		if (displayHour > 12) displayHour -= 12;
		if (displayHour == 0) displayHour = 12;

		return $"{displayHour:D2}:{minutes:D2} {period}";
	}

	/// <summary>
	/// Вычисляет игровое время с высокой точностью
	/// </summary>
	public void CalculateGameTime(float deltaTime, float dayDuration, float nightDuration,
								   ref float totalGameHours, out float currentHour, out int currentDay)
	{
		float totalCycleDuration = dayDuration + nightDuration;
		float gameHoursPerSecond = 24.0f / totalCycleDuration;

		totalGameHours += deltaTime * gameHoursPerSecond;
		currentHour = totalGameHours % 24.0f;
		currentDay = (int)(totalGameHours / 24.0f) + 1;
	}

	/// <summary>
	/// Вычисляет фактор критической ночи (День 3)
	/// </summary>
	public float CalculateCriticalNightFactor(float gameHour, int currentDay, int criticalDay)
	{
		if (currentDay != criticalDay) return 0.0f;

		float factor = 0.0f;

		if (gameHour >= SUNSET_PEAK_HOUR && gameHour <= PEAK_NIGHT_HOUR_2)
		{
			factor = InverseLerp(SUNSET_PEAK_HOUR, PEAK_NIGHT_HOUR_2, gameHour);
		}
		else if (gameHour >= PEAK_NIGHT_HOUR_1 && gameHour < DAWN_PEAK_HOUR)
		{
			factor = 1.0f - InverseLerp(PEAK_NIGHT_HOUR_1, DAWN_PEAK_HOUR, gameHour);
		}

		return SmoothStep(0.0f, 1.0f, factor);
	}

	/// <summary>
	/// Определяет, день ли сейчас (логика игры: 6:00-18:00 = день)
	/// </summary>
	public bool IsDay(float gameHour)
	{
		int hour = (int)gameHour;
		return hour >= 6 && hour < 18;
	}

	/// <summary>
	/// Вычисляет интерполированные цвета для неба
	/// </summary>
	public Color InterpolateSkyColor(Color nightColor, Color dayColor, float dayNightProgress)
	{
		return nightColor.Lerp(dayColor, dayNightProgress);
	}

	/// <summary>
	/// Вычисляет интерполированную энергию освещения
	/// </summary>
	public float InterpolateLightEnergy(float nightEnergy, float dayEnergy, float dayNightProgress)
	{
		return Mathf.Lerp(nightEnergy, dayEnergy, dayNightProgress);
	}

	/// <summary>
	/// Получить оставшееся время в текущей фазе дня/ночи
	/// </summary>
	public float GetTimeRemainingInCurrentPhase(float totalGameHours, float dayDuration, float nightDuration, bool isDay)
	{
		float hoursInCurrentCycle = totalGameHours % 24.0f;
		float totalCycleDuration = dayDuration + nightDuration;
		float realSecondsPerGameHour = totalCycleDuration / 24.0f;

		if (isDay)
		{
			float hoursUntilNight = 18.0f - hoursInCurrentCycle;
			return hoursUntilNight * realSecondsPerGameHour;
		}
		else
		{
			float hoursUntilNextMorning;
			if (hoursInCurrentCycle >= 18.0f)
			{
				hoursUntilNextMorning = 24.0f - hoursInCurrentCycle + 6.0f;
			}
			else
			{
				hoursUntilNextMorning = 6.0f - hoursInCurrentCycle;
			}
			return hoursUntilNextMorning * realSecondsPerGameHour;
		}
	}

	/// <summary>
	/// Форматирует оставшееся время в MM:SS формате
	/// </summary>
	public string FormatRemainingTime(float remainingSeconds)
	{
		int minutes = (int)(remainingSeconds / 60);
		int seconds = (int)(remainingSeconds % 60);
		return $"{minutes:D2}:{seconds:D2}";
	}

	// Вспомогательные математические функции
	private float InverseLerp(float a, float b, float value)
	{
		return a == b ? 0.0f : Mathf.Clamp((value - a) / (b - a), 0.0f, 1.0f);
	}

	private float SmoothStep(float edge0, float edge1, float x)
	{
		x = Mathf.Clamp((x - edge0) / (edge1 - edge0), 0.0f, 1.0f);
		return x * x * (3.0f - 2.0f * x);
	}
}
