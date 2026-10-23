import { NextRequest, NextResponse } from "next/server";
export const dynamic = "force-dynamic";
export async function GET(req: NextRequest) {
  const headers = { "Cache-Control": "no-store" };
  try {
    const origin = process.env.DNS_TEST_ORIGIN;
    const token = process.env.DNS_TEST_TOKEN;
    if (!origin || !token)
      return NextResponse.json({ configured: false }, { headers });
    const action = req.nextUrl.searchParams.get("action");
    if (!action) return NextResponse.json({ configured: true }, { headers });
    const id = req.nextUrl.searchParams.get("id");
    if (
      action !== "start" &&
      (action !== "result" || !id || !/^[a-f0-9]{32}$/.test(id))
    )
      return NextResponse.json(
        { error: "Invalid request" },
        { status: 400, headers },
      );
    const upstream = await fetch(
      new URL(action === "start" ? "/start" : `/result?id=${id}`, origin),
      {
        headers: { Authorization: `Bearer ${token}` },
        cache: "no-store",
        signal: AbortSignal.timeout(5000),
      },
    );
    if (!upstream.ok) throw new Error("DNS service unavailable");
    const data = await upstream.json();
    return NextResponse.json(data, { headers });
  } catch {
    return NextResponse.json(
      { error: "DNS service unavailable" },
      { status: 502, headers },
    );
  }
}
