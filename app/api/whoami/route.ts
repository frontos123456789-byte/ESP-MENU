import { NextRequest, NextResponse } from "next/server";
import { isIP } from "node:net";
import { isPublicIP } from "@/lib/ip";
export const dynamic = "force-dynamic";
export async function GET(request: NextRequest) {
  try {
    const headers = Object.fromEntries(request.headers.entries());
    const candidate = (
      headers["x-forwarded-for"]?.split(",")[0] ||
      headers["x-real-ip"] ||
      ""
    ).trim();
    const ip = isIP(candidate) ? candidate : null;
    const geo = Object.fromEntries(
      [
        "country",
        "country-region",
        "city",
        "latitude",
        "longitude",
        "timezone",
      ].map((k) => {
        const v =
          headers[`x-vercel-ip-${k}`] ||
          (k === "country-region" ? headers["x-vercel-ip-region"] : null);
        let decoded = v || null;
        try {
          decoded = v ? decodeURIComponent(v) : null;
        } catch {}
        return [k, decoded];
      }),
    );
    let enrichment = null;
    let enrichmentError = null;
    if (ip && isPublicIP(ip))
      try {
        const r = await fetch(`https://ipwho.is/${encodeURIComponent(ip)}`, {
          cache: "no-store",
          signal: AbortSignal.timeout(4500),
        });
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        const data = await r.json();
        if (!data.success) throw new Error(data.message || "Lookup failed");
        enrichment = {
          country: data.country,
          country_code: data.country_code,
          region: data.region,
          city: data.city,
          latitude: data.latitude,
          longitude: data.longitude,
          timezone: data.timezone,
          connection: data.connection,
          security: data.security || null,
        };
      } catch (e) {
        enrichmentError = e instanceof Error ? e.message : "Lookup failed";
      }
    return NextResponse.json(
      {
        ip,
        ipVersion: ip ? `IPv${isIP(ip)}` : null,
        geo,
        headers,
        protocol:
          headers["x-forwarded-proto"] ||
          request.nextUrl.protocol.replace(":", ""),
        httpVersion: null,
        enrichment,
        enrichmentError,
      },
      { headers: { "Cache-Control": "private, no-store, max-age=0" } },
    );
  } catch {
    return NextResponse.json(
      { error: "Could not inspect request" },
      { status: 500, headers: { "Cache-Control": "no-store" } },
    );
  }
}
