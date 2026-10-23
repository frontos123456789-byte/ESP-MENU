import type { Collector } from "@/lib/types";
import { probe, timeout } from "./utils";
const permissions = [
  "accelerometer",
  "ambient-light-sensor",
  "background-fetch",
  "background-sync",
  "bluetooth",
  "camera",
  "clipboard-read",
  "clipboard-write",
  "display-capture",
  "geolocation",
  "gyroscope",
  "idle-detection",
  "local-fonts",
  "magnetometer",
  "microphone",
  "midi",
  "nfc",
  "notifications",
  "payment-handler",
  "persistent-storage",
  "push",
  "screen-wake-lock",
  "speaker-selection",
  "storage-access",
  "top-level-storage-access",
  "window-management",
];
export const device: Collector = async () => {
  const nav = navigator as Navigator & {
    getBattery?: () => Promise<{
      charging: boolean;
      chargingTime: number;
      dischargingTime: number;
      level: number;
    }>;
    keyboard?: { getLayoutMap: () => Promise<Map<string, string>> };
  };
  const codecs = [
    ["H.264", 'video/mp4; codecs="avc1.42E01E"'],
    ["VP9", 'video/webm; codecs="vp09.00.10.08"'],
    ["AV1", 'video/mp4; codecs="av01.0.04M.08"'],
    ["HEVC", 'video/mp4; codecs="hvc1.1.6.L93.B0"'],
    ["AAC", 'audio/mp4; codecs="mp4a.40.2"'],
  ];
  return Promise.all([
    probe("battery", "Battery", async () => {
      if (!nav.getBattery) return null;
      const b = await timeout(nav.getBattery());
      return {
        charging: b.charging,
        level: b.level,
        chargingTime: Number.isFinite(b.chargingTime)
          ? b.chargingTime
          : "Infinity",
        dischargingTime: Number.isFinite(b.dischargingTime)
          ? b.dischargingTime
          : "Infinity",
      };
    }),
    probe(
      "storage",
      "Storage estimate",
      () => navigator.storage?.estimate(),
      "medium",
      "Квота зависит от браузера, свободного места и политики хранения; она не доказывает инкогнито.",
    ),
    probe(
      "persisted",
      "Persistent storage",
      () => navigator.storage?.persisted(),
      "low",
    ),
    probe(
      "devices",
      "Media device inventory",
      async () => {
        if (!navigator.mediaDevices?.enumerateDevices) return null;
        const ds = await timeout(navigator.mediaDevices.enumerateDevices());
        return {
          counts: {
            cameras: ds.filter((d) => d.kind === "videoinput").length,
            microphones: ds.filter((d) => d.kind === "audioinput").length,
            speakers: ds.filter((d) => d.kind === "audiooutput").length,
          },
          devices: ds.map((d) => ({
            kind: d.kind,
            label: d.label || "(hidden)",
            deviceId: d.deviceId,
            groupId: d.groupId,
          })),
          note: "Без разрешений список может быть пустым или неполным; политика страницы блокирует камеру и микрофон.",
        };
      },
      "high",
    ),
    ...permissions.map((name) =>
      probe(
        `permission.${name}`,
        `Permission · ${name}`,
        async () => {
          if (!navigator.permissions) return null;
          try {
            return (
              await navigator.permissions.query({
                name: name as PermissionName,
              })
            ).state;
          } catch (e) {
            // Browsers throw TypeError for permission names they do not implement.
            if (e instanceof TypeError) return null;
            throw e;
          }
        },
        "low",
        "Только чтение статуса; запрос разрешения не выполняется. Для камеры, микрофона и геолокации denied может отражать Permissions-Policy этой страницы.",
      ),
    ),
    probe(
      "sensors",
      "Sensor interfaces",
      () =>
        Object.fromEntries(
          [
            "Accelerometer",
            "LinearAccelerationSensor",
            "GravitySensor",
            "Gyroscope",
            "Magnetometer",
            "AbsoluteOrientationSensor",
            "RelativeOrientationSensor",
            "AmbientLightSensor",
            "DeviceMotionEvent",
            "DeviceOrientationEvent",
          ].map((k) => [k, k in window]),
        ),
      "low",
      "Проверяется наличие API, сенсоры не активируются.",
    ),
    probe("gamepads", "Gamepads", () =>
      navigator.getGamepads
        ? Array.from(navigator.getGamepads())
            .filter(Boolean)
            .map((g) => ({
              id: g!.id,
              mapping: g!.mapping,
              axes: g!.axes,
              buttons: g!.buttons.length,
              connected: g!.connected,
            }))
        : null,
    ),
    probe(
      "interfaces",
      "Device APIs",
      () =>
        Object.fromEntries(
          [
            "bluetooth",
            "usb",
            "serial",
            "hid",
            "keyboard",
            "credentials",
            "mediaCapabilities",
          ].map((k) => [k, k in navigator]),
        ),
      "low",
    ),
    probe(
      "keyboard",
      "Keyboard layout",
      () => nav.keyboard?.getLayoutMap().then((m) => Object.fromEntries(m)),
      "high",
      "Раскладка клавиш может указывать на язык и регион. Браузер может заблокировать API.",
    ),
    ...codecs.map(([name, contentType]) =>
      probe(
        `codec.${name}`,
        `Codec · ${name}`,
        async () => {
          const media = document.createElement(
            contentType.startsWith("audio") ? "audio" : "video",
          );
          const canPlay = media.canPlayType(contentType);
          if (!navigator.mediaCapabilities) return { canPlay: canPlay || "no" };
          const config: MediaDecodingConfiguration = {
            type: "file",
            ...(contentType.startsWith("audio")
              ? {
                  audio: {
                    contentType,
                    channels: "2",
                    bitrate: 128000,
                    samplerate: 48000,
                  },
                }
              : {
                  video: {
                    contentType,
                    width: 1920,
                    height: 1080,
                    bitrate: 5000000,
                    framerate: 30,
                  },
                }),
          };
          const info = await timeout(
            navigator.mediaCapabilities.decodingInfo(config),
          );
          return {
            canPlay: canPlay || "no",
            supported: info.supported,
            smooth: info.smooth,
            powerEfficient: info.powerEfficient,
          };
        },
        "low",
      ),
    ),
  ]);
};
