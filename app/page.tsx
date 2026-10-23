"use client";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowDownToLine,
  ArrowUpRight,
  Check,
  ChevronDown,
  Copy,
  Fingerprint,
  Globe2,
  Search,
  Shield,
  ShieldCheck,
  RefreshCw,
  Radio,
  Monitor,
  Cpu,
  Clock3,
  HardDrive,
  Network,
  ScanLine,
  Info,
  X,
  Zap,
} from "lucide-react";
import type { Field, Section, Whoami } from "@/lib/types";
import { collectors } from "@/collectors";
import { speed } from "@/collectors/speed";
import { dns } from "@/collectors/dns";
import { combinedFingerprint, getValue, privacyReport } from "@/lib/privacy";
import { timeout } from "@/collectors/utils";
const icons: Record<string, typeof Globe2> = {
  network: Globe2,
  browser: Monitor,
  screen: ScanLine,
  locale: Clock3,
  gpu: Cpu,
  fingerprint: Fingerprint,
  webrtc: Radio,
  device: HardDrive,
  behavior: Shield,
  speed: Zap,
  dns: Network,
};
const emptySections = (): Section[] =>
  collectors.map((c) => ({
    id: c.id,
    title: c.title,
    description: c.description,
    fields: [],
    state: "loading",
  }));
