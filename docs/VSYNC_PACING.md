# Ровность кадров с V-Sync (заметки, 2026-10-18)

Владелец: с «Без розривів кадру» кадры идут менее ровно, чем без него. Исследование — только чтение, ничего не менялось.

## Почему так (теория, не замер)
- С `displaySyncEnabled = YES` кадр держится на экране целое число тактов (120 Гц → 8,33 мс). FPS не делитель 120 (например, 90 с генерацией) → интервалы 8,3 и 16,7 мс вперемешку = рывки. Без V-Sync кадр выходит сразу (ровнее, но разрывы).
- Ограничитель Dormison (`sevo_limiter.c`, `SEVO_FPS_LIMIT`): ждёт `mach_wait_until` на CPU в `nextDrawable`, сетка от предыдущего срока, к тактам экрана не привязан. При лимите 60 и 120 Гц фаза сетки относительно такта плывёт → кадр иногда попадает на соседний такт (догадка, проверить по ленте показа).
- DXVK (`util_fps_limiter.cpp`) — то же самое: таймер на CPU, без vblank.
- MoltenVK (`MVKImage.mm`): present из scheduled handler, `presentAtTime:` при `VK_GOOGLE_display_timing`, `displaySyncEnabled` по present mode, `addPresentedHandler` для обратной связи.
- Apple WWDC21 10147: ровный показ — `presentDrawable:afterMinimumDuration:` (фикс. лимит или скользящее среднее времени GPU); на фиксированном экране — делитель частоты; на Adaptive-Sync (только внешние дисплеи, полноэкранный режим; про встроенный ProMotion MacBook ничего) — любой ровный темп.
- **D3DMetal 4.0b3 сам содержит `D3DM_MAX_FPS` и вызовы `presentDrawable:afterMinimumDuration:` / `presentAfterMinimumDuration:`** (strings). Что `D3DM_MAX_FPS` идёт через них — вероятно, не проверено.

## Что попробовать (по одному, замер — лента показа / разброс интервалов в журнале Reflex)
1. RE9: лимит 60 через `D3DM_MAX_FPS=60` против `SEVO_FPS_LIMIT=60`, V-Sync Lullaby вкл. Сравнить разброс интервалов показа и задержку.
2. Если ровнее — переключатель «Обмеження FPS» для D3DMetal отдавать в `D3DM_MAX_FPS`.
3. Привязать `sevo_limiter` к тактам (срок = ближайший такт по `presentedTime` / `CAMetalDisplayLink`) — для DXMT/DXVK.
4. Без лимита с V-Sync: `presentDrawable:afterMinimumDuration:` по скользящему среднему интервала кадра (как в WWDC21) — ровнее, цена — несколько мс задержки.
5. Проверить, есть ли переменная частота на встроенном экране: `NSScreen.minimumRefreshInterval != maximumRefreshInterval` в полноэкранном окне игры.
