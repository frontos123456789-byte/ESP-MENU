import type { Collector } from "@/lib/types";
import { probe, hash, timeout } from "./utils";
import { FONT_CANDIDATES } from "./fonts";
import { renderGLHash } from "./gpu";
async function audioHash() {
  if (!window.OfflineAudioContext) return null;
  const ctx = new OfflineAudioContext(1, 44100, 44100);
  const osc = ctx.createOscillator();
  osc.type = "triangle";
  osc.frequency.value = 10000;
  const compressor = ctx.createDynamicsCompressor();
  compressor.threshold.value = -50;
  compressor.knee.value = 40;
  compressor.ratio.value = 12;
  compressor.attack.value = 0;
  compressor.release.value = 0.25;
  osc.connect(compressor);
  compressor.connect(ctx.destination);
  osc.start(0);
  try {
    const buffer = await timeout(ctx.startRendering(), 4000);
    const samples = buffer.getChannelData(0).slice(4500, 5000);
    return await hash(samples.buffer);
  } finally {
    osc.disconnect();
    compressor.disconnect();
  }
}
async function voices(signal: AbortSignal) {
  if (!("speechSynthesis" in window)) return null;
  const synth = speechSynthesis;
  if (!synth.getVoices().length && !signal.aborted)
    await new Promise<void>((resolve) => {
      const finish = () => {
        clearTimeout(timer);
        synth.removeEventListener("voiceschanged", finish);
        signal.removeEventListener("abort", finish);
        resolve();
      };
      const timer = setTimeout(finish, 1600);
      synth.addEventListener("voiceschanged", finish);
      signal.addEventListener("abort", finish, { once: true });
    });
  return synth
    .getVoices()
    .map((v) => ({
      name: v.name,
      lang: v.lang,
      localService: v.localService,
      default: v.default,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}
export const fingerprint: Collector = async (signal) =>
  Promise.all([
    probe(
      "canvasHash",
      "Canvas SHA-256",
      async () => {
        const c = document.createElement("canvas");
        c.width = 300;
        c.height = 100;
        const x = c.getContext("2d");
        if (!x) return null;
        x.fillStyle = "#f59b42";
        x.fillRect(12, 12, 200, 50);
        x.font = "19px Arial";
        x.fillStyle = "#112c3e";
        x.fillText("What do websites know? Ω Ж 🧭", 4, 42);
        x.globalCompositeOperation = "multiply";
        x.fillStyle = "#4acbc0";
        x.beginPath();
        x.arc(180, 50, 30, 0, Math.PI * 2);
        x.fill();
        return hash(c.toDataURL());
      },
      "high",
      "Различия отрисовки шрифтов и графики дают воспроизводимый отпечаток.",
    ),
    probe(
      "webglHash",
      "WebGL SHA-256",
      renderGLHash,
      "high",
      "Хэш пикселей реально отрисованного шейдером треугольника.",
    ),
    probe(
      "audioHash",
      "Audio SHA-256",
      audioHash,
      "high",
      "OfflineAudioContext рендерит неслышимый сигнал; микрофон не используется.",
    ),
    probe(
      "fonts",
      "Detected fonts",
      () => {
        const c = document.createElement("canvas").getContext("2d");
        if (!c) return null;
        const sample = "mmmmmmmmmmlliWW0123456789ΩЖ";
        const bases = ["monospace", "sans-serif", "serif"];
        const widths = bases.map((b) => {
          c.font = `72px ${b}`;
          return c.measureText(sample).width;
        });
        return {
          tested: FONT_CANDIDATES.length,
          detected: FONT_CANDIDATES.filter((f) =>
            bases.some((b, i) => {
              c.font = `72px "${f}",${b}`;
              return c.measureText(sample).width !== widths[i];
            }),
          ),
          method:
            "width comparison; browser font restrictions and aliases can affect results",
        };
      },
      "high",
      "Набор шрифтов может выдавать ОС и установленные программы. Определение приблизительное.",
    ),
    probe("voices", "Speech synthesis voices", () => voices(signal), "high"),
    probe(
      "plugins",
      "Browser plugins",
      () =>
        Array.from(navigator.plugins).map((p) => ({
          name: p.name,
          description: p.description,
          filename: p.filename,
        })),
      "medium",
    ),
    probe(
      "mimeTypes",
      "MIME types",
      () =>
        Array.from(navigator.mimeTypes).map((m) => ({
          type: m.type,
          suffixes: m.suffixes,
          description: m.description,
        })),
      "low",
    ),
  ]);
