export function normalizeIP(ip: string): string {
  const s = ip.toLowerCase().split("%")[0];
  if (!s.includes(":")) return s;
  try {
    return new URL(`http://[${s}]/`).hostname.slice(1, -1);
  } catch {
    return s;
  }
}
export function isPublicIP(ip: string) {
  const s = normalizeIP(ip);
  if (s.includes(":")) {
    try {
      new URL(`http://[${s}]/`);
    } catch {
      return false;
    }
    return (
      !/^(::($|1$)|f[cd]|fe[89ab]|ff)/.test(s) &&
      !s.startsWith("2001:db8:") &&
      (s.includes("::ffff:") ? false : true)
    );
  }
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(s)) return false;
  const p = s.split(".").map(Number);
  if (p.length !== 4 || p.some((n) => !Number.isInteger(n) || n < 0 || n > 255))
    return false;
  const [a, b] = p;
  return !(
    a === 0 ||
    a === 10 ||
    a === 127 ||
    a >= 224 ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 192 && b === 0 && (p[2] === 0 || p[2] === 2)) ||
    (a === 198 && (b === 18 || b === 19)) ||
    (a === 198 && b === 51 && p[2] === 100) ||
    (a === 203 && b === 0 && p[2] === 113)
  );
}
