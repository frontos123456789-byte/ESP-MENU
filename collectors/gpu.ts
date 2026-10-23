import type { Collector } from "@/lib/types";
import { probe, hash, timeout } from "./utils";
export function glSnapshot(version: 1 | 2) {
  const canvas = document.createElement("canvas");
  canvas.width = 256;
  canvas.height = 128;
  const gl = canvas.getContext(version === 2 ? "webgl2" : "webgl", {
    preserveDrawingBuffer: true,
  }) as WebGLRenderingContext | WebGL2RenderingContext | null;
  if (!gl) return null;
  try {
    const debug = gl.getExtension("WEBGL_debug_renderer_info");
    const params: Record<string, unknown> = {};
    for (const k of [
      "MAX_TEXTURE_SIZE",
      "MAX_CUBE_MAP_TEXTURE_SIZE",
      "MAX_RENDERBUFFER_SIZE",
      "MAX_VERTEX_ATTRIBS",
      "MAX_VERTEX_UNIFORM_VECTORS",
      "MAX_VARYING_VECTORS",
      "MAX_FRAGMENT_UNIFORM_VECTORS",
      "MAX_TEXTURE_IMAGE_UNITS",
      "MAX_VIEWPORT_DIMS",
      "ALIASED_LINE_WIDTH_RANGE",
      "ALIASED_POINT_SIZE_RANGE",
      "SHADING_LANGUAGE_VERSION",
      "VERSION",
    ]) {
      try {
        const val = gl.getParameter(
          (gl as unknown as Record<string, number>)[k],
        );
        params[k] = ArrayBuffer.isView(val)
          ? Array.from(val as unknown as number[])
          : val;
      } catch {
        params[k] = null;
      }
    }
    return {
      vendor: gl.getParameter(gl.VENDOR),
      renderer: gl.getParameter(gl.RENDERER),
      unmaskedVendor: debug
        ? gl.getParameter(debug.UNMASKED_VENDOR_WEBGL)
        : null,
      unmaskedRenderer: debug
        ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL)
        : null,
      parameters: params,
      extensions: gl.getSupportedExtensions(),
    };
  } finally {
    gl.getExtension("WEBGL_lose_context")?.loseContext();
  }
}
export async function renderGLHash() {
  const c = document.createElement("canvas");
  c.width = 256;
  c.height = 128;
  const gl = c.getContext("webgl", { preserveDrawingBuffer: true });
  if (!gl) return null;
  try {
    const program = gl.createProgram()!;
    for (const [type, source] of [
      [
        gl.VERTEX_SHADER,
        "attribute vec2 p; varying vec2 v; void main(){v=p;gl_Position=vec4(p,0.,1.);}",
      ],
      [
        gl.FRAGMENT_SHADER,
        "precision mediump float; varying vec2 v; void main(){gl_FragColor=vec4(sin(v.x*13.)*.5+.5,cos(v.y*7.)*.5+.5,v.x*v.y,1.);}",
      ],
    ] as const) {
      const s = gl.createShader(type)!;
      gl.shaderSource(s, source);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS))
        throw new Error("Shader unavailable");
      gl.attachShader(program, s);
    }
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS))
      throw new Error("Link failed");
    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-0.9, -0.8, 0.9, -0.7, -0.1, 0.9]),
      gl.STATIC_DRAW,
    );
    const p = gl.getAttribLocation(program, "p");
    gl.enableVertexAttribArray(p);
    gl.vertexAttribPointer(p, 2, gl.FLOAT, false, 0, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    const pixels = new Uint8Array(256 * 128 * 4);
    gl.readPixels(0, 0, 256, 128, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    return await hash(pixels.buffer);
  } finally {
    gl.getExtension("WEBGL_lose_context")?.loseContext();
  }
}
export const gpu: Collector = async () =>
  Promise.all([
    probe(
      "webgl",
      "WebGL",
      () => glSnapshot(1),
      "high",
      "Модель GPU и драйвер помогают идентифицировать устройство.",
    ),
    probe("webgl2", "WebGL 2", () => glSnapshot(2), "high"),
    probe(
      "webgpu",
      "WebGPU adapter",
      async () => {
        const api = (
          navigator as Navigator & {
            gpu?: {
              requestAdapter: () => Promise<{
                info?: unknown;
                features: Set<string>;
              } | null>;
            };
          }
        ).gpu;
        if (!api) return null;
        const a = await timeout(api.requestAdapter());
        return a
          ? { info: a.info || null, features: Array.from(a.features) }
          : null;
      },
      "high",
    ),
  ]);
