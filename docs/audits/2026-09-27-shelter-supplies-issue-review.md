# Issue reading record — shelter supplies, 2026-09-27

Before implementation, Codex read every issue body in Nolavel/Henry-s-Feral-Night,
including closed issues: 25 issues, 12 open and 13 closed. Pull requests were
excluded. Relevant discussion decisions were also reviewed. This is a dated
snapshot, not a replacement for the current GitHub issue tracker.

The human had integrated the previous shelter pass through PR #125. Work starts
from main `8a273ab`, merged into the Codex-owned `codex` branch before edits.

## Decisions applied

- #42/#24: retain First Exit A's land/night scenario, authored route and gradual
  shelter recovery. The author's current request explicitly adds test food/water
  and table salvage; it does not authorize an unrelated scope expansion.
- #68/#70–76: InventoryComponent owns loose items, EquipmentComponent owns
  physical pockets, and Hub presents those systems. Existing Use consumes items;
  F picks up world supplies or uses food presented on the seated meal table.
- #42 recovery discussion: sitting adds no magical recovery bonus. Food/water
  change the biomonitor, and the stove warms/dries Henry. Container fill states
  use catalog IDs rather than mutable per-instance resources or a new manager.
- #79: depleted containers and destroyed furniture survive saves using primitive
  data. Collected salvage follows the existing world-pickup ledger.
- #57/#56/#63: preserve dropped-flare physics, carried-log stove steps, staged
  boarding and bedroll actions from the previously merged pass.
- #80: automated component/input checks and local render captures do not replace
  a continuous human island playthrough or prove publisher readiness.
- #1 coordination text was read as project context; no external message or issue
  comment was posted.

## Complete issue inventory at the time of reading

| Issue | State | Title |
|---|---|---|
| [#1](https://github.com/Nolavel/Henry-s-Feral-Night/issues/1) | open | AI Talk — Codex ↔ Claude Code coordination |
| [#4](https://github.com/Nolavel/Henry-s-Feral-Night/issues/4) | open | Первый анализ от чатгпт |
| [#5](https://github.com/Nolavel/Henry-s-Feral-Night/issues/5) | closed | Root LICENSE is a third party's MIT — the game is formally open source by someone unconnected to it |
| [#6](https://github.com/Nolavel/Henry-s-Feral-Night/issues/6) | closed | The survival loop cannot close: sleeping restores nothing, food does not exist, interactions are dead |
| [#7](https://github.com/Nolavel/Henry-s-Feral-Night/issues/7) | open | Commercial readiness — scope control, risk matrix, playable vertical slice (Grok 2026-09-23) |
| [#16](https://github.com/Nolavel/Henry-s-Feral-Night/issues/16) | open | Snow / frost presentation — Gemini brief + Grok fact-check + path toward AAA (UE-plugin parity) |
| [#24](https://github.com/Nolavel/Henry-s-Feral-Night/issues/24) | closed | [P0] First Exit — грамматика, референс, направление |
| [#31](https://github.com/Nolavel/Henry-s-Feral-Night/issues/31) | closed | [Rendering] HFN Cold Ash LUT profiles and shelter switching hook |
| [#42](https://github.com/Nolavel/Henry-s-Feral-Night/issues/42) | open | First Exit |
| [#51](https://github.com/Nolavel/Henry-s-Feral-Night/issues/51) | open | Henry animation superstructure: jump, actions, crouch + Claude review |
| [#56](https://github.com/Nolavel/Henry-s-Feral-Night/issues/56) | closed | Claude slice: carry firewood, cabinet interaction, shelter work animations |
| [#57](https://github.com/Nolavel/Henry-s-Feral-Night/issues/57) | closed | Held flare: irregular light, sparks, smoke + Henry hand integration |
| [#58](https://github.com/Nolavel/Henry-s-Feral-Night/issues/58) | closed | Review Repo from Kimi |
| [#63](https://github.com/Nolavel/Henry-s-Feral-Night/issues/63) | closed | Bedroll item: sleep in the field through the same F — Sleep |
| [#68](https://github.com/Nolavel/Henry-s-Feral-Night/issues/68) | open | Diegetic Inventory & Player Hub |
| [#70](https://github.com/Nolavel/Henry-s-Feral-Night/issues/70) | closed | Инвентарь/Hub: фундамент владения предметами и физическими карманами |
| [#71](https://github.com/Nolavel/Henry-s-Feral-Night/issues/71) | closed | Инвентарь/Hub: состояние Player Hub и камера осмотра Генри |
| [#72](https://github.com/Nolavel/Henry-s-Feral-Night/issues/72) | closed | Инвентарь/Hub: рюкзак раскрывается на Генри как книга |
| [#73](https://github.com/Nolavel/Henry-s-Feral-Night/issues/73) | closed | Инвентарь/Hub: Quick Access через физические карманы и точки доступа |
| [#74](https://github.com/Nolavel/Henry-s-Feral-Night/issues/74) | open | Инвентарь/Hub: универсальное действие «Использовать» и удаление временных item-клавиш |
| [#75](https://github.com/Nolavel/Henry-s-Feral-Night/issues/75) | open | Инвентарь/Hub: снятие рюкзака и режим полной ревизии |
| [#76](https://github.com/Nolavel/Henry-s-Feral-Night/issues/76) | open | Инвентарь/Hub: аудит управления и финальная связка Quick Access / backpack / Hub |
| [#78](https://github.com/Nolavel/Henry-s-Feral-Night/issues/78) | open | First Exit A: authored weather turn that changes the return decision |
| [#79](https://github.com/Nolavel/Henry-s-Feral-Night/issues/79) | closed | First Exit A: save closure for consumed world pickups |
| [#80](https://github.com/Nolavel/Henry-s-Feral-Night/issues/80) | open | First Exit A: continuous stranger playtest and publisher-proof capture |
