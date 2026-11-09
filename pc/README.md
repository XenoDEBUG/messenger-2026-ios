# Messenger 2026 — ПК

Страница берётся из корневого `www/index.html` (та же, что в iOS-приложении).
Сборка делается автоматически в GitHub Actions (workflow «PC portable exe»):
при каждом push в `main` или запуске вручную.

Готовый `Messenger-2026.exe` скачивается из раздела Artifacts запуска
`messenger-2026-pc-portable`. Установка не нужна.

Локальный запуск (нужны Node.js 18+ и Windows):

1. `cp ../www/index.html www/index.html`
2. `npm install`
3. `npm start`

Звонки и микрофон работают, потому что страница открыта из файла, а не по http.
