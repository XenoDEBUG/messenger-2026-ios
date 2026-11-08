# Развёртывание на VDS (Ubuntu 22.04 или 24.04)

## 1. Подключиться к VDS с компьютера
Windows: откройте PowerShell и выполните `ssh root@ВАШ_IP`, введите пароль из письма хостера.
Либо программа PuTTY. При первом входе подтвердите ключ (`yes`).

## 2. Установить Docker
```
curl -fsSL https://get.docker.com | sh
```

## 3. Скачать сервер
```
git clone https://github.com/XenoDEBUG/messenger-2026-ios
cd messenger-2026-ios/deploy
```

## 4. Настроить пароли
```
cp .env.example .env
nano .env
```
Заполните `MONGO_PASSWORD` и `JWT_SECRET` (длинные случайные строки). Сохраните: Ctrl+O, Enter, Ctrl+X.

## 5. Запустить
```
docker compose up -d --build
```
Проверка с VDS: `curl http://localhost:3000/health` должен вернуть `{"ok":true}`.
Снаружи: откройте в браузере `http://ВАШ_IP:3000/health`. Для этого откройте порт:
`ufw allow 3000 && ufw allow OpenSSH && ufw enable`

## 6. Подключить базу в MongoDB Compass (с компьютера)
Сначала откройте туннель в отдельном окне PowerShell и оставьте его открытым:
```
ssh -L 27017:127.0.0.1:27017 root@ВАШ_IP
```
В Compass создайте подключение:
```
mongodb://ПОЛЬЗОВАТЕЛЬ:ПАРОЛЬ@localhost:27017/messenger?authSource=admin
```
Где ПОЛЬЗОВАТЕЛЬ и ПАРОЛЬ — значения `MONGO_USER` и `MONGO_PASSWORD` из `.env`. База открыта только через туннель, наружу порт 27017 не выведен.

## Обновление
```
cd messenger-2026-ios/deploy && git pull && docker compose up -d --build
```

## Данные
Данные Mongo хранятся в томе `mongo-data` и остаются при перезапуске и обновлении.
