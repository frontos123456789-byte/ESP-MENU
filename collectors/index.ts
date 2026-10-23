import type { Collector } from "@/lib/types";
import { browser } from "./browser";
import { screenCollector } from "./screen";
import { locale } from "./locale";
import { gpu } from "./gpu";
import { fingerprint } from "./fingerprint";
import { network } from "./network";
import { webrtc } from "./webrtc";
import { device } from "./device";
import { behavior } from "./behavior";
export const collectors: {
  id: string;
  title: string;
  description: string;
  run: Collector;
}[] = [
  {
    id: "network",
    title: "Network & identity",
    description: "IP, геолокация и всё, что вы отправляете серверу",
    run: network,
  },
  {
    id: "browser",
    title: "Browser & OS",
    description: "Браузер, система и настройки приватности",
    run: browser,
  },
  {
    id: "screen",
    title: "Screen & display",
    description: "Размеры, возможности экрана и предпочтения",
    run: screenCollector,
  },
  {
    id: "locale",
    title: "Time & language",
    description: "Часовой пояс, локаль и форматирование",
    run: locale,
  },
  {
    id: "gpu",
    title: "Graphics & GPU",
    description: "Графическое оборудование и драйверы",
    run: gpu,
  },
  {
    id: "fingerprint",
    title: "Digital fingerprint",
    description: "Незаметные различия, которые узнают ваш браузер",
    run: fingerprint,
  },
  {
    id: "webrtc",
    title: "WebRTC & interfaces",
    description: "Адреса, обнаруженные через ICE / STUN",
    run: webrtc,
  },
  {
    id: "device",
    title: "Device & storage",
    description: "Оборудование, API, разрешения и кодеки",
    run: device,
  },
  {
    id: "behavior",
    title: "Browser defenses",
    description: "Эвристики защиты и автоматизации",
    run: behavior,
  },
];