function stringify(v: unknown) {
  return typeof v === "string" ? v : JSON.stringify(v, null, 2);
}
function FieldRow({ field: f }: { field: Field }) {
  const complex = typeof f.value === "object" && f.value !== null;
  return (
    <div className="data-row">
      <div className="data-label">
        <span
          className={`risk-dot ${f.risk}`}
          title={`${f.risk.toUpperCase()} · ${f.note}`}
          aria-label={`${f.risk}: ${f.note}`}
          tabIndex={0}
        />
        <span>{f.label}</span>
        <span className="field-help" tabIndex={0}>
          <Info size={12} />
          <span role="tooltip">{f.note}</span>
        </span>
      </div>
      <div className={`data-value ${f.status !== "ok" ? "muted-value" : ""}`}>
        {f.status === "unsupported" ? (
          <span>Не поддерживается</span>
        ) : f.status === "error" ? (
          <span title={String(f.value)}>
            Недоступно <small>· {String(f.value)}</small>
          </span>
        ) : complex ? (
          <details className="json-detail">
            <summary>
              {Array.isArray(f.value)
                ? `${f.value.length} элементов`
                : `${Object.keys(f.value!).length} параметров`}
              <ChevronDown size={13} />
            </summary>
            <pre>{stringify(f.value)}</pre>
          </details>
        ) : (
          <span>
            {f.value === true ? (
              <span className="bool-yes">true</span>
            ) : f.value === false ? (
              "false"
            ) : (
              String(f.value ?? "Неизвестно")
            )}
          </span>
        )}
      </div>
    </div>
  );
}
function DataSection({
  section: s,
  query,
  risk,
}: {
  section: Section;
  query: string;
  risk: string;
}) {
  const [expanded, setExpanded] = useState(false);
  const fields = s.fields.filter(
    (f) =>
      (risk === "all" || f.risk === risk) &&
      (!query ||
        `${f.label} ${f.key} ${stringify(f.value)} ${f.note}`
          .toLowerCase()
          .includes(query.toLowerCase())),
  );
  const searching = !!query || risk !== "all";
  const Icon = icons[s.id] || Globe2;
  if (s.state === "done" && !fields.length && searching) return null;
  return (
    <details className="section-card" id={s.id} open={searching || undefined}>
      <summary>
        <div className="section-icon">
          <Icon size={19} />
        </div>
        <div className="section-heading">
          <h3>{s.title}</h3>
          <p>{s.description}</p>
        </div>
        <span className="section-count">
          {s.state === "loading" ? (
            <span className="spinner" />
          ) : (
            String(fields.length).padStart(2, "0")
          )}
        </span>
        <ChevronDown className="section-chevron" size={16} />
      </summary>
      <div className="section-body">
        {s.state === "loading" ? (
          <div className="skeleton-lines">
            <i />
            <i />
            <i />
          </div>
        ) : (
          <>
            {(expanded || searching ? fields : fields.slice(0, 8)).map((f) => (
              <FieldRow key={f.key} field={f} />
            ))}
            {fields.length > 8 && !searching && (
              <button
                className="show-more"
                onClick={() => setExpanded(!expanded)}
              >
                {expanded
                  ? "Свернуть параметры"
                  : `Показать все ${fields.length} параметров`}
                <ChevronDown size={14} />
              </button>
            )}
            {!fields.length && <p className="empty">Нет доступных данных</p>}
          </>
        )}
      </div>
    </details>
  );
}
export default function Home() {
  const [sections, setSections] = useState<Section[]>(emptySections);
  const [fingerprint, setFingerprint] = useState("");
  const [query, setQuery] = useState("");
  const [risk, setRisk] = useState("all");
  const [toast, setToast] = useState("");
  const [scannedAt, setScannedAt] = useState("");
  const [scanning, setScanning] = useState(true);
  const [showAbout, setShowAbout] = useState(false);
  const [activeExtra, setActiveExtra] = useState<string | null>(null);
  const controller = useRef<AbortController | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const extraLock = useRef(false);
  const notify = useCallback((message: string) => {
    setToast(message);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(""), 3500);
  }, []);
  const scan = useCallback(async () => {
    controller.current?.abort();
    const abort = new AbortController();
    controller.current = abort;
    extraLock.current = false;
    setActiveExtra(null);
    setSections(emptySections());
    setFingerprint("");
    setScanning(true);
    setScannedAt("");
    const results: Section[] = [];
    await Promise.all(
      collectors.map(async (c) => {
        let fields: Field[];
        try {
          fields = await timeout(c.run(abort.signal), 12000);
        } catch (e) {
          fields = [
            {
              key: `${c.id}.error`,
              label: "Collector status",
              value: e instanceof Error ? e.message : "Не поддерживается",
              risk: "low",
              note: "Сбор данных не завершился.",
              status: "error",
            },
          ];
        }
        if (abort.signal.aborted) return;
        const section: Section = {
          id: c.id,
          title: c.title,
          description: c.description,
          fields,
          state: "done",
        };
        results.push(section);
        setSections((prev) => prev.map((s) => (s.id === c.id ? section : s)));
      }),
    );
    if (abort.signal.aborted) return;
    try {
      const fp = await combinedFingerprint(results);
      if (!abort.signal.aborted) setFingerprint(fp);
    } catch {
      if (!abort.signal.aborted) setFingerprint("SHA-256 недоступен");
    }
    if (!abort.signal.aborted) {
      setScanning(false);
      setScannedAt(
        new Date().toLocaleTimeString("ru-RU", {
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit",
        }),
      );
    }
  }, []);
  useEffect(() => {
    void scan();
    const shortcut = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement;
      if (
        event.key === "/" &&
        !["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName) &&
        !target.isContentEditable
      ) {
        event.preventDefault();
        document.querySelector<HTMLInputElement>(".search input")?.focus();
      }
    };
    window.addEventListener("keydown", shortcut);
    return () => {
      window.removeEventListener("keydown", shortcut);
      controller.current?.abort();
      if (toastTimer.current) clearTimeout(toastTimer.current);
    };
  }, [scan]);
  const report = useMemo(() => privacyReport(sections), [sections]);
  const http = getValue<Whoami>(sections, "http");
  const geo = http?.geo;
  const enrichment = http?.enrichment;
  const connection = enrichment?.connection as
    { isp?: string; org?: string; asn?: number } | undefined;
  const ua = getValue<string>(sections, "userAgent");
  const browserName = ua
    ? /Edg\//.test(ua)
      ? "Microsoft Edge"
      : /Firefox\//.test(ua)
        ? "Firefox"
        : /Chrome\//.test(ua)
          ? "Chrome"
          : /Safari\//.test(ua)
            ? "Safari"
            : "Browser"
    : "Определяем…";
  const platform = getValue<string>(sections, "platform");
  const completed = sections.filter((s) => s.state === "done").length;
  const totalFields = sections.reduce((n, s) => n + s.fields.length, 0);
  const highFields = sections
    .flatMap((s) => s.fields)
    .filter((f) => f.risk === "high" && f.status === "ok").length;
  const location = [
    geo?.city || enrichment?.city,
    geo?.country || enrichment?.country_code,
  ]
    .filter(Boolean)
    .join(", ");
  const reportExport = () =>
    JSON.stringify(
      {
        schemaVersion: 1,
        generatedAt: new Date().toISOString(),
        fingerprint,
        privacyReport: report,
        sections,
        notice:
          "Contains sensitive IP, headers and fingerprint data. Review before sharing. No application server persistence.",
      },
      null,
      2,
    );
  async function copy() {
    try {
      await navigator.clipboard.writeText(reportExport());
      notify("Отчёт скопирован как JSON");
    } catch {
      notify("Буфер обмена недоступен. Используйте скачивание JSON.");
    }
  }
  function download() {
    try {
      const url = URL.createObjectURL(
        new Blob([reportExport()], { type: "application/json" }),
      );
      const a = document.createElement("a");
      a.href = url;
      a.download = `privacy-report-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      notify("JSON подготовлен к скачиванию");
    } catch {
      notify("Не удалось скачать JSON");
    }
  }
  async function runExtra(id: "speed" | "dns") {
    if (extraLock.current || scanning) return;
    extraLock.current = true;
    setActiveExtra(id);
    const abort = controller.current!;
    const section: Section = {
      id,
      title: id === "speed" ? "Connection benchmark" : "DNS resolver test",
      description:
        id === "speed"
          ? "Приблизительная скорость и HTTP-задержка"
          : "Авторитетная проверка рекурсивных резолверов",
      fields: [],
      state: "loading",
    };
    setSections((prev) => [...prev.filter((s) => s.id !== id), section]);
    try {
      const fields = await (id === "speed" ? speed : dns)(abort.signal);
      if (!abort.signal.aborted)
        setSections((prev) =>
          prev.map((s) => (s.id === id ? { ...s, fields, state: "done" } : s)),
        );
    } catch (e) {
      if (!abort.signal.aborted)
        setSections((prev) =>
          prev.map((s) =>
            s.id === id
              ? {
                  ...s,
                  state: "done",
                  fields: [
                    {
                      key: id,
                      label: "Test status",
                      value: e instanceof Error ? e.message : "Недоступно",
                      risk: "low",
                      status: "error",
                      note: "Проверка не завершилась.",
                    },
                  ],
                }
              : s,
          ),
        );
    } finally {
      if (!abort.signal.aborted) {
        setActiveExtra(null);
        extraLock.current = false;
        requestAnimationFrame(() => {
          const result = document.getElementById(
            id,
          ) as HTMLDetailsElement | null;
          if (result) {
            result.open = true;
            result.scrollIntoView({
              block: "start",
              behavior: matchMedia("(prefers-reduced-motion: reduce)").matches
                ? "instant"
                : "smooth",
            });
          }
        });
      }
    }
  }
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <a className="brand" href="#">
          <span className="brand-icon">
            <Fingerprint size={25} />
          </span>
          <span>
            trace<span className="brand-period">.</span>
          </span>
          <span className="beta">BETA</span>
        </a>
        <div className="sidebar-caption">YOUR DIGITAL FOOTPRINT</div>
        <nav>
          <a className="nav-active" href="#overview">
            <ScanLine size={17} />
            Overview
            <span className="nav-dot" />
          </a>
          <a href="#privacy">
            <Shield size={17} />
            Privacy report
            <span className="nav-number">{report.findings.length}</span>
          </a>
          <a href="#signals">
            <Fingerprint size={17} />
            Browser signals
            <span className="nav-number">{totalFields || "—"}</span>
          </a>
          <a href="#diagnostics">
            <Network size={17} />
            Network tests
            <ArrowUpRight size={13} />
          </a>
        </nav>
        <div className="sidebar-bottom">
          <div className="local-badge">
            <span className="live-dot" />
            LOCAL-FIRST INSPECTION
          </div>
          <p>
            Ваши данные остаются
            <br />в этой вкладке.
          </p>
          <button onClick={() => setShowAbout(!showAbout)}>
            <Info size={14} />
            Как это работает
            <ArrowUpRight size={12} />
          </button>
          <div className="sidebar-version">
            NO ACCOUNTS. NO ANALYTICS.
            <br />
            v1.0 / open inspection
          </div>
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <div className="breadcrumb">
            Workspace <span>/</span> <strong>Privacy inspector</strong>
          </div>
          <div className="topbar-right">
            <span className="secure-label">
              <ShieldCheck size={14} />
              Без регистрации
            </span>
            <a
              href="https://github.com/topics/browser-fingerprinting"
              target="_blank"
              rel="noreferrer"
              className="learn-link"
            >
              О fingerprinting <ArrowUpRight size={13} />
            </a>
          </div>
        </header>
        <main id="overview">
          <div className="page-eyebrow">
            <span className="live-dot" /> A LITTLE LESS INVISIBLE THAN YOU THINK
          </div>
          <div className="page-title-row">
            <div>
              <h1>
                What do websites
                <br className="mobile-break" /> know about me<span>?</span>
              </h1>
              <p className="intro">
                Один визит. Без разрешений. Вот что ваш браузер уже рассказал.
              </p>
            </div>
            <button
              className="button rescan"
              onClick={() => void scan()}
              disabled={scanning}
            >
              <RefreshCw size={15} className={scanning ? "rotate" : ""} />
              {scanning ? "Сканирование…" : "Пересканировать"}
            </button>
          </div>
          <div className="scan-status">
            <span
              className={`status-indicator ${scanning ? "scanning" : ""}`}
            />
            <span>
              {scanning
                ? "Собираем сигналы браузера"
                : "Сканирование завершено"}
            </span>
            <span className="status-divider">/</span>
            <span className="mono">
              {completed}/{sections.length} collectors
            </span>
            <span className="scan-time">
              {scannedAt
                ? `Обновлено в ${scannedAt}`
                : "Каждый блок появляется по готовности"}
            </span>
          </div>
          <div className="scan-progress">
            <div style={{ width: `${(completed / sections.length) * 100}%` }} />
          </div>
          <section className="hero-grid" aria-label="Overview">
            <div className="identity-card">
              <div className="card-label">
                <Globe2 size={15} /> YOUR PUBLIC IDENTITY{" "}
                <span className="visible-tag">VISIBLE TO WEBSITES</span>
              </div>
              <div className={`public-ip mono ${!http ? "loading-text" : ""}`}>
                {http?.ip || (scanning ? "Discovering…" : "IP недоступен")}
                <span className="ip-version">{http?.ipVersion || "IP"}</span>
              </div>
              <div className="ip-location">
                <span className="country-indicator">◎</span>
                {location ||
                  (scanning
                    ? "Определяем местоположение"
                    : "Геолокация недоступна")}
                <span className="approx">приблизительно</span>
              </div>
              <div className="identity-meta">
                <div>
                  <span>INTERNET PROVIDER</span>
                  <strong>{connection?.isp || "Не определён"}</strong>
                  <small>
                    {connection?.asn
                      ? `AS${connection.asn}`
                      : "ASN unavailable"}
                  </small>
                </div>
                <div>
                  <span>BROWSER / PLATFORM</span>
                  <strong>{browserName}</strong>
                  <small>{platform || "—"}</small>
                </div>
              </div>
              <div className="fingerprint-line">
                <Fingerprint size={25} />
                <div>
                  <span>
                    YOUR BROWSER FINGERPRINT <small>SHA-256</small>
                  </span>
                  <code title={fingerprint}>
                    {fingerprint || "Вычисляем отпечаток…"}
                  </code>
                </div>
                <button
                  title="Скопировать fingerprint"
                  aria-label="Скопировать fingerprint"
                  disabled={!fingerprint}
                  onClick={async () => {
                    try {
                      await navigator.clipboard.writeText(fingerprint);
                      notify("Fingerprint скопирован");
                    } catch {
                      notify("Буфер обмена недоступен");
                    }
                  }}
                >
                  <Copy size={15} />
                </button>
              </div>
            </div>
            <div className="score-card">
              <div className="card-label">
                <Shield size={15} /> PRIVACY SCORE{" "}
                <span
                  className="score-info"
                  title="Эвристическая оценка наблюдаемых сигналов; неизвестные проверки не считаются пройденными."
                >
                  <Info size={14} />
                </span>
              </div>
              <div className="score-content">
                <div
                  className="score-ring"
                  style={
                    {
                      "--score": `${(report.score ?? 0) * 3.6}deg`,
                    } as React.CSSProperties
                  }
                >
                  <div>
                    <strong>{report.score ?? "—"}</strong>
                    <span>/ 100</span>
                  </div>
                </div>
                <div className="score-text">
                  <span className="amber-chip">
                    {scanning
                      ? "Собираем картину"
                      : report.score !== null && report.score >= 85
                        ? "Меньше видимых сигналов"
                        : "Есть что проверить"}
                  </span>
                  <h2>
                    Как много вы
                    <br />
                    оставляете за собой?
                  </h2>
                  <p>
                    Оценка сигналов, а не гарантия
                    <br />
                    анонимности.
                  </p>
                </div>
              </div>
              <div className="score-footer">
                <span>
                  Проверок с результатом <b>{report.coverage}</b>
                </span>
                <span className="mono">HEURISTIC</span>
              </div>
            </div>
          </section>
          <div className="trust-strip">
            <ShieldCheck size={15} />
            <span>Без трекеров и хранения отчётов</span>
            <i />
            <span>Без запросов разрешений</span>
            <i />
            <button onClick={() => setShowAbout(!showAbout)}>
              Внешние проверки и ограничения <ChevronDown size={13} />
            </button>
          </div>
          {showAbout && (
            <div className="about-box">
              <button
                aria-label="Закрыть пояснение"
                onClick={() => setShowAbout(false)}
              >
                <X size={16} />
              </button>
              <h3>Что происходит в этой вкладке</h3>
              <p>
                Браузерные сигналы и отпечаток обрабатываются локально. Сервер
                возвращает IP и заголовки и отправляет IP в ipwho.is для
                обогащения. Браузер обращается к api.ipify.org, api6.ipify.org и
                Google STUN. Эти провайдеры и Vercel видят соединения и могут
                вести собственные технические журналы. Приложение не пишет логи,
                cookies, localStorage или базу данных.
              </p>
              <p>
                Статусы разрешений только читаются. Уникальность отпечатка,
                инкогнито, Tor и VPN нельзя надёжно доказать этими сигналами.
                JSON содержит ваш IP, заголовки и отпечаток — проверьте его
                перед передачей другим людям.
              </p>
            </div>
          )}
          <section id="privacy" className="privacy-section">
            <div className="section-title">
              <div>
                <span className="section-kicker">01 / THE BIG PICTURE</span>
                <h2>
                  Privacy report <span className="subtle-badge">LIVE</span>
                </h2>
              </div>
              <div className="legend">
                <span>
                  <i className="green" />
                  Норма
                </span>
                <span>
                  <i className="yellow" />
                  Проверить
                </span>
                <span>
                  <i className="red" />
                  Риск
                </span>
                <span>
                  <i className="unknown" />
                  Неизвестно
                </span>
              </div>
            </div>
            <div className="findings-grid">
              {report.findings.map((f) => (
                <article key={f.id} className="finding">
                  <div className="finding-top">
                    <span className={`finding-icon ${f.level}`}>
                      {f.level === "green" ? (
                        <Check size={14} />
                      ) : f.level === "unknown" ? (
                        <span>?</span>
                      ) : (
                        <span>!</span>
                      )}
                    </span>
                    <h3>{f.title}</h3>
                    <span className={`finding-level ${f.level}`}>
                      {f.level === "green"
                        ? "OK"
                        : f.level === "red"
                          ? "EXPOSED"
                          : f.level === "yellow"
                            ? "REVIEW"
                            : "UNKNOWN"}
                    </span>
                  </div>
                  <p>{f.detail}</p>
                </article>
              ))}
            </div>
            <details className="recommendations">
              <summary>
                <span className="recommendation-icon">
                  <ShieldCheck size={17} />
                </span>
                <strong>Следующие шаги</strong>
                <span>
                  {report.recommendations.length} рекомендаций для вашей
                  конфигурации
                </span>
                <ChevronDown size={15} />
              </summary>
              <ol>
                {report.recommendations.map((r) => (
                  <li key={r}>{r}</li>
                ))}
              </ol>
            </details>
          </section>
          <section id="signals" className="signals-section">
            <div className="section-title">
              <div>
                <span className="section-kicker">02 / UNDER THE HOOD</span>
                <h2>Everything your browser reveals</h2>
                <p>Откройте категорию и изучите каждый сигнал.</p>
              </div>
              <div className="signal-total">
                <strong>{totalFields}</strong>
                <span>
                  параметров
                  <br />
                  <b>{highFields} high exposure</b>
                </span>
              </div>
            </div>
            <div className="toolbar">
              <label className="search">
                <Search size={17} />
                <input
                  aria-label="Поиск параметров"
                  placeholder="Поиск по IP, шрифтам, заголовкам…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
                {query && (
                  <button
                    aria-label="Очистить поиск"
                    onClick={() => setQuery("")}
                  >
                    <X size={14} />
                  </button>
                )}
                <kbd>/</kbd>
              </label>
              <select
                aria-label="Фильтр уровня риска"
                value={risk}
                onChange={(e) => setRisk(e.target.value)}
              >
                <option value="all">Все уровни</option>
                <option value="high">High exposure</option>
                <option value="medium">Medium exposure</option>
                <option value="low">Low exposure</option>
              </select>
              <div className="export-buttons">
                <button
                  title="Скопировать всё как JSON"
                  onClick={() => void copy()}
                >
                  <Copy size={15} />
                  <span>Copy JSON</span>
                </button>
                <button title="Скачать JSON" onClick={download}>
                  <ArrowDownToLine size={15} />
                  <span>Export</span>
                </button>
              </div>
            </div>
            <div className="data-sections">
              {sections.map((s) => (
                <DataSection key={s.id} section={s} query={query} risk={risk} />
              ))}
              {(query || risk !== "all") &&
                sections.every(
                  (s) =>
                    !s.fields.some(
                      (f) =>
                        (risk === "all" || f.risk === risk) &&
                        `${f.label} ${f.key} ${stringify(f.value)} ${f.note}`
                          .toLowerCase()
                          .includes(query.toLowerCase()),
                    ),
                ) && (
                  <div className="no-results">
                    <Search size={24} />
                    <h3>Ничего не найдено</h3>
                    <p>Измените запрос или уровень риска.</p>
                    <button
                      className="button"
                      onClick={() => {
                        setQuery("");
                        setRisk("all");
                      }}
                    >
                      Сбросить фильтры
                    </button>
                  </div>
                )}
            </div>
            <div className="exposure-legend">
              <span>EXPOSURE LEVEL</span>
              <b>
                <i className="risk-dot low" />
                Low
              </b>
              <b>
                <i className="risk-dot medium" />
                Medium
              </b>
              <b>
                <i className="risk-dot high" />
                High
              </b>
              <span>Наведите на ⓘ, чтобы узнать, зачем сайту этот сигнал.</span>
            </div>
          </section>
          <section id="diagnostics">
            <div className="section-title">
              <div>
                <span className="section-kicker">03 / GO A LITTLE DEEPER</span>
                <h2>Network diagnostics</h2>
              </div>
              <span className="optional-tag">OPTIONAL TESTS</span>
            </div>
            <div className="diagnostic-grid">
              <article>
                <div className="diagnostic-icon">
                  <Zap size={23} />
                </div>
                <h3>Проверить соединение</h3>
                <p>
                  Download, upload, HTTP ping и jitter до этого сервера Vercel.
                  Приблизительный тест, около 2.5 MB трафика.
                </p>
                <button
                  onClick={() => void runExtra("speed")}
                  disabled={scanning || !!activeExtra}
                >
                  {activeExtra === "speed" ? (
                    <>
                      <span className="spinner" />
                      Измеряем…
                    </>
                  ) : (
                    <>
                      Запустить тест скорости
                      <ArrowUpRight size={15} />
                    </>
                  )}
                </button>
              </article>
              <article>
                <div className="diagnostic-icon">
                  <Network size={23} />
                </div>
                <h3>Кто разрешает ваши DNS-запросы?</h3>
                <p>
                  Требуется собственный авторитетный DNS-сервис. Без настройки
                  используйте независимую проверку.
                </p>
                <div className="dns-actions">
                  <button
                    onClick={() => void runExtra("dns")}
                    disabled={scanning || !!activeExtra}
                  >
                    {activeExtra === "dns" ? "Проверяем…" : "Проверить DNS"}
                    <ArrowUpRight size={15} />
                  </button>
                  <a
                    href="https://www.dnsleaktest.com/"
                    target="_blank"
                    rel="noreferrer"
                  >
                    dnsleaktest.com
                    <ArrowUpRight size={13} />
                  </a>
                </div>
                <details className="dns-setup">
                  <summary>
                    Как подключить свой DNS-тест <ChevronDown size={12} />
                  </summary>
                  <p>
                    Делегируйте дочернюю зону (например, dnscheck.example.com)
                    через NS на свой VPS. Запустите dns-service/server.py из
                    исходников с открытыми UDP/TCP 53 и защищённым HTTPS API.
                    Обычный wildcard на Vercel не показывает резолверы.
                  </p>
                  <p>
                    В Vercel задайте DNS_TEST_ORIGIN и DNS_TEST_TOKEN, затем
                    выполните redeploy. Подробные команды находятся в README
                    проекта. Сервис создаёт 8 случайных имён и удаляет
                    наблюдения из памяти за 60 секунд.
                  </p>
                </details>
              </article>
            </div>
          </section>
          <footer>
            <div>
              <Fingerprint size={19} />
              <span>Less guesswork. More awareness.</span>
            </div>
            <p>Снимок этой вкладки · Не сертификат анонимности</p>
            <a href="#overview">Наверх ↑</a>
          </footer>
        </main>
      </div>
      {toast && (
        <div className="toast" role="status">
          <Check size={16} />
          {toast}
        </div>
      )}
    </div>
  );
}
