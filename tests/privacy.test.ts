import test from "node:test";
import assert from "node:assert/strict";
import { combinedFingerprint, privacyReport } from "../lib/privacy";
import { normalizeIP, isPublicIP } from "../lib/ip";
import type { Field, Section, Whoami } from "../lib/types";
const f = (
  key: string,
  value: unknown,
  status: Field["status"] = "ok",
): Field => ({
  key,
  label: key,
  value: value as Field["value"],
  status,
  risk: "medium",
  note: "",
});
const section = (fields: Field[], id = "network"): Section => ({
  id,
  title: id,
  description: "",
  state: "done",
  fields,
});
const http = (ip: string): Whoami => ({
  ip,
  ipVersion: ip.includes(":") ? "IPv6" : "IPv4",
  geo: {},
  headers: {},
  protocol: "https",
  httpVersion: null,
  enrichment: null,
  enrichmentError: null,
});
const level = (sections: Section[], id: string) =>
  privacyReport(sections).findings.find((f) => f.id === id)?.level;

test("missing evidence never becomes successful VPN, WebRTC, DNS or IPv6 test", () => {
  const report = privacyReport([]);
  for (const id of ["vpn", "webrtc", "dns", "ipv6"])
    assert.equal(report.findings.find((f) => f.id === id)?.level, "unknown");
  assert.equal(report.score, null);
});
test("HTTP / ICE same-family mismatch is flagged; equivalent IPv6 formats match", () => {
  assert.equal(
    level(
      [
        section([
          f("http", http("8.8.8.8")),
          f("ice", { publicIPs: ["1.1.1.1"], completed: true }),
        ]),
      ],
      "webrtc",
    ),
    "red",
  );
  assert.equal(
    level(
      [
        section([
          f("http", http("2001:4860:4860::8888")),
          f("ice", {
            publicIPs: ["2001:4860:4860:0:0:0:0:8888"],
            completed: true,
          }),
        ]),
      ],
      "webrtc",
    ),
    "green",
  );
});
test("dual-stack addresses are not compared as if they were same-family identities", () => {
  assert.notEqual(
    level(
      [
        section([
          f("http", http("8.8.8.8")),
          f("ice", { publicIPs: ["2606:4700:4700::1111"], completed: true }),
          f("ipv6", "2606:4700:4700::1111"),
        ]),
      ],
      "webrtc",
    ),
    "red",
  );
  assert.equal(
    level([section([f("ipv6", "2606:4700:4700::1111")])], "ipv6"),
    "yellow",
  );
});
test("empty ICE result stays unknown rather than claiming leak-free", () => {
  assert.equal(
    level(
      [
        section([
          f("http", http("8.8.8.8")),
          f("ice", { publicIPs: [], completed: true }),
        ]),
      ],
      "webrtc",
    ),
    "unknown",
  );
});
test("security classification requires positive flags and language without region stays unknown", () => {
  const identity = http("8.8.8.8");
  identity.enrichment = { security: { is_vpn: true }, country_code: "US" };
  assert.equal(
    level([section([f("http", identity), f("language", "en")])], "vpn"),
    "yellow",
  );
  assert.equal(
    level([section([f("http", identity), f("language", "en")])], "language"),
    "unknown",
  );
});
test("fingerprint stable under object ordering, timestamps, IP and measurement changes", async () => {
  const first = [
    section([
      f("canvasHash", "abc"),
      f("uaHigh", { b: 2, a: 1 }),
      f("ip", "8.8.8.8"),
      f("localTime", "today"),
    ]),
  ];
  const second = [
    section([
      f("localTime", "tomorrow"),
      f("ip", "1.1.1.1"),
      f("uaHigh", { a: 1, b: 2 }),
      f("canvasHash", "abc"),
    ]),
  ];
  assert.equal(
    await combinedFingerprint(first),
    await combinedFingerprint(second),
  );
  assert.notEqual(
    await combinedFingerprint(first),
    await combinedFingerprint([
      section([f("canvasHash", "xyz"), f("uaHigh", { a: 1, b: 2 })]),
    ]),
  );
});
test("private, loopback, link-local and CGNAT addresses are not public", () => {
  for (const ip of [
    "127.0.0.1",
    "10.1.2.3",
    "192.168.0.1",
    "172.16.0.1",
    "169.254.0.1",
    "100.64.0.1",
    "::1",
    "fc00::1",
    "fe80::1",
  ])
    assert.equal(isPublicIP(ip), false, ip);
  for (const ip of ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111"])
    assert.equal(isPublicIP(ip), true, ip);
  assert.equal(
    normalizeIP("2001:4860:4860:0:0:0:0:8888"),
    "2001:4860:4860::8888",
  );
});
test("malformed addresses cannot become public identities", () => {
  for (const ip of ["invalid:address", "999.1.1.1", "not-an-ip", ""])
    assert.equal(isPublicIP(ip), false, ip);
});

test("documentation ranges are excluded without excluding adjacent public networks", () => {
  for (const ip of ["192.0.2.1", "198.51.100.1", "203.0.113.1"]) assert.equal(isPublicIP(ip), false);
  for (const ip of ["192.0.3.1", "192.2.1.1", "198.51.101.1"]) assert.equal(isPublicIP(ip), true);
});
