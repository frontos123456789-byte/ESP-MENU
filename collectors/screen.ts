import { probe } from "./utils";
import type { Collector } from "@/lib/types";
export const screenCollector: Collector = async () => {
  const queries = [
    "prefers-color-scheme: dark",
    "prefers-color-scheme: light",
    "prefers-reduced-motion: reduce",
    "prefers-contrast: more",
    "prefers-contrast: less",
    "forced-colors: active",
    "hover: hover",
    "any-hover: hover",
    "pointer: fine",
    "pointer: coarse",
    "any-pointer: fine",
    "inverted-colors: inverted",
    "dynamic-range: high",
    "video-dynamic-range: high",
    "color-gamut: srgb",
    "color-gamut: p3",
    "color-gamut: rec2020",
  ];
  return Promise.all([
    ...(
      [
        "width",
        "height",
        "availWidth",
        "availHeight",
        "colorDepth",
        "pixelDepth",
      ] as const
    ).map((k) => probe(`screen.${k}`, `screen.${k}`, () => screen[k])),
    ...(
      [
        "innerWidth",
        "innerHeight",
        "outerWidth",
        "outerHeight",
        "devicePixelRatio",
      ] as const
    ).map((k) => probe(k, k, () => window[k])),
    probe(
      "orientation",
      "Orientation",
      () =>
        screen.orientation && {
          type: screen.orientation.type,
          angle: screen.orientation.angle,
        },
    ),
    probe(
      "visualViewport",
      "Visual viewport",
      () =>
        window.visualViewport && {
          width: visualViewport!.width,
          height: visualViewport!.height,
          scale: visualViewport!.scale,
          offsetLeft: visualViewport!.offsetLeft,
          offsetTop: visualViewport!.offsetTop,
        },
    ),
    ...queries.map((q) =>
      probe(
        q,
        q,
        () => matchMedia(`(${q})`).matches,
        "low",
        "Медиа-запрос показывает предпочтения интерфейса или возможности дисплея.",
      ),
    ),
  ]);
};
