import type { Collector } from "@/lib/types";
import { probe } from "./utils";
import { isPublicIP } from "@/lib/ip";
export const webrtc: Collector = async (signal) => [
  await probe(
    "ice",
    "WebRTC ICE candidates",
    async () => {
      if (!window.RTCPeerConnection) return null;
      const pc = new RTCPeerConnection({
        iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
      });
      const candidates: {
        candidate: string;
        address: string;
        type: string;
        protocol: string;
        scope: string;
      }[] = [];
      let completed = false;
      try {
        await new Promise<void>((resolve, reject) => {
          const finish = () => {
            clearTimeout(timer);
            signal.removeEventListener("abort", abort);
            resolve();
          };
          const abort = () => finish();
          const timer = setTimeout(finish, 5500);
          signal.addEventListener("abort", abort, { once: true });
          pc.onicecandidate = (e) => {
            if (!e.candidate) {
              completed = true;
              finish();
              return;
            }
            const c = e.candidate;
            const address = c.address || c.candidate.split(" ")[4] || "";
            candidates.push({
              candidate: c.candidate,
              address,
              type: c.type || "",
              protocol: c.protocol || "",
              scope: address.endsWith(".local")
                ? "mDNS"
                : isPublicIP(address)
                  ? "public"
                  : "local",
            });
          };
          pc.onicegatheringstatechange = () => {
            if (pc.iceGatheringState === "complete") {
              completed = true;
              finish();
            }
          };
          if (signal.aborted) {
            finish();
            return;
          }
          pc.createDataChannel("privacy-check");
          pc.createOffer()
            .then((o) => pc.setLocalDescription(o))
            .catch((e) => {
              finish();
              reject(e);
            });
        });
        return {
          candidates,
          completed,
          publicIPs: [
            ...new Set(
              candidates
                .filter((c) => c.scope === "public")
                .map((c) => c.address),
            ),
          ],
          localAddresses: [
            ...new Set(
              candidates
                .filter((c) => c.scope !== "public")
                .map((c) => c.address),
            ),
          ],
        };
      } finally {
        pc.onicecandidate = null;
        pc.onicegatheringstatechange = null;
        pc.close();
      }
    },
    "high",
    "STUN-запрос к Google может показать адрес сетевого интерфейса. Камера и микрофон не запрашиваются.",
  ),
];
