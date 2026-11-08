# Развёртывание на VDS (Ubuntu 22.04/24.04)

1. Установите Docker: `curl -fsSL https://get.docker.com | sh`
2. Загрузите папку репозитория на сервер (`git clone https://github.com/XenoDEBUG/messenger-2026-ios`).
3. `cd messenger-2026-ios/deploy`, `cp .env.example .env`, заполните `.env`.
4. Запуск: `docker compose up -d --build`
5. Проверка: `curl http://ВАШ_IP:3000/health` должен вернуть `{"ok":true}`.

Данные Mongo лежат в томе `mongo-data` и не теряются при перезапуске.
Открыть порт 3000 в фаерволе: `ufw allow 3000`.

Обновление: `git pull && docker compose up -d --build`.

Подключиться к базе через MongoDB Compass: `mongodb://USER:PASSWORD@ВАШ_IP:27017/messenger?authSource=admin`.
Порт 27017 наружу не открыт, поэтому для Compass пробросьте его через SSH-туннель или откройте порт осознанно.
