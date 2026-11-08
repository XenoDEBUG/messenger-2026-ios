# Messenger 2026 — iOS

Сборка неподписанного `.ipa` делается в GitHub Actions (macOS-машина).

1. Вкладка **Actions** → **iOS unsigned IPA** → **Run workflow**.
2. Когда сборка зелёная, откройте запуск и скачайте артефакт `messenger-2026-unsigned-ipa` (внутри `App.ipa`).
3. Для установки на iPhone файл нужно подписать (например, Sideloadly со своим Apple ID).

Веб-страница: `www/index.html`.
