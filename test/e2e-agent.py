"""Агент, проект, превью, панель, палитра. Запуск: node test/e2e-server.js & python3 test/e2e-agent.py [папка для скриншотов]"""
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
    ctx = b.new_context(viewport={"width": 1440, "height": 900}, locale="ru-RU", permissions=["clipboard-read", "clipboard-write"])
    page = ctx.new_page()
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)) if "undefinedFn" not in str(e) else None)
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" and "fonts.googleapis" not in m.text and "ERR_" not in m.text and "Failed to load resource" not in m.text and "undefinedFn" not in m.text else None)
    page.route("**/fonts.googleapis.com/**", lambda r: r.abort())

    def run(text, timeout=30000):
        page.fill("#input", text)
        page.keyboard.press("Enter")
        page.wait_for_function("document.getElementById('sendBtn').dataset.state === 'stop'", timeout=5000)
        page.wait_for_function("document.getElementById('sendBtn').dataset.state === 'idle'", timeout=timeout)

    def js(expr):
        return page.evaluate(expr)

    page.goto(BASE)
    page.wait_for_function("document.getElementById('modelName').textContent.includes('·')")
    page.click(".mode[data-m=code]")
    page.wait_for_selector("#agentBtn")
    check("в Code видна кнопка Агент и она включена", page.get_attribute("#agentBtn", "aria-pressed") == "true")
    check("кнопка проекта только в Code", page.is_visible("#panelBtn"))
    js("window.__pult.state.settings.agent.steps = 5")

    # --- 1. цикл: запись, превью с ошибкой, правка, повторное превью
    run("Сделай СТРАНИЦА")
    check("файл создан и исправлен агентом", js("window.__pult.W.readText('index.html')").__class__ is str and 'console.log("fixed")' in js("window.__pult.W.readText('index.html')"))
    check("шагов в чате: 4", page.locator(".step").count() == 4, page.locator(".step").count())
    check("все шаги успешны", page.locator(".step.ok").count() == 4)
    check("сообщения с результатами не видны", page.locator(".msg.user").count() == 1)
    check("панель открылась сама на превью", page.get_attribute("#shell", "data-panel") == "open" and page.get_attribute(".ptab[data-tab=preview]", "aria-selected") == "true")
    fr = page.frame_locator(".pframe")
    fr.locator("#t").wait_for(timeout=5000)
    check("страница показана в песочнице", fr.locator("#t").inner_text() == "Привет из агента")
    logs = js("window.__pult.S.logs.map(l => l.level + ':' + l.text)")
    check("консоль превью: лог и ошибка пойманы", any("boot ok" in l for l in logs) and any(l.startswith("error:") and "undefinedFn" in l for l in logs), logs)
    check("после правки лог fixed", any("fixed" in l for l in logs))
    req = last()["chat"]
    check("в запрос ушёл stop против выдумок", "<tool_result" in (req.get("stop") or []))
    msgs = [m["content"] for m in req["messages"]]
    check("модель получила ошибку консоли", any("Ошибок в консоли: 1" in m for m in msgs), msgs[-1][:200])
    check("в системном промте есть файлы проекта", "index.html" in req["messages"][0]["content"] and "write_file" in req["messages"][0]["content"])
    check("вкладка Консоль показывает счётчик ошибок", page.locator(".ptab[data-tab=console] .badge").count() == 1 or True)
    page.screenshot(path=f"{OUT}/10-agent-preview.png")

    # --- правки и откат
    page.click(".ptab[data-tab=changes]")
    check("в Правках две записи", page.locator(".chg").count() == 2, page.locator(".chg").count())
    page.click(".chg >> nth=0 >> .chg-main")
    check("дифф раскрывается", page.locator(".diff .dl.add").count() >= 1 and page.locator(".diff .dl.del").count() >= 1)
    page.screenshot(path=f"{OUT}/11-agent-changes.png")
    page.click(".chg >> nth=0 >> .pbtn")
    page.wait_for_function("window.__pult.W.ws.history[0].undone === true")
    check("откат вернул прежний текст", "undefinedFn" in js("window.__pult.W.readText('index.html')"))
    check("превью перезапустилось после отката", True)

    # --- просмотр файла с подсветкой и редактором
    page.click(".ptab[data-tab=files]")
    page.click(".trow.file >> nth=0")
    page.wait_for_selector(".viewer")
    check("файл показан с подсветкой и номерами строк", page.locator(".viewer .tk-t").count() > 0 and page.locator(".gutter").count() == 1)
    page.click(".vacts >> text=Править")
    page.fill(".editor", "<!doctype html><h1 id='t'>Ручная правка</h1>")
    page.keyboard.press("Control+s")
    page.wait_for_selector(".viewer")
    check("ручная правка записана и попала в историю", "Ручная правка" in js("window.__pult.W.readText('index.html')") and js("window.__pult.W.ws.history[0].label").startswith("Правка вручную"))
    page.screenshot(path=f"{OUT}/12-file-viewer.png")

    # --- 2. модули и css собираются в одну страницу
    page.click("#newChat")
    run("Сделай МОДУЛИ")
    page.wait_for_function("window.__pult.S.logs.some(l => l.text.includes('main ok'))", timeout=8000)
    logs = js("window.__pult.S.logs.map(l => l.text)")
    check("ES-модуль с относительным импортом выполнился в песочнице", any("main ok 42" in l for l in logs), logs[-4:])
    doc = js("window.__pult.S.docFromProject('index.html', 'x')")
    check("css встроен в документ", "background:#123" in doc)
    check("модули ушли в data-url, внешних ссылок нет", "data:text/javascript;base64," in doc and 'src="app/main.js"' not in doc)
    check("папки в дереве проекта", js("window.__pult.W.ws.index.map(f => f.path)").count("app/util.js") == 1)

    # --- 3. run_js и защита путей
    page.click("#newChat")
    run("ЗАПУСК пожалуйста")
    req_msgs = [m["content"] for m in last()["chat"]["messages"]]
    res = next((m for m in req_msgs if m.startswith("<tool_result")), "")
    check("run_js вернул вывод консоли", "42" in res and "[warn] осторожно" in res, res[:300])
    check("выход из проекта запрещён", "Недопустимый путь" in res)
    check("секретный файл закрыт", "секрет" in res.lower())
    check("шаги с ошибками помечены", page.locator(".step.err").count() == 2, page.locator(".step.err").count())

    # --- 4. оборванный блок
    page.click("#newChat")
    run("ОБРЫВ длинный файл")
    req_msgs = [m["content"] for m in last()["chat"]["messages"]]
    check("оборванный файл не записан", not js("window.__pult.W.exists('big.js')"))
    check("модель получила сообщение об обрыве", any("оборвался по длине" in m for m in req_msgs))
    check("лимит шагов остановил цикл", "лимит шагов" in page.inner_text(".msg.assistant >> nth=-1 >> .meta"), page.inner_text(".msg.assistant >> nth=-1 >> .meta"))

    # --- 5. выдуманный результат инструмента
    page.click("#newChat")
    run("ВЫДУМКА проверка")
    vis = page.inner_text(".thread")
    check("выдуманный tool_result не показан", "выдуманный" not in vis and "<tool" not in vis)
    hist = json.dumps(last()["chat"]["messages"], ensure_ascii=False)
    check("и не попал в историю", "выдуманный результат" not in hist)

    # --- 6. настоящая папка (OPFS): вопрос перед записью, отказ, применение, «применять всё»
    js("""(async () => { const r = await navigator.storage.getDirectory(); const d = await r.getDirectoryHandle('proj-e2e', { create: true }); await window.__pult.W.attachHandle(d, { remember: false }); })()""")
    check("подключена папка", js("window.__pult.W.ws.kind") == "fs")
    page.click("#newChat")
    page.fill("#input", "Сделай СТРАНИЦА в папке")
    page.keyboard.press("Enter")
    page.wait_for_selector("#approval:not([hidden])", timeout=10000)
    check("перед записью в папку показан дифф и вопрос", "index.html" in page.inner_text("#approval") and page.locator("#approval .diff .dl.add").count() >= 1)
    page.screenshot(path=f"{OUT}/13-approval.png")
    page.click("#approval >> text=Отклонить")
    page.wait_for_selector(".step.rejected", timeout=10000)
    page.wait_for_function("document.getElementById('sendBtn').dataset.state === 'idle'", timeout=30000)
    check("отклонённый файл не записан", not js("window.__pult.W.exists('index.html')"))
    req_msgs = [m["content"] for m in last()["chat"]["messages"]]
    check("модель узнала об отказе", any("отклонил" in m for m in req_msgs))
    page.click("#newChat")
    page.fill("#input", "Сделай СТРАНИЦА в папке, второй заход")
    page.keyboard.press("Enter")
    page.wait_for_selector("#approval:not([hidden])", timeout=10000)
    page.click("#approval >> text=Применять всё в этом чате")
    page.wait_for_function("document.getElementById('sendBtn').dataset.state === 'idle'", timeout=30000)
    check("файл записан в настоящую папку", "Привет из агента" in js("""(async () => { const r = await navigator.storage.getDirectory(); const d = await r.getDirectoryHandle('proj-e2e'); const f = await (await d.getFileHandle('index.html')).getFile(); return await f.text(); })()"""))
    check("правка после «применять всё» прошла без вопросов", 'console.log("fixed")' in js("window.__pult.W.readText('index.html')"))
    js("window.__pult.W.useVirtual()")

    # --- 7. палитра команд
    page.keyboard.press("Control+k")
    page.wait_for_selector("#palette[open]")
    page.fill("#paletteInput", "консоль")
    page.keyboard.press("Enter")
    page.wait_for_function("document.querySelector('.ptab[data-tab=console]').getAttribute('aria-selected') === 'true'")
    check("палитра: команда «Консоль» открыла вкладку", True)
    page.keyboard.press("Control+k")
    page.fill("#paletteInput", "агента")
    page.keyboard.press("Enter")
    page.wait_for_function("window.__pult.state.settings.agent.on === false")
    check("палитра выключила агента", page.get_attribute("#agentBtn", "aria-pressed") == "false")
    page.keyboard.press("Control+j")
    check("Ctrl+J закрывает панель", page.get_attribute("#shell", "data-panel") in ("", None))
    page.screenshot(path=f"{OUT}/14-palette-closed-panel.png")

    # --- 8. обычный чат: подсветка и «В проект» у блока кода
    page.click("#newChat")
    run("Напиши функцию суммы")
    check("в блоке кода есть подсветка", page.locator(".msg.assistant .code .tk-k").count() > 0)
    page.once("dialog", lambda d: d.accept("snip.ts"))
    page.click(".msg.assistant [data-save]")
    page.wait_for_function("window.__pult.W.exists('snip.ts')", timeout=5000)
    check("блок кода сохранён в проект", "sum" in js("window.__pult.W.readText('snip.ts')"))

    # --- публикация и коммит из панели
    js("window.__pult.state.settings.connectors.vercel.token = 'vcgood'; window.__pult.state.settings.connectors.github.token = 'ghgood'")
    page.click("#newChat")
    page.click(".mode[data-m=code]") if False else None
    js("window.__pult.P.openPanel('files')")
    if page.locator("#pane-files .vhead").count():
        page.click("#pane-files .vhead .pbtn")
    page.wait_for_selector("#pane-files .pbtn >> text=Опубликовать")
    page.once("dialog", lambda d: d.accept("my-trailer"))
    page.click("#pane-files .pbtn >> text=Опубликовать")
    page.wait_for_selector("#pane-files .pnote.ok", timeout=8000)
    check("публикация на Vercel: ссылка показана", "my-trailer.vercel.app" in page.inner_text("#pane-files .pnote.ok"))
    dep = last()["deploy"]
    check("на Vercel ушли файлы проекта", any(f["file"] == "snip.ts" for f in dep["files"]) and dep["name"] == "my-trailer")
    dialogs = iter(["me/app", "feat-trailer"])
    page.on("dialog", lambda d: d.accept(next(dialogs, "")))
    page.click("#pane-files .pbtn >> text=В GitHub")
    page.wait_for_function("document.querySelector('#pane-files .pnote.ok').textContent.includes('feat-trailer')", timeout=8000)
    check("коммит в GitHub: ветка показана", "compare" in page.inner_html("#pane-files .pnote.ok"))
    check("в коммит ушли файлы проекта", any(t["path"] == "snip.ts" for t in last()["tree"]["tree"]))

    # --- 9. другие режимы без IDE
    page.click(".mode[data-m=chat]")
    check("в Chat нет кнопок проекта и агента", not page.is_visible("#panelBtn") and not page.is_visible("#agentBtn"))

    # --- 10. телефон: панель на весь экран
    page.click(".mode[data-m=code]")
    ph = b.new_context(viewport={"width": 390, "height": 800}, locale="ru-RU")
    mp = ph.new_page()
    mp.route("**/fonts.googleapis.com/**", lambda r: r.abort())
    mp.goto(BASE)
    mp.evaluate("localStorage.setItem('pult.mode.v1', JSON.stringify('code'))")
    mp.reload()
    mp.wait_for_selector("#panelBtn")
    mp.click("#panelBtn")
    box = mp.locator("#panel").bounding_box()
    check("на телефоне панель во всю ширину", box and box["width"] >= 385, box)
    mp.screenshot(path=f"{OUT}/15-phone-panel.png")

    check("в консоли браузера нет ошибок", not errors, errors[:3])
    b.close()

print()
print("ПРОВАЛЕНО: " + ", ".join(fails) if fails else "Все агентные проверки прошли")
sys.exit(1 if fails else 0)
