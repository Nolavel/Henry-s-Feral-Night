<p align="center">
  <img src="icon.svg" width="160" alt="Hoarbound">
</p>

# Hoarbound

**Third-person systemic survival / Системный сурвайвал от третьего лица**

## EN

**Hoarbound** is a survival game set in a frozen **Key West**.  
Henry leaves a bunker with limited supplies and must turn an abandoned house into a place that can survive the night.

Cold, wind, wet clothing, carried weight, fuel and time are connected systems. The goal is not simply to make mechanics work — it is to make them **change the player's decisions**.

**Current milestone — First Exit**
- bunker → route choice → supplies → worsening weather;
- shelter repair → stove → recovery;
- sleep/save → coherent reload;
- one continuous 10–15 minute human playtest without debug workarounds.

## RU

**Hoarbound** — сурвайвал на замёрзшем **Key West**.  
Генри выходит из бункера с ограниченными запасами и должен превратить заброшенный дом в убежище, способное пережить ночь.

Холод, ветер, мокрая одежда, вес груза, топливо и время связаны между собой. Наша цель — не просто заставить механики работать, а сделать так, чтобы они **меняли решения игрока**.

**Текущая цель — First Exit**
- бункер → выбор маршрута → ресурсы → ухудшение погоды;
- ремонт убежища → печь → восстановление;
- сон/save → согласованная загрузка;
- один непрерывный 10–15-минутный плейтест без debug-костылей.

## Tech / Технологии

**Godot 4.8-dev6 .NET · Forward+ / Vulkan · PC**

Real-world NOAA/OSM data underpins the Key West terrain and city. Production work currently focuses on systemic survival, streamed winter environments, deformable snow and stylized rendering.

Main scene: `res://scenes/world/key_west/key_west.tscn`

See `PRD.md`, `docs/game_design/VERTICAL_SLICE.md`, `AGENTS.md` and `CHANGELOG.md`.

## Status / Статус

**Active development — vertical slice. / Активная разработка — vertical slice.**

Copyright © 2025–2026 Nolavel. All rights reserved. See `LICENSE`.
