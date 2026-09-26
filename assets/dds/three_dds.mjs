// Writes uncompressed DDS fixtures in this folder and reads each with
// three.js 0.180's DDSLoader, into dds.json. Run it where `three` is
// installed.
import { writeFileSync } from 'node:fs';
import { DDSLoader } from 'three/examples/jsm/loaders/DDSLoader.js';

function header( width, height, levels, bits, masks ) {
	const h = new Uint32Array( 32 );
	h[ 0 ] = 0x20534444; // 'DDS '
	h[ 1 ] = 124;
	h[ 2 ] = 0x1007 | ( levels > 1 ? 0x20000 : 0 );
	h[ 3 ] = height;
	h[ 4 ] = width;
	h[ 7 ] = levels;
	h[ 19 ] = 32;
	h[ 20 ] = 0x41; // DDPF_RGB | DDPF_ALPHAPIXELS
	h[ 22 ] = bits;
	h[ 23 ] = masks[ 0 ]; h[ 24 ] = masks[ 1 ]; h[ 25 ] = masks[ 2 ]; h[ 26 ] = masks[ 3 ];
	return Buffer.from( h.buffer );
}

function bytes( count, seed ) {
	return Buffer.from( Array.from( { length: count }, ( _, i ) => ( i * 37 + seed ) & 255 ) );
}

const files = {
	// BGRA, a 4 by 2 level and a 2 by 1 level.
	'bgra.dds': Buffer.concat( [
		header( 4, 2, 2, 32, [ 0xff0000, 0xff00, 0xff, 0xff000000 ] ),
		bytes( 4 * 2 * 4, 1 ), bytes( 2 * 1 * 4, 9 ),
	] ),
	// BGR, 3 by 2, with masks that only overlap their bytes.
	'bgr.dds': Buffer.concat( [
		header( 3, 2, 1, 24, [ 0x010000, 0x0100, 0x01, 0 ] ),
		bytes( 3 * 2 * 3, 5 ),
	] ),
};

const reference = {};
for ( const [ name, file ] of Object.entries( files ) ) {
	writeFileSync( name, file );
	const buffer = file.buffer.slice( file.byteOffset, file.byteOffset + file.length );
	const dds = new DDSLoader().parse( buffer, true );
	reference[ name ] = {
		width: dds.width, height: dds.height, format: dds.format, mipmapCount: dds.mipmapCount,
		mipmaps: dds.mipmaps.map( ( m ) => ( { width: m.width, height: m.height, data: Array.from( m.data ) } ) ),
	};
}
writeFileSync( 'dds.json', JSON.stringify( reference ) );
