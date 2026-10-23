import type { Collector, Whoami } from "@/lib/types";
import { field, json, probe, unknown } from "./utils";
export const network: Collector = async (signal) => {
  const results = await Promise.all([
    probe(
      "http",
      "HTTP identity",
      async () => (await json("/api/whoami", signal)) as Whoami,
      "high",
      "Ваш IP и заголовки видны каждому серверу, к которому вы обращаетесь.",
    ),
    probe(
      "ipv4",
      "IPv4-only endpoint",
      async () => (await json("https://api.ipify.org?format=json", signal)).ip,
      "high",
    ),
    probe(
      "ipv6",
      "IPv6-only endpoint",
      async () => (await json("https://api6.ipify.org?format=json", signal)).ip,
      "high",
      "Доступность IPv6 сама по себе не доказывает утечку VPN.",
    ),
    probe("connection", "Network Information", () => {
      const n = navigator as Navigator & {
        connection?: {
          effectiveType?: string;
          downlink?: number;
          rtt?: number;
          saveData?: boolean;
          type?: string;
        };
      };
      const c = n.connection;
      return c
        ? {
            effectiveType: c.effectiveType,
            downlink: c.downlink,
            rtt: c.rtt,
            saveData: c.saveData,
            type: c.type,
          }
        : null;
    }),
  ]);
  results.push(
    await probe(
      "protocols",
      "Resource next-hop protocols",
      () =>
        (
          performance.getEntriesByType(
            "resource",
          ) as PerformanceResourceTiming[]
        )
          .filter((e) => e.nextHopProtocol)
          .map((e) => ({
            resource: new URL(e.name).pathname,
            protocol: e.nextHopProtocol,
          })),
      "low",
      "Resource Timing показывает h2/h3 для доступных записей. Для cross-origin данных может требоваться Timing-Allow-Origin.",
    ),
  );
  const http = results.find((f) => f.key === "http");
  if (http?.status === "ok") {
    const data = http.value as unknown as Whoami;
    results.push(
      field("ip", "Public IP", data.ip, "high"),
      field("ipVersion", "IP version", data.ipVersion),
      field("geo", "Vercel geolocation", data.geo, "high"),
    );
    results.push(
      field(
        "ipEnrichment",
        "IP enrichment · ipwho.is",
        data.enrichment,
        "high",
        "Приблизительная геолокация и оператор IP; security-флаги доступны не на каждом тарифе.",
      ),
    );
    if (data.enrichmentError)
      results.push(
        unknown(
          "enrichmentError",
          "Enrichment unavailable",
          data.enrichmentError,
        ),
      );
    for (const [key, v] of Object.entries(data.headers))
      results.push(
        field(
          `header.${key}`,
          key,
          v,
          /^(cookie|authorization|x-real-ip|x-forwarded-for|x-vercel-forwarded-for|x-vercel-ip-.+)$/.test(
            key,
          )
            ? "high"
            : "medium",
          "Входящий HTTP-заголовок, доступный приложению после прокси Vercel. Экспорт может содержать чувствительные значения.",
        ),
      );
  }
  return results;
};
