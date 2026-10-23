import type { Collector } from "@/lib/types";
import { probe, unknown } from "./utils";
export const behavior: Collector = async () => [
  await probe(
    "adblock",
    "Ad-blocking bait",
    () => {
      const el = document.createElement("div");
      el.className = "adsbox ad-banner adsbygoogle";
      el.style.cssText =
        "position:absolute;left:-10000px;width:1px;height:1px;";
      document.body.appendChild(el);
      try {
        return {
          hidden:
            getComputedStyle(el).display === "none" || el.offsetHeight === 0,
          method: "local cosmetic-filter bait; inconclusive",
        };
      } finally {
        el.remove();
      }
    },
    "low",
    "Косметический фильтр может скрыть тестовый элемент. Отрицательный результат не исключает блокировщик.",
  ),
  await probe(
    "brave",
    "Brave self-identification",
    () =>
      (
        navigator as Navigator & { brave?: { isBrave: () => Promise<boolean> } }
      ).brave?.isBrave(),
    "medium",
  ),
  await probe(
    "automation",
    "Automation signals",
    () => ({
      webdriver: navigator.webdriver,
      headlessUserAgent: /HeadlessChrome|PhantomJS/i.test(navigator.userAgent),
      languagesEmpty: navigator.languages.length === 0,
    }),
    "high",
    "Сигналы автоматизации не являются доказательством: их можно скрыть или получить в обычном окружении.",
  ),
  await probe(
    "rfp",
    "Anti-fingerprinting artifacts",
    () => ({
      firefox: /Firefox\//.test(navigator.userAgent),
      utc: Intl.DateTimeFormat().resolvedOptions().timeZone === "UTC",
      screenMatchesViewport:
        screen.width === innerWidth && screen.height === innerHeight,
      hardwareConcurrencyTwo: navigator.hardwareConcurrency === 2,
    }),
    "medium",
    "Артефакты совместимы с Firefox resistFingerprinting/Tor, но также встречаются в обычных браузерах.",
  ),
  unknown(
    "incognito",
    "Incognito mode",
    "Надёжное определение без разрешений невозможно. Квота хранилища показана отдельно; низкая квота не доказывает приватный режим.",
  ),
  unknown(
    "tor",
    "Tor Browser",
    "По JavaScript нельзя достоверно установить Tor. Отсутствие security-флага IP не исключает Tor.",
  ),
];
