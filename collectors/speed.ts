import type { Collector } from "@/lib/types";
import { probe } from "./utils";
export const speed: Collector = async (signal) => [
  await probe(
    "speed",
    "Connection benchmark",
    async () => {
      const samples: number[] = [];
      async function request(bytes: number, body?: Uint8Array) {
        const start = performance.now();
        const r = await fetch(
          `/api/network?bytes=${bytes}&nonce=${crypto.randomUUID()}`,
          {
            method: body ? "POST" : "GET",
            body: body ? (body.buffer as ArrayBuffer) : undefined,
            cache: "no-store",
            signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]),
            headers: body
              ? { "Content-Type": "application/octet-stream" }
              : undefined,
          },
        );
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        const b = await r.arrayBuffer();
        return { ms: performance.now() - start, bytes: b.byteLength };
      }
      await request(1);
      for (let i = 0; i < 6; i++) samples.push((await request(1)).ms);
      const down = await request(2 * 1024 * 1024);
      const upload = new Uint8Array(512 * 1024);
      for (let i = 0; i < upload.length; i += 65536)
        crypto.getRandomValues(upload.subarray(i, i + 65536));
      const up = await request(0, upload);
      return {
        downloadMbps: +((down.bytes * 8) / down.ms / 1000).toFixed(2),
        uploadMbps: +((upload.byteLength * 8) / up.ms / 1000).toFixed(2),
        pingMs: +(samples.reduce((a, b) => a + b, 0) / samples.length).toFixed(
          1,
        ),
        jitterMs: +(
          samples
            .slice(1)
            .reduce((a, b, i) => a + Math.abs(b - samples[i]), 0) /
          (samples.length - 1)
        ).toFixed(1),
        samplesMs: samples.map((x) => +x.toFixed(1)),
        downloadBytes: down.bytes,
        uploadBytes: upload.byteLength,
        method:
          "Single HTTP transfer to this Vercel deployment. Includes server overhead; not line capacity or ICMP ping.",
      };
    },
    "medium",
    "Приблизительный HTTP-бенчмарк: около 2.5 MB трафика. Задержка включает работу сервера.",
  ),
];
