#!/usr/bin/env node
/**
 * Turns the hand-drawn logo frames into a Swift source file.
 *
 *   node Scripts/make-mark-frames.mjs
 *   node Scripts/make-mark-frames.mjs --verify   # writes an HTML proof sheet
 *
 * Sources are `logo_svgs/frame*.svg` — the same files the marketing site plays as
 * stop motion. This flattens them into something a small Swift parser can read
 * without SwiftUI needing to understand SVG at all.
 *
 * ## What "flatten" means here
 *
 * The files use the whole vocabulary an illustration tool reaches for: nested
 * layer groups, `transform` on those groups, `rect` and `circle` alongside `path`,
 * relative path commands, `H`/`V` shorthands, and layers hidden with
 * `display:none`. None of that is worth reimplementing in Swift.
 *
 * So everything is resolved here, in a browser, which already knows these rules:
 *
 *   - hidden layers are dropped (checking ancestors, since `display` does not
 *     inherit and a shape inside a hidden layer still reports itself visible)
 *   - `rect` and `circle` become paths
 *   - every ancestor transform is composed with the shape's own and baked into
 *     the coordinates, because the movement in this sequence lives in
 *     `translate()` on the layer groups rather than in new path data
 *   - commands are made absolute and reduced to four: M, L, C, Z
 *
 * What Swift receives is a list of frames, each a list of layers, each a string of
 * those four commands. The parser for that is about thirty lines.
 *
 * ## Punch layers
 *
 * Shapes filled `#4d4d4d` in the sources are not meant to be seen. They hide part
 * of what was drawn before them — that is how the mail disappears into the box.
 * They are marked `punches` here and the view erases with them rather than
 * painting them, so the mark carries no background colour and sits on anything.
 *
 * Order matters: such a shape hides what precedes it and nothing after, so a layer
 * marked `punches` applies to the layers already drawn and not to the ones that
 * follow.
 */

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(root, 'logo_svgs');
const OUT = join(
  root,
  'Packages/Carpenter/Sources/CarpenterUI/Components/MarkFrames.swift'
);
const TMP = join(root, '.mark-frames-extract.html');
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const files = readdirSync(SRC)
  .filter((f) => /^frame\d+\.svg$/.test(f))
  .sort((a, b) => parseInt(a.match(/\d+/)[0], 10) - parseInt(b.match(/\d+/)[0], 10));

if (!files.length) throw new Error(`No frame*.svg in ${SRC}`);

