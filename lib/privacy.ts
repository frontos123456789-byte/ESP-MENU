import type { Field, Finding, Section, Whoami } from "./types";
import { normalizeIP } from "./ip";
import { hash } from "@/collectors/utils";
export function getField(sections: Section[], key: string) {
  return sections.flatMap((s) => s.fields).find((f) => f.key === key);
}
export function getValue<T>(sections: Section[], key: string): T | undefined {
  const f = getField(sections, key);
  return f?.status === "ok" ? (f.value as T) : undefined;
}
export const fingerprintKeys = [
  "userAgent",
  "uaHigh",
  "platform",
  "hardwareConcurrency",
  "deviceMemory",
  "maxTouchPoints",
  "languages",
  "screen.width",
  "screen.height",
  "screen.colorDepth",
  "devicePixelRatio",
  "timezone",
  "webgl",
  "webgl2",
  "webgpu",
  "canvasHash",
  "webglHash",
  "audioHash",
  "fonts",
  "voices",
  "plugins",
  "mimeTypes",
];
function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object")
    return Object.fromEntries(
      Object.entries(value)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => [k, canonical(v)]),
    );
  return value;
}
export async function combinedFingerprint(sections: Section[]) {
  const fields = sections
    .flatMap((s) => s.fields)
    .filter((f) => fingerprintKeys.includes(f.key))
    .sort((a, b) => a.key.localeCompare(b.key));
  return hash(
    JSON.stringify({
      version: 1,
      features: fields.map((f) => ({
        key: f.key,
        status: f.status,
        value: f.status === "ok" ? canonical(f.value) : null,
      })),
    }),
  );
}
export function entropyEstimate(fields: Field[]) {
  const weights: Record<string, number> = {
    userAgent: 3,
    uaHigh: 3,
    "screen.width": 2,
    "screen.height": 2,
    devicePixelRatio: 1,
    timezone: 2,
    languages: 2,
    hardwareConcurrency: 1,
    deviceMemory: 1,
    webgl: 4,
    canvasHash: 4,
    webglHash: 3,
    audioHash: 3,
    fonts: 4,
    voices: 2,
  };
  const contributions = fields
    .filter((f) => f.status === "ok" && f.value !== null && weights[f.key])
    .map((f) => ({ feature: f.key, weight: weights[f.key] }));
  return {
    bits: contributions.reduce((n, c) => n + c.weight, 0),
    contributions,
    method:
      "Illustrative weighted signal count, NOT measured Shannon entropy or population uniqueness. Correlated features are not statistically calibrated.",
  };
}
const HOSTING_PATTERN =
  /\b(vpn|proxy|mullvad|proton|nord|express ?vpn|surfshark|windscribe|cyberghost|ipvanish|m247|datacamp|cdn77|hetzner|ovh|digitalocean|linode|akamai connected cloud|vultr|choopa|leaseweb|contabo|scaleway|oracle cloud|amazon|aws|google cloud|microsoft azure|alibaba cloud|tencent cloud|hosting|colo(cation)?|data ?center|server)\b/i;
