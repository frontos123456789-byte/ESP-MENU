import type { Collector } from "@/lib/types";
import { probe } from "./utils";
export const locale: Collector = async () =>
  Promise.all([
    probe(
      "intl",
      "Intl.DateTimeFormat",
      () => Intl.DateTimeFormat().resolvedOptions(),
      "high",
    ),
    probe(
      "timezone",
      "Time zone",
      () => Intl.DateTimeFormat().resolvedOptions().timeZone,
      "high",
      "Часовой пояс может отличаться от региона VPN-сервера. Само расхождение не доказывает VPN.",
    ),
    probe("timezoneOffset", "UTC offset (minutes)", () =>
      new Date().getTimezoneOffset(),
    ),
    probe("numberFormat", "Number format", () =>
      Intl.NumberFormat().resolvedOptions(),
    ),
    probe("localTime", "Local date & time", () => new Date().toString(), "low"),
  ]);
