import type { Collector } from "@/lib/types";
import { json, probe, unknown } from "./utils";
export const dns: Collector = async (signal) => {
  const config = await json("/api/dns", signal);
  if (!config.configured)
    return [
      unknown(
        "dns",
        "DNS resolver test",
        "Не настроен авторитетный DNS-сервис. Wildcard-записи Vercel недостаточно. См. README или dnsleaktest.com.",
      ),
    ];
  return [
    await probe(
      "dns",
      "Observed DNS resolvers",
      async () => {
        const session = await json("/api/dns?action=start", signal);
        await Promise.allSettled(
          session.hosts.map((host: string) =>
            fetch(`https://${host}/probe`, {
              mode: "no-cors",
              credentials: "omit",
              cache: "no-store",
              referrerPolicy: "no-referrer",
              signal: AbortSignal.any([signal, AbortSignal.timeout(4000)]),
            }),
          ),
        );
        return await json(
          `/api/dns?action=result&id=${encodeURIComponent(session.id)}`,
          signal,
        );
      },
      "high",
      "Временный авторитетный DNS-сервис видит IP рекурсивных резолверов, а не обязательно вашего провайдера. Записи живут не более 60 секунд.",
    ),
  ];
};