/** The browser does the resolving; this is the script it runs. */
const EXTRACTOR = `
const root = document.querySelector('#host svg');
root.querySelectorAll('defs,metadata').forEach((n) => n.remove());
[...root.querySelectorAll('*')].forEach((n) => { if (n.tagName.includes(':')) n.remove(); });

const BACKGROUND = 'rgb(77, 77, 77)';
const NUM = /[-+]?(?:\\d*\\.\\d+|\\d+\\.?)(?:[eE][-+]?\\d+)?/g;
const R = (n) => Math.round(n * 1000) / 1000;

function hidden(n) {
  for (let p = n; p && p !== root.parentElement; p = p.parentElement) {
    if (getComputedStyle(p).display === 'none') return true;
  }
  return false;
}

/* SVG transform lists, composed by hand.
   DOMMatrix looks like the tool for this and is not: it parses CSS transform
   syntax, where a translate needs a unit. SVG writes translate(10), which CSS
   rejects, so the constructor throws on the very files this exists to read. */
const I = [1, 0, 0, 1, 0, 0];
const mul = (m, n) => [
  m[0] * n[0] + m[2] * n[1],
  m[1] * n[0] + m[3] * n[1],
  m[0] * n[2] + m[2] * n[3],
  m[1] * n[2] + m[3] * n[3],
  m[0] * n[4] + m[2] * n[5] + m[4],
  m[1] * n[4] + m[3] * n[5] + m[5],
];
const apply = (m, x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];

function parseTransform(text) {
  let m = I;
  const re = /(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/g;
  let hit;
  while ((hit = re.exec(text))) {
    const a = (hit[2].match(NUM) || []).map(Number);
    const rad = (d) => (d * Math.PI) / 180;
    let step;
    switch (hit[1]) {
      case 'matrix': step = a.slice(0, 6); break;
      case 'translate': step = [1, 0, 0, 1, a[0] || 0, a[1] || 0]; break;
      case 'scale': step = [a[0] ?? 1, 0, 0, a[1] ?? a[0] ?? 1, 0, 0]; break;
      case 'skewX': step = [1, 0, Math.tan(rad(a[0] || 0)), 1, 0, 0]; break;
      case 'skewY': step = [1, Math.tan(rad(a[0] || 0)), 0, 1, 0, 0]; break;
      case 'rotate': {
        const c = Math.cos(rad(a[0] || 0));
        const s = Math.sin(rad(a[0] || 0));
        const r = [c, s, -s, c, 0, 0];
        // rotate(deg cx cy) turns about a point rather than the origin.
        step = a.length > 1
          ? mul(mul([1, 0, 0, 1, a[1], a[2]], r), [1, 0, 0, 1, -a[1], -a[2]])
          : r;
        break;
      }
      default: step = I;
    }
    m = mul(m, step);
  }
  return m;
}

/* Own transform last, ancestors outermost-first — the order they apply in. */
function matrixFor(n) {
  const parts = [];
  for (let p = n; p && p !== root.parentElement; p = p.parentElement) {
    const t = p.getAttribute && p.getAttribute('transform');
    if (t) parts.unshift(t);
  }
  return parseTransform(parts.join(' '));
}

/** Circle as four cubics. 0.5522847498 is the usual circle-to-bezier constant. */
function circlePath(cx, cy, r) {
  const k = r * 0.5522847498;
  return [
    ['M', cx, cy - r],
    ['C', cx + k, cy - r, cx + r, cy - k, cx + r, cy],
    ['C', cx + r, cy + k, cx + k, cy + r, cx, cy + r],
    ['C', cx - k, cy + r, cx - r, cy + k, cx - r, cy],
    ['C', cx - r, cy - k, cx - k, cy - r, cx, cy - r],
    ['Z'],
  ];
}

const ARGS = { M: 2, L: 2, H: 1, V: 1, C: 6, A: 7, Z: 0 };

/* Elliptical arc to cubics, per the SVG spec's F.6.5 conversion.
   Arcs cannot be expressed as beziers exactly, so each is split into sweeps of at
   most 90 degrees and approximated; at logo scale the error is far below a pixel.
   Doing it here is what keeps the Swift parser down to four commands. */
function arcToCubics(x1, y1, rx, ry, deg, large, sweep, x2, y2) {
  if (!rx || !ry) return [['L', x2, y2]];
  const phi = (deg * Math.PI) / 180;
  const cp = Math.cos(phi), sp = Math.sin(phi);
  const dx = (x1 - x2) / 2, dy = (y1 - y2) / 2;
  const ux = cp * dx + sp * dy, uy = -sp * dx + cp * dy;

  rx = Math.abs(rx); ry = Math.abs(ry);
  // A radius too small to reach the endpoint is scaled up until it just does.
  const lambda = (ux * ux) / (rx * rx) + (uy * uy) / (ry * ry);
  if (lambda > 1) { const k = Math.sqrt(lambda); rx *= k; ry *= k; }

  const rx2 = rx * rx, ry2 = ry * ry;
  const num = rx2 * ry2 - rx2 * uy * uy - ry2 * ux * ux;
  const den = rx2 * uy * uy + ry2 * ux * ux;
  const coef = (large !== sweep ? 1 : -1) * Math.sqrt(Math.max(0, num / den));
  const cxp = (coef * rx * uy) / ry, cyp = (-coef * ry * ux) / rx;
  const cx = cp * cxp - sp * cyp + (x1 + x2) / 2;
  const cy = sp * cxp + cp * cyp + (y1 + y2) / 2;

  const ang = (vx, vy, wx, wy) => {
    const d = (vx * wx + vy * wy) / (Math.hypot(vx, vy) * Math.hypot(wx, wy));
    const a = Math.acos(Math.min(1, Math.max(-1, d)));
    return vx * wy - vy * wx < 0 ? -a : a;
  };
  const sx = (ux - cxp) / rx, sy = (uy - cyp) / ry;
  const ex = (-ux - cxp) / rx, ey = (-uy - cyp) / ry;
  let t1 = ang(1, 0, sx, sy);
  let dt = ang(sx, sy, ex, ey);
  if (!sweep && dt > 0) dt -= 2 * Math.PI;
  if (sweep && dt < 0) dt += 2 * Math.PI;

  const at = (t) => [
    cx + rx * cp * Math.cos(t) - ry * sp * Math.sin(t),
    cy + rx * sp * Math.cos(t) + ry * cp * Math.sin(t),
  ];
  const slope = (t) => [
    -rx * cp * Math.sin(t) - ry * sp * Math.cos(t),
    -rx * sp * Math.sin(t) + ry * cp * Math.cos(t),
  ];

  const steps = Math.max(1, Math.ceil(Math.abs(dt) / (Math.PI / 2)));
  const seg = dt / steps;
  const alpha = (4 / 3) * Math.tan(seg / 4);
  const out = [];
  for (let i = 0; i < steps; i++) {
    const a0 = t1 + i * seg, a1 = a0 + seg;
    const [px, py] = at(a0), [qx, qy] = at(a1);
    const [dpx, dpy] = slope(a0), [dqx, dqy] = slope(a1);
    out.push(['C', px + alpha * dpx, py + alpha * dpy, qx - alpha * dqx, qy - alpha * dqy, qx, qy]);
  }
  return out;
}

/** Path data to absolute [cmd, ...coords] tuples using only M, L, C and Z. */
function parse(d) {
  const out = [];
  let x = 0, y = 0, sx = 0, sy = 0;
  const re = /([MmLlHhVvCcAaZz])([^MmLlHhVvCcAaZz]*)/g;
  let m;
  while ((m = re.exec(d))) {
    const raw = m[1];
    const up = raw.toUpperCase();
    const rel = raw !== up;
    const nums = (m[2].match(NUM) || []).map(Number);
    const step = ARGS[up];
    if (step === 0) { out.push(['Z']); x = sx; y = sy; continue; }
    for (let i = 0; i < nums.length; i += step) {
      let cmd = i === 0 ? up : up === 'M' ? 'L' : up;
      const a = nums.slice(i, i + step);
      if (cmd === 'H') { x = rel ? x + a[0] : a[0]; out.push(['L', x, y]); continue; }
      if (cmd === 'V') { y = rel ? y + a[0] : a[0]; out.push(['L', x, y]); continue; }
      if (cmd === 'C') {
        const p = rel ? [x + a[0], y + a[1], x + a[2], y + a[3], x + a[4], y + a[5]] : a;
        out.push(['C', ...p]); x = p[4]; y = p[5]; continue;
      }
      if (cmd === 'A') {
        const ex = rel ? x + a[5] : a[5];
        const ey = rel ? y + a[6] : a[6];
        out.push(...arcToCubics(x, y, a[0], a[1], a[2], a[3], a[4], ex, ey));
        x = ex; y = ey; continue;
      }
      const px = rel ? x + a[0] : a[0];
      const py = rel ? y + a[1] : a[1];
      out.push([cmd, px, py]);
      x = px; y = py;
      if (cmd === 'M') { sx = x; sy = y; }
    }
  }
  return out;
}

/* Anything outside the handled set would be consumed as the wrong number of
   coordinates and land somewhere plausible-looking but wrong, which is exactly how
   the arcs in these files went unnoticed. Fail loudly instead. */
function checkCommands(d) {
  const bad = (d.match(/[A-Za-z]/g) || []).filter(
    (c) => !'MmLlHhVvCcAaZzEe'.includes(c)
  );
  if (bad.length) throw new Error('Unhandled path command(s): ' + [...new Set(bad)].join(''));
}

function shapeOps(n) {
  const tag = n.tagName.toLowerCase();
  const f = (a) => parseFloat(n.getAttribute(a) || '0');
  if (tag === 'path') { const d = n.getAttribute('d') || ''; checkCommands(d); return parse(d); }
  if (tag === 'rect') {
    const x = f('x'), y = f('y'), w = f('width'), h = f('height');
    return [['M', x, y], ['L', x + w, y], ['L', x + w, y + h], ['L', x, y + h], ['Z']];
  }
  if (tag === 'circle') return circlePath(f('cx'), f('cy'), f('r'));
  if (tag === 'ellipse') return circlePath(f('cx'), f('cy'), f('rx'));
  return [];
}

const layers = [];
[...root.querySelectorAll('path,rect,circle,ellipse')].forEach((n) => {
  if (hidden(n)) return;
  const punches = getComputedStyle(n).fill === BACKGROUND;
  const mat = matrixFor(n);
  const ops = shapeOps(n).map((op) => {
    if (op[0] === 'Z') return 'Z';
    const nums = [];
    for (let i = 1; i < op.length; i += 2) {
      const [px, py] = apply(mat, op[i], op[i + 1]);
      nums.push(R(px), R(py));
    }
    return op[0] + ' ' + nums.join(' ');
  });
  if (ops.length) layers.push({ punches, path: ops.join(' ') });
});

const pre = document.createElement('pre');
pre.id = 'out';
pre.textContent = JSON.stringify({ viewBox: root.getAttribute('viewBox'), layers });
document.body.appendChild(pre);
`;

