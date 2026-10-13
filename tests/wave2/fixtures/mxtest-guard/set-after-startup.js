#!/usr/bin/env node
// set-after-startup.js — fixture helper: re-encode a captured Mendix settings unit (BSON) with
// AfterStartupMicroflow = <value>, every enclosing length rewritten. Re-encoding with the original
// value ('') reproduces the capture byte for byte (checked by test-mxtest-guard.sh).
const fs = require('fs');
const [inp, out, value] = process.argv.slice(2);
const buf = fs.readFileSync(inp);
function cstr(b, o) { const e = b.indexOf(0, o); return [b.toString('utf8', o, e), e + 1]; }
function size(t, b, o) {
  switch (t) {
    case 0x01: case 0x09: case 0x11: case 0x12: return 8;
    case 0x02: case 0x0d: case 0x0e: return 4 + b.readInt32LE(o);
    case 0x03: case 0x04: return b.readInt32LE(o);
    case 0x05: return 5 + b.readInt32LE(o);
    case 0x07: return 12; case 0x08: return 1; case 0x0a: case 0x06: case 0x7f: case 0xff: return 0;
    case 0x10: return 4; case 0x13: return 16;
    default: throw new Error('unknown BSON type 0x' + t.toString(16) + ' at ' + o);
  }
}
function enc(b, o) {  // re-encode document at o, rewriting the target
  const len = b.readInt32LE(o), end = o + len - 1; let p = o + 4; const parts = [];
  while (p < end) {
    const t = b[p]; const [k, vo] = cstr(b, p + 1); const n = size(t, b, vo);
    let val = b.subarray(vo, vo + n);
    if (t === 0x03 || t === 0x04) val = enc(b, vo);
    else if (t === 0x02 && k === 'AfterStartupMicroflow') {
      const s = Buffer.from(value + '\0', 'utf8'); const l = Buffer.alloc(4); l.writeInt32LE(s.length); val = Buffer.concat([l, s]);
    }
    parts.push(b.subarray(p, vo), val); p = vo + n;
  }
  const body = Buffer.concat(parts); const h = Buffer.alloc(4); h.writeInt32LE(body.length + 5);
  return Buffer.concat([h, body, Buffer.from([0])]);
}
fs.writeFileSync(out, enc(buf, 0));
