import type { Field, Risk, Value } from "@/lib/types";
export const valueOf = (v: unknown): Value =>
  v === undefined ? null : JSON.parse(JSON.stringify(v));
export function field(
  key: string,
  label: string,
  value: unknown,
  risk: Risk = "medium",
  note = "Этот признак помогает сайту различать браузеры и адаптировать интерфейс.",
): Field {
  return {
    key,
    label,
    value: valueOf(value),
    risk,
    note,
    status: value === undefined || value === null ? "unsupported" : "ok",
  };
}
export async function probe(
  key: string,
  label: string,
  read: () => unknown | Promise<unknown>,
  risk: Risk = "medium",
  note?: string,
): Promise<Field> {
  try {
    return field(key, label, await read(), risk, note);
  } catch (e) {
    return {
      key,
      label,
      value: e instanceof Error ? e.message : String(e),
      risk,
      note: note || "API заблокирован, недоступен или завершился ошибкой.",
      status: "error",
    };
  }
}
export async function hash(data: string | ArrayBuffer) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        typeof data === "string" ? new TextEncoder().encode(data) : data,
      ),
    ),
  )
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
export async function json(url: string, signal: AbortSignal, timeout = 6500) {
  const r = await fetch(url, {
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
    signal: AbortSignal.any([signal, AbortSignal.timeout(timeout)]),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}
export function timeout<T>(promise: Promise<T>, ms = 5000): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Время ожидания истекло")),
      ms,
    );
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}
export function unknown(key: string, label: string, reason: string): Field {
  return {
    key,
    label,
    value: reason,
    risk: "medium",
    status: "unknown",
    note: reason,
  };
}
