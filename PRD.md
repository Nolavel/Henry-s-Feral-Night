# Hoarbound — Product Requirements Document (PRD)

> Живой документ. Обновляется при закрытии milestone или смене приоритета.  
> Владелец: Nolavel.  
> Технические соисполнители: Claude Code (`claudeflow`), Codex (`codex`).  
> Scope control, audits, vertical-slice readiness: Grok (`grok`) — предлагает, не реализует gameplay.

См. также: [AGENTS.md](AGENTS.md), [docs/game_design/VERTICAL_SLICE.md](docs/game_design/VERTICAL_SLICE.md), [CONTRIBUTING_DECOMPOSITION.md](CONTRIBUTING_DECOMPOSITION.md).

---

## 1. Vision

Сурвайвал-экшен от третьего лица о выживании в замёрзшем апокалипсисе.  
Бывший тропический остров Key West замёрз. Генри выходит из бункера и должен дойти до дома, который сможет удержать ночь: найти топливо, заколотить окна, поддерживать печь и оставаться сухим.

Соло-проект, прототип. Движок: Godot 4.8-dev6 .NET (Forward+, GDScript).

## 2. Player fantasy и core loop

```
запертый бункер → выбор land-маршрута → scarce resources → ухудшение погоды
→ убежище → ремонт (boarding) → огонь → просушка → сон / save
```

Ключевые ощущения, которые должны считываться без подсказок:

- **scarcity** — доски, топливо, еда и время ограничены;
- **shelter-as-verb** — убежище не готово по умолчанию, его нужно *сделать*;
- **sleep = save** — сон завершает цикл и создаёт точку сохранения;
- **Kenny-as-weight** — переносимый груз ощутимо влияет на решения.

Референс по decision pressure: *The Long Dark*. Тон: *The Road*.

## 3. Текущий продуктовый рубеж

Runtime update 2026-09-29: Key West is the default playable world; Graciosa is
preserved in `archive/graciosa/`. The current route is Whitehead Spit -> Fort Street.

**First Exit A — One Land Night** (milestone First Exit, north-star issues #24 / #42).

Один непрерывный 10–15-минутный playable loop в основной сцене Key West без телепортации между тестовыми сценами.

Thin ice и coastal geography вынесены в отдельный последующий slice **Coast / Thin Ice (B)**.

## 4. Success criteria верхнего уровня (First Exit A)

Milestone считается закрытым, когда:

- [ ] Новый игрок проходит bunker → shelter → sleep/save за ~10–15 минут без debug-телепортов и консольных костылей.
- [ ] Существуют три осмысленных **land**-пути: road / shore / ruins, которые отличаются по времени, холоду, весу и риску.
- [ ] Weather turn реально заставляет пересмотреть обратный маршрут или набор ресурсов.
- [ ] Shelter остаётся выбором (4 repairable windows + operable door, ограниченное количество boards), а не автоматическим safe room.
- [ ] Sleep/load восстанавливает согласованное состояние: shelter, fuel, weather, bedroll, inventory и consumed world pickups.
- [ ] README, `VERTICAL_SLICE.md` и `FIRST_EXIT.md` описывают один и тот же scope.
- [ ] Thin ice нигде не блокирует прохождение и не обещается как маршрут A.

## 5. Дорожная карта (Now / Next / Later)

| Эпик / Milestone                        | Статус | Роль |
|-----------------------------------------|--------|------|
| **First Exit A**                        | Основные действия реализованы; живой прогон не подтверждён | Now. Доказывает основной survival-loop. |
| **Diegetic Inventory + Player Hub**     | Физические предметы и Quick Access реализованы; проверка новым игроком впереди | Now/Next. Даёт физический доступ к предметам. |
| **Coast / Thin Ice (B)**                | 0%     | Next. Signature-выбор: короткий рискованный лёд vs длинный безопасный берег. |
| Survival Pressure Polish                | Later  | Route audio, readability, wetness feedback, publisher captures. |

Уточнение автора от 2026-09-28: в текущем кандидате остаются прежние запасы,
бонусные стопки и второй комплект у убежища (33 доски, 66 гвоздей, 12 поленьев).
Старт возвращён к бункеру. Прогон проверяет готовые действия и понятность пути;
баланс исторического дефицита 15 досок / 30 гвоздей этим прогоном не подтверждается.

## 6. Out of scope (для текущего рубежа First Exit A)

- Coastal thin-ice geography и вся presentation-цепочка льда
- Combat / enemies
- Активные способности Kenny
- Новые need-meters
- Heavy snow deformation
- Расширение острова за пределы First Exit route
- Новые самостоятельные менеджеры систем
- Полноценный HUD-редизайн
- Отдельные shader-эксперименты

## 7. Ограничения разработки

- Автор + два implementation-агента (Claude / Codex) + Grok (planning & audits only).
- `AGENTS.md` — единый свод правил по веткам и ролям.
- Ничего не попадает в `main` без автора.
- Координация агентов — в issue #1 (handoffs).
- CI: 29+ headless test suites, render pipeline.
- Data-driven layout (`first_exit_layout.json`) — source of truth для позиций.

## 8. Как этот документ связан с декомпозицией

```
PRD (этот документ)
 └─ Epic         = GitHub Milestone (+ опционально epic-issue)
	 └─ User Story = issue «Как игрок, я хочу…» + acceptance checklist
		 └─ Task     = дочерний issue / PR
			 └─ Subtask = пункт чек-листа Task (= один коммит/дифф + тест где возможно)
```

Подробные правила и шаблоны — в `CONTRIBUTING_DECOMPOSITION.md` и `.github/ISSUE_TEMPLATE/`.