function readFrame(file) {
  const svg = readFileSync(join(SRC, file), 'utf8').replace(/<\?xml[^>]*\?>/, '');
  writeFileSync(
    TMP,
    `<!doctype html><meta charset="utf-8"><div id="host">${svg}</div>` +
      `<script>${EXTRACTOR}</scr` + `ipt>`
  );
  const dom = execFileSync(
    CHROME,
    ['--headless', '--disable-gpu', '--dump-dom', `file://${TMP}`],
    { maxBuffer: 1 << 28 }
  ).toString();
  const raw = dom.match(/<pre id="out">([\s\S]*?)<\/pre>/);
  if (!raw) throw new Error(`Extraction produced nothing for ${file}`);
  return JSON.parse(
    raw[1].replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&')
  );
}

const frames = files.map(readFrame);

const boxes = new Set(frames.map((f) => f.viewBox));
if (boxes.size !== 1) {
  throw new Error(`Frames must share one viewBox. Found: ${[...boxes].join(' | ')}`);
}
const [vx, vy, vw, vh] = [...boxes][0].split(/[\s,]+/).map(Number);

/* A proof sheet: the flattened output, drawn back as plain SVG, so it can be
   diffed against the untouched sources. Nothing else verifies that the transforms
   were composed the right way round. */
