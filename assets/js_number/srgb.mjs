// Print three.js's SRGBToLinear of each byte over 255, as V8 computes it,
// as the hex of each double, for the table `_SRGB_TO_LINEAR` in `loaders/js_number.mojo`.
const THREE = await import('three');
const buf = new DataView(new ArrayBuffer(8));
const out = [];
for (let b = 0; b < 256; b++) {
  const color = new THREE.Color().setHex(b << 16);
  buf.setFloat64(0, color.r);
  out.push('0x' + buf.getBigUint64(0).toString(16).toUpperCase().padStart(16, '0'));
}
let text = '';
for (let i = 0; i < out.length; i += 3) text += '    ' + out.slice(i, i + 3).join(', ') + ',\n';
console.log(text);
