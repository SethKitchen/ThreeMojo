// Reads each TIFF in this folder with three.js 0.180's TIFFLoader, into
// tiff.json. Run it where `three` is installed, after make_tiff.py. UTIF
// reads `window.UDOC` for CMYK, so Node needs a `window` without one.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { TIFFLoader } from 'three/examples/jsm/loaders/TIFFLoader.js';

globalThis.window = {};
const reference = {};
for ( const name of readdirSync( '.' ).filter( ( n ) => n.endsWith( '.tif' ) ).sort() ) {
	const bytes = readFileSync( name );
	const buffer = bytes.buffer.slice( bytes.byteOffset, bytes.byteOffset + bytes.length );
	try {
		const tiff = new TIFFLoader().parse( buffer );
		reference[ name ] = { width: tiff.width, height: tiff.height, data: Array.from( tiff.data ) };
	} catch ( e ) {
		reference[ name ] = { error: String( e ) };
	}
}
writeFileSync( 'tiff.json', JSON.stringify( reference ) );
