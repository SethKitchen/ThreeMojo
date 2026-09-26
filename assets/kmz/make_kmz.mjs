// Writes assets/kmz/model.kmz with the fflate that three.js 0.180 ships:
// a doc.kml in the KML namespace that names models/tri.dae, the model, and
// the brick texture the model names as `brick.png`. Run it where `three` is
// installed, with ../brick.png beside this folder.
import { readFileSync, writeFileSync } from 'node:fs';
import * as fflate from 'three/examples/jsm/libs/fflate.module.js';

const dae = readFileSync( 'tri.dae' );
const kml = `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document><Placemark><name>tri</name><Model>
<Link><href>models/tri.dae</href></Link>
</Model></Placemark></Document>
</kml>
`;
writeFileSync( 'model.kmz', fflate.zipSync( {
	'doc.kml': fflate.strToU8( kml ),
	'models/tri.dae': new Uint8Array( dae ),
	'images/brick.png': new Uint8Array( readFileSync( '../brick.png' ) ),
}, { mtime: new Date( '2026-01-01T00:00:00Z' ) } ) );
