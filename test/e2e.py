"""Сквозная проверка в настоящем браузере. Запуск: node test/e2e-server.js & python3 test/e2e.py"""
import json, sys, urllib.request
from playwright.sync_api import sync_playwright

BASE = "http://127.0.0.1:4173"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp"
fails = []

def check(name, cond, extra=""):
    print(("ok   " if cond else "FAIL ") + name + (f"  [{extra}]" if extra and not cond else ""))
    if not cond:
        fails.append(name)

def last():
    return json.load(urllib.request.urlopen(BASE + "/__last"))

with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 1280, "height": 800}, locale="ru-RU", permissions=["clipboard-read", "clipboard-write"])
    page = ctx.new_page()
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" and "fonts.googleapis" not in m.text and "ERR_" not in m.text and "Failed to load resource" not in m.text else None)
    page.route("**/fonts.googleapis.com/**", lambda r: r.abort())

    page.goto(BASE)
    page.wait_for_selector(".mode-word")
    page.wait_for_function("document.getElementById('modelName').textContent.includes('·')")
    check("пустой экран Chat, акцент розовый", page.inner_text(".mode-word") == "Chat")
    chat_accent = page.evaluate("getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()")
    page.screenshot(path=f"{OUT}/01-chat-empty.png")

    # --- Chat: стриминг + markdown
    page.click(".starter >> nth=0")
    page.wait_for_selector(".msg.assistant .code", timeout=8000)
    page.wait_for_function("!document.querySelector('.msg.streaming')", timeout=8000)
    check("ответ отрисован: код, список, таблица",
          page.locator(".msg.assistant .code").count() == 1 and page.locator(".msg.assistant li").count() == 2 and page.locator(".msg.assistant table").count() == 1)
    check("в запрос ушёл системный промт Chat", "собеседник" in last()["chat"]["messages"][0]["content"])
    check("модель Chat — Llama (подбор под режим)", "llama" in last()["chat"]["model"])
    page.click("[data-copy]")
    page.wait_for_function("document.querySelector('[data-copy]').textContent !== 'Копировать'", timeout=3000)
    check("кнопка копирования кода реагирует", page.inner_text("[data-copy]") == "Скопировано")
    check("в буфере именно код", "export const sum" in page.evaluate("navigator.clipboard.readText()"))
    check("чат появился в списке", page.locator(".chat-item").count() == 1)
    page.screenshot(path=f"{OUT}/02-chat-reply.png")

    # --- Code: акцент другой, автопереключение модели
    page.click(".mode[data-m=code]")
    code_accent = page.evaluate("getComputedStyle(document.documentElement).getPropertyValue('--accent').trim()")
    check("акцент меняется вместе с режимом", code_accent != chat_accent, f"{chat_accent} / {code_accent}")
    check("в Code пустой список чатов отдельный", page.locator(".chat-item").count() == 0)
    page.fill("#input", "Напиши функцию суммы")
    page.keyboard.press("Enter")
    page.wait_for_selector(".msg.assistant .note", timeout=10000)
    page.wait_for_function("!document.querySelector('.msg.streaming')", timeout=8000)
    check("при 429 переключилась на другую модель", "после сбоя" in page.inner_text(".msg.assistant .note"))
    check("ответ после переключения получен", page.locator(".msg.assistant .code").count() == 1)
    page.screenshot(path=f"{OUT}/03-code-fallback.png")

    # --- Настройки: тема, шрифт, промт
    page.click("#openSettings")
    page.wait_for_selector("#settingsDialog[open]")
    page.screenshot(path=f"{OUT}/04-settings-look.png")
    page.click(".swatch >> nth=1")
    check("тема переключилась на Лёд", page.evaluate("document.documentElement.dataset.theme") == "ice")
    page.click(".font-opt >> nth=1")
    check("шрифт применился", "Manrope" in page.evaluate("getComputedStyle(document.documentElement).getPropertyValue('--font')"))
    page.click("#settingsTabs .tab >> nth=1")
    page.fill("#settingsBody textarea >> nth=0", "Всегда отвечай пиратом ARRR")
    page.screenshot(path=f"{OUT}/05-settings-prompts.png")
    page.click("#settingsDialog [data-close]")
    page.fill("#input", "Привет")
    page.keyboard.press("Enter")
    page.wait_for_function("!document.querySelector('.msg.streaming')", timeout=10000)
    sys_prompt = last()["chat"]["messages"][0]["content"]
    check("свой промт попал в системное сообщение", "ARRR" in sys_prompt and "инженер" in sys_prompt)
    page.screenshot(path=f"{OUT}/06-ice-theme.png")

    # --- Коннекторы
    page.click("#openConnectors")
    page.fill("#connectorBody input[type=password]", "ghp_test")
    page.click("#connectorBody .btn.primary")
    page.wait_for_selector("#connectorBody .pick")
    page.screenshot(path=f"{OUT}/07-connectors-repos.png")
    page.click("#connectorBody .pick")
    page.wait_for_selector("#connectorBody .pick small:text('src/index.ts')")
    page.click("#connectorBody .pick:has-text('index.ts')")
    page.wait_for_selector("#chips .chip")
    check("файл из GitHub стал вложением", "index.ts" in page.inner_text("#chips"))
    page.click("#connectorTabs .tab >> nth=1")
    page.fill("#connectorBody input[type=password]", "vc_test")
    page.click("#connectorBody .btn.primary")
    page.click("#connectorBody .pick:has-text('my-site')")
    page.wait_for_selector("#connectorBody .pick:has-text('fix build')")
    page.screenshot(path=f"{OUT}/08-connectors-vercel.png")
    page.click("#connectorBody .pick:has-text('fix build')")
    page.wait_for_function("document.querySelectorAll('#chips .chip').length === 2")
    page.click("#connectorsDialog [data-close]")
    page.fill("#input", "Почему падает?")
    page.keyboard.press("Enter")
    page.wait_for_function("!document.querySelector('.msg.streaming')", timeout=10000)
    user_msg = [m for m in last()["chat"]["messages"] if m["role"] == "user"][-1]["content"]
    check("в запрос ушёл файл из GitHub", "secretMarker" in user_msg and '<file name="me/app/src/index.ts"' in user_msg)
    check("в запрос ушёл лог Vercel", "left-pad" in user_msg)
    check("вложения очищены после отправки", page.locator("#chips .chip").count() == 0)
    page.screenshot(path=f"{OUT}/09-code-with-context.png")

    # --- Сохранение после перезагрузки
    page.reload()
    page.wait_for_selector(".mode-word")
    check("тема сохранилась", page.evaluate("document.documentElement.dataset.theme") == "ice")
    check("режим сохранился", page.evaluate("document.documentElement.dataset.mode") == "code")
    check("чаты сохранились", page.locator(".chat-item").count() >= 1)
    page.click(".chat-open >> nth=0")
    check("чат открывается из истории", page.locator(".msg").count() >= 2)

    # --- Свой акцент
    page.click("#openSettings")
    page.click("#settingsDialog .pill >> nth=1")
    check("свой акцент включается", page.evaluate("document.documentElement.dataset.accent") == "custom")
    page.click("#settingsDialog [data-close]")

    # --- Телефон
    m = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, has_touch=True, is_mobile=True, locale="ru-RU")
    mp = m.new_page()
    mp.route("**/fonts.googleapis.com/**", lambda r: r.abort())
    mp.goto(BASE)
    mp.wait_for_selector(".mode-word")
    check("на телефоне меню скрыто", not mp.is_visible("#rail") or mp.evaluate("document.getElementById('rail').getBoundingClientRect().right <= 0"))
    mp.screenshot(path=f"{OUT}/10-mobile-empty.png")
    mp.click("#menuBtn")
    mp.wait_for_timeout(400)
    mp.screenshot(path=f"{OUT}/11-mobile-rail.png")
    check("меню на телефоне открывается", mp.evaluate("document.getElementById('rail').getBoundingClientRect().left >= 0"))
    m.close()

    check("в консоли нет ошибок", not errors, "; ".join(errors[:3]))
    b.close()

print()
print("ПРОВАЛЕНО: " + ", ".join(fails) if fails else "Все проверки в браузере прошли")
sys.exit(1 if fails else 0)
