import { NextRequest } from "next/server";
import { randomFillSync } from "node:crypto";
export const dynamic = "force-dynamic";
const headers = {
  "Cache-Control": "no-store, no-transform",
  "Content-Type": "application/octet-stream",
};
export async function GET(req: NextRequest) {
  try {
    const n = Number(req.nextUrl.searchParams.get("bytes") || 1);
    if (!Number.isInteger(n) || n < 1 || n > 2097152)
      return new Response(null, { status: 400, headers });
    const buffer = new Uint8Array(n);
    randomFillSync(buffer);
    return new Response(buffer, {
      headers: { ...headers, "Content-Length": String(n) },
    });
  } catch {
    return new Response(null, { status: 500, headers });
  }
}
export async function POST(req: NextRequest) {
  try {
    if (Number(req.headers.get("content-length")) > 524288)
      return new Response(null, { status: 413, headers });
    const reader = req.body?.getReader();
    if (!reader) return new Response(null, { status: 400, headers });
    let size = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 524288) {
        await reader.cancel();
        return new Response(null, { status: 413, headers });
      }
    }
    return Response.json(
      { received: size },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return new Response(null, { status: 400, headers });
  }
}
