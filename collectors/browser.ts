import { probe } from "./utils";
import type { Collector } from "@/lib/types";
type UAData = {
  brands: unknown;
  mobile: boolean;
  platform: string;
  getHighEntropyValues: (keys: string[]) => Promise<unknown>;
};
export const browser: Collector = async () => {
  const nav = navigator as Navigator & {
    userAgentData?: UAData;
    deviceMemory?: number;
    globalPrivacyControl?: boolean;
  };
  const keys = [
    "userAgent",
    "vendor",
    "language",
    "languages",
    "platform",
    "cookieEnabled",
    "doNotTrack",
    "globalPrivacyControl",
    "pdfViewerEnabled",
    "webdriver",
    "hardwareConcurrency",
    "deviceMemory",
    "maxTouchPoints",
  ] as const;
  return Promise.all([
    ...keys.map((k) =>
      probe(
        k,
        k,
        () => (k === "doNotTrack" ? (nav[k] ?? "unspecified") : nav[k]),
        [
          "userAgent",
          "platform",
          "hardwareConcurrency",
          "deviceMemory",
        ].includes(k)
          ? "high"
          : "low",
      ),
    ),
    probe(
      "uaData",
      "User-Agent Client Hints",
      () =>
        nav.userAgentData && {
          brands: nav.userAgentData.brands,
          mobile: nav.userAgentData.mobile,
          platform: nav.userAgentData.platform,
        },
    ),
    probe(
      "uaHigh",
      "High-entropy Client Hints",
      () =>
        nav.userAgentData?.getHighEntropyValues([
          "platform",
          "platformVersion",
          "architecture",
          "bitness",
          "model",
          "uaFullVersion",
          "fullVersionList",
          "wow64",
        ]),
      "high",
      "Подробная версия ОС и архитектура повышают различимость устройства.",
    ),
  ]);
};
