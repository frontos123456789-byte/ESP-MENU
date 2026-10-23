// Best-effort in-memory limiter. Serverless instances do not share memory, so this
// only blunts bursts from one client; it is not a substitute for Vercel Firewall rules.
const buckets = new Map<string, { count: number; reset: number }>();
export function allow(key: string, limit: number, windowMs = 60_000, now = Date.now()) {
  if (buckets.size > 5000)
    for (const [k, v] of buckets) if (v.reset <= now) buckets.delete(k);
  const b = buckets.get(key);
  if (!b || b.reset <= now) {
    buckets.set(key, { count: 1, reset: now + windowMs });
    return true;
  }
  b.count += 1;
  return b.count <= limit;
}
