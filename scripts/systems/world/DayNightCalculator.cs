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
	/// Вычисляет угол поворота солнца по оси X
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