if (process.argv.includes('--verify')) {
  const tiles = frames
    .map(
      (f) =>
        `<svg viewBox="${vx} ${vy} ${vw} ${vh}">` +
        f.layers
          .map((l) => `<path d="${l.path}" fill="${l.punches ? '#4d4d4d' : '#000'}"/>`)
          .join('') +
        `</svg>`
    )
    .join('');
  writeFileSync(
    join(root, '.mark-frames-verify.html'),
    `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#4d4d4d}` +
      `main{display:grid;grid-template-columns:repeat(${frames.length},1fr)}` +
      `svg{display:block;width:100%}</style><main>${tiles}</main>`
  );
  console.log('verify sheet -> .mark-frames-verify.html');
}

const swiftLayers = (f) =>
  f.layers
    .map((l) => `        Layer(punches: ${l.punches}, path: "${l.path}"),`)
    .join('\n');

const swift = `// Generated by Scripts/make-mark-frames.mjs — do not edit by hand.
// Refresh with: node Scripts/make-mark-frames.mjs
//
// The Outpost mark as ${frames.length} hand-drawn frames, played as stop motion. Sources are
// logo_svgs/frame*.svg, the same files the marketing site uses.
//
// Everything an illustration tool put in those files — nested layer groups and
// their transforms, rects, circles, relative commands, hidden layers — is resolved
// by the generator. What survives is four commands: M, L, C and Z, absolute, in the
// coordinate space below.

import CoreGraphics

/// The drawing data for \`\`AnimatedMark\`\`.
public enum MarkFrames {
    /// One shape, and whether it paints or erases.
    public struct Layer: Sendable {
        /// Erases what earlier layers in the same frame have drawn.
        ///
        /// In the artwork these are shapes filled with the page colour, used to hide
        /// the mail as it slides into the box. Erasing rather than painting is what
        /// lets the mark sit on any background without knowing what it is.
        public let punches: Bool
        /// Absolute path data using only \`M\`, \`L\`, \`C\` and \`Z\`.
        public let path: String

        public init(punches: Bool, path: String) {
            self.punches = punches
            self.path = path
        }
    }

    /// The coordinate space every frame is drawn in.
    public static let viewBox = CGRect(x: ${vx}, y: ${vy}, width: ${vw}, height: ${vh})

    /// The frame the box lands shut on, counting from one — the beat that gets the bounce.
    public static let shutFrame = 5

    /// In order. Held beats are repeated frames, so the count and order are the timing.
    public static let frames: [[Layer]] = [
${frames
  .map((f, i) => `        // Frame ${i + 1}\n        [\n${swiftLayers(f).replace(/^ {8}/gm, '            ')}\n        ],`)
  .join('\n')}
    ]
}
`;

writeFileSync(OUT, swift);
console.log(
  `mark frames: ${frames.length} frames, ` +
    `${frames.reduce((n, f) => n + f.layers.length, 0)} layers, ` +
    `${frames.reduce((n, f) => n + f.layers.filter((l) => l.punches).length, 0)} punches ` +
    `-> ${OUT.replace(root + '/', '')}`
);
