# Пульт

Бесплатный AI-агрегатор с тремя режимами (Code, Work, Chat), бесплатными моделями OpenRouter,
своими промтами, темами, шрифтами и коннекторами GitHub и Vercel.

Без сборки и зависимостей: статика в `public/` + функции Vercel в `api/`.

## Запуск локально
```
cp .env.example .env.local    # впиши OPENROUTER_API_KEY
node server.js                # http://localhost:3000
npm test                      # проверки API на моках
```

## Деплой на Vercel
1. Залей папку в GitHub-репозиторий и импортируй его в Vercel (Framework Preset: Other).
2. В Settings → Environment Variables добавь `OPENROUTER_API_KEY`.
3. Если сайт публичный, добавь ещё `ACCESS_CODE`, иначе любой сможет тратить твой лимит.

Без серверного ключа каждый вставляет свой ключ OpenRouter в Настройки → Доступ.
С серверным ключом разрешены только модели `:free`.

## Где что лежит
- `public/js/store.js` — режимы, промты по умолчанию, темы, шрифты, хранилище (localStorage)
- `public/js/connectors.js` — коннекторы; новый добавляется объектом в список `CONNECTORS`
- `public/js/settings.js` — вкладки настроек
- `api/chat.js` — стриминг в OpenRouter, `api/models.js` — список бесплатных моделей
- `api/github.js`, `api/vercel.js` — прокси к API (токены приходят из браузера в заголовках, на сервере не хранятся)

Чаты, настройки, ключи и токены живут только в браузере пользователя.