function hostingHint(connection: unknown): string | null {
  if (!connection || typeof connection !== "object") return null;
  const c = connection as Record<string, unknown>;
  for (const key of ["org", "isp", "domain"]) {
    const v = c[key];
    if (typeof v === "string" && HOSTING_PATTERN.test(v)) return v;
  }
  return null;
}
function familyOf(ip: string) {
  return ip.includes(":") ? 6 : 4;
}
export function privacyReport(sections: Section[]) {
  const findings: Finding[] = [];
  const http = getValue<Whoami>(sections, "http");
  const e = http?.enrichment;
  const security = e?.security as Record<string, boolean> | null | undefined;
  const flags = security
    ? Object.entries(security).filter(([k]) =>
        /^(is_)?(proxy|vpn|hosting|tor)$/.test(k),
      )
    : [];
  const positives = flags.filter(([, v]) => v === true);
  const orgHint = flags.length ? null : hostingHint(e?.connection);
  findings.push({
    id: "vpn",
    title: "VPN / proxy / hosting",
    level:
      positives.length || orgHint
        ? "yellow"
        : flags.length
          ? "green"
          : "unknown",
    detail: positives.length
      ? `IP-база сообщает: ${positives.map(([k]) => k).join(", ")}. Это классификация, а не доказательство утечки.`
      : orgHint
        ? `Оператор IP («${orgHint}») похож на VPN или дата-центр. Это эвристика по названию организации, а не проверка по базе: возможны ошибки в обе стороны.`
        : flags.length
          ? "Провайдер данных не отметил проверенные категории. Ошибки классификации возможны."
          : "Бесплатный API не вернул security-флаги, а название оператора не похоже на VPN или хостинг; наличие VPN неизвестно.",
  });
  const tz = getValue<string>(sections, "timezone");
  const iptz =
    http?.geo.timezone || (e?.timezone as { id?: string } | null)?.id;
  let zoneMismatch = false;
  if (tz && iptz) {
    try {
      const now = new Date();
      zoneMismatch =
        new Intl.DateTimeFormat("en", {
          timeZone: tz,
          timeZoneName: "longOffset",
        })
          .formatToParts(now)
          .find((p) => p.type === "timeZoneName")?.value !==
        new Intl.DateTimeFormat("en", {
          timeZone: iptz,
          timeZoneName: "longOffset",
        })
          .formatToParts(now)
          .find((p) => p.type === "timeZoneName")?.value;
    } catch {
      zoneMismatch = tz !== iptz;
    }
  }
  findings.push({
    id: "timezone",
    title: "Часовой пояс",
    level: tz && iptz ? (zoneMismatch ? "yellow" : "green") : "unknown",
    detail:
      tz && iptz
        ? `${tz} в браузере · ${iptz} по IP. ${zoneMismatch ? "UTC-смещения отличаются; возможны VPN, путешествие или настройка ОС." : "UTC-смещения совпадают; это не исключает VPN."}`
        : "Недостаточно данных для сравнения.",
    recommendation: zoneMismatch
      ? "Проверьте часовой пояс ОС и ожидаемый регион VPN. Расхождение само по себе не опасно."
      : undefined,
  });
  const language = getValue<string>(sections, "language");
  const languages = getValue<string[]>(sections, "languages");
  const country = http?.geo.country || (e?.country_code as string | undefined);
  let region: string | undefined;
  for (const tag of [language, ...(Array.isArray(languages) ? languages : [])]) {
    if (!tag) continue;
    try {
      region = new Intl.Locale(tag).region;
    } catch {}
    if (region) break;
  }
  findings.push({
    id: "language",
    title: "Язык и страна IP",
    level:
      country && region ? (country === region ? "green" : "yellow") : "unknown",
    detail:
      country && region
        ? `Регион языка ${region}, страна IP ${country}. Языковые предпочтения не определяют местоположение.`
        : "У языка нет явного региона либо страна IP неизвестна.",
  });
  const ice = getValue<{ publicIPs: string[]; completed: boolean }>(
    sections,
    "ice",
  );
  const httpIP = http?.ip;
  const v4Seen = getValue<string>(sections, "ipv4");
  const v6Seen = getValue<string>(sections, "ipv6");
  const knownIPs = [httpIP, v4Seen, v6Seen]
    .filter((ip): ip is string => typeof ip === "string" && ip.length > 0)
    .map(normalizeIP);
  const exposed = ice?.publicIPs.filter((ip) => {
    const sameFamily = knownIPs.filter((k) => familyOf(k) === familyOf(ip));
    return sameFamily.length > 0 && !sameFamily.includes(normalizeIP(ip));
  });
  findings.push({
    id: "webrtc",
    title: "WebRTC",
    level:
      !ice || !httpIP
        ? "unknown"
        : exposed?.length
          ? "red"
          : ice.publicIPs.length
            ? "green"
            : "unknown",
    detail: exposed?.length
      ? `Другой публичный адрес того же семейства: ${exposed.join(", ")}. Возможен обход HTTP-прокси/VPN; подтвердите с включённым VPN.`
      : ice?.publicIPs.length
        ? "Отличающийся публичный IP того же семейства не обнаружен."
        : "Публичных ICE-кандидатов нет; STUN мог быть заблокирован. Это не доказательство отсутствия утечки.",
    recommendation: exposed?.length
      ? "Включите защиту WebRTC в VPN/браузере и повторите проверку с включённым VPN."
      : undefined,
  });
  const v6 = v6Seen;
  const v4 = v4Seen;
  const ipv6Ice = ice?.publicIPs.filter((ip) => ip.includes(":")) || [];
  findings.push({
    id: "ipv6",
    title: "IPv6",
    level: v6 || ipv6Ice.length ? "yellow" : "unknown",
    detail: v6
      ? `IPv6 доступен: ${v6}. Сравните этот адрес с ожидаемым IPv6 вашего VPN; IPv4 и IPv6 нельзя сравнивать напрямую.`
      : ipv6Ice.length
        ? `WebRTC обнаружил IPv6: ${ipv6Ice.join(", ")}. Проверка через IPv6-only HTTP не завершилась.`
        : "IPv6-only endpoint недоступен. Причиной могут быть блокировка, CORS или отсутствие IPv6.",
    recommendation:
      v6 || ipv6Ice.length
        ? "Убедитесь, что VPN маршрутизирует IPv6; если нет — включите его защиту от IPv6-утечек."
        : undefined,
  });
  if (
    v4 &&
    httpIP &&
    !httpIP.includes(":") &&
    normalizeIP(v4) !== normalizeIP(httpIP)
  )
    findings.push({
      id: "routing",
      title: "HTTP routing",
      level: "yellow",
      detail: `Сайт видит ${httpIP}, IPv4 endpoint — ${v4}. Возможны split tunneling, прокси или смена адреса.`,
      recommendation:
        "Проверьте split tunneling и исключения в настройках VPN.",
    });
  const dns = getField(sections, "dns");
  findings.push({
    id: "dns",
    title: "DNS-резолверы",
    level: "unknown",
    detail:
      dns?.status === "ok"
        ? "Резолверы показаны в DNS-карточке. Для вывода об утечке сравните их с ожидаемыми резолверами VPN."
        : "Авторитетный DNS-тест ещё не выполнен или не настроен.",
  });
  const entropy = entropyEstimate(sections.flatMap((s) => s.fields));
  const fpReady =
    sections.find((s) => s.id === "fingerprint")?.state === "done";
  findings.push({
    id: "fingerprint",
    title: "Fingerprint exposure",
    level: !fpReady
      ? "unknown"
      : entropy.bits >= 24
        ? "red"
        : entropy.bits >= 12
          ? "yellow"
          : "green",
    detail: `${entropy.bits} условных бит по весам признаков. Это оценка доступности сигналов, не измеренная энтропия и не процент уникальности.`,
    recommendation:
      entropy.bits >= 12
        ? "Используйте встроенную защиту от fingerprinting. Множество редких расширений может сделать набор признаков заметнее."
        : undefined,
  });
  const penalties: Record<string, number> = {
    webrtc: 30,
    routing: 8,
    timezone: 5,
    language: 3,
    ipv6: 8,
    fingerprint: 25,
  };
  const known = findings.filter((f) => f.level !== "unknown");
  const score = Math.max(
    0,
    100 -
      known.reduce(
        (sum, f) =>
          sum +
          (f.level === "red"
            ? penalties[f.id] || 0
            : f.level === "yellow"
              ? (penalties[f.id] || 0) * 0.5
              : 0),
        0,
      ),
  );
  const recommendations = [
    ...new Set(
      findings
        .flatMap((f) => (f.recommendation ? [f.recommendation] : []))
        .concat([
          "Проверьте DNS на dnsleaktest.com с включённым VPN и сравните результат без VPN.",
          "Оставьте браузер обновлённым; включите защиту от трекеров и Global Privacy Control, если доступны.",
          "Повторите сканирование в обычном и приватном окне: инкогнито не скрывает IP и отпечаток.",
        ]),
    ),
  ].slice(0, 5);
  return {
    findings,
    score: known.length ? Math.round(score) : null,
    coverage: `${known.length}/${findings.length}`,
    entropy,
    recommendations,
  };
}
