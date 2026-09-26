// Writes the NRRD fixtures in this folder and reads each with three.js
// 0.180's NRRDLoader, into nrrd.json. Run it where `three` is installed.
import { writeFileSync } from 'node:fs';
import * as fflate from 'three/examples/jsm/libs/fflate.module.js';
import { NRRDLoader } from 'three/examples/jsm/loaders/NRRDLoader.js';

const files = {};
const ascii = ( text ) => Buffer.from( text, 'latin1' );

// Raw bytes in left-posterior-superior space with directions. three.js
// drops the header's last character, here the `)` of the origin.
files[ 'raw.nrrd' ] = Buffer.concat( [
	ascii( 'NRRD0004\n# a comment: not a field\ntype: uint8\ndimension: 3\nspace: left-posterior-superior\nsizes: 3 2 2\nspace directions: (0,0.5,0) (2,0,0) (0,0,1.5)\nkinds: domain domain domain\nendian: little\nencoding: raw\nspace origin: (1,2,3)\n\n' ),
	Buffer.from( [ 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 200, 255 ] ),
] );

// gzip floats with spacings and no directions. `encoding: gzip` loses its
// `p` and still starts with `gz`.
{
	const floats = new Float32Array( [ 0.5, - 1.25, 3, Number.NaN, 8, 2.5, - 7, 1 ] );
	files[ 'gzip.nrrd' ] = Buffer.concat( [
		ascii( 'NRRD0004\ntype: float\ndimension: 3\nspace: left-anterior-superior\nsizes: 2 2 2\nspacings: 0.5 2 NaN\nendian: big\nencoding: gzip\n\n' ),
		Buffer.from( fflate.gzipSync( new Uint8Array( floats.buffer ), { mtime: 0 } ) ),
	] );
}

// Text, a value per word, with more words than the sizes hold.
files[ 'ascii.nrrd' ] = ascii( 'NRRD0004\ntype: short\ndimension: 3\nsizes: 2 2 1\nspace directions: (1,0,0) (0,1,0) (0,0,1)\nencoding: ascii\nendian: little\n\n1 -2\t3\n40000 \xa05 6\n' );

// Hexadecimal unsigned ints, with and without a 0x.
files[ 'hex.nrrd' ] = ascii( 'NRRD0004\ntype: uint\ndimension: 3\nsizes: 2 1 2\nspace directions: (0,0,2) (0,3,0) (4,0,0)\nencoding: hex\nendian: little\n\nff 0x10 -1 zz' );

// `encoding: raw` as the last line reads `ra`, which three.js does not
// know, so the volume is the whole file, header and all.
files[ 'whole.nrrd' ] = Buffer.concat( [
	ascii( 'NRRD0004\ntype: uchar\nsizes: 4 4 4\nencoding: raw\n\n' ),
	Buffer.from( [ 1, 2, 3 ] ),
] );

const reference = {};
for ( const [ name, bytes ] of Object.entries( files ) ) {
	writeFileSync( name, bytes );
	const buffer = bytes.buffer.slice( bytes.byteOffset, bytes.byteOffset + bytes.length );
	const v = new NRRDLoader().parse( buffer );
	const h = v.header;
	reference[ name ] = {
		data: Array.from( v.data, ( x ) => Number.isNaN( x ) ? 'NaN' : x ),
		dimensions: v.dimensions.map( ( x ) => x === undefined || Number.isNaN( x ) ? 'NaN' : x ),
		axisOrder: Array.from( { length: 3 }, ( _, i ) => v.axisOrder[ i ] ?? '' ),
		spacing: v.spacing,
		matrix: v.matrix.elements,
		inverseMatrix: v.inverseMatrix.elements,
		RASDimensions: v.RASDimensions.map( ( x ) => Number.isNaN( x ) ? 'NaN' : x ),
		min: v.min, max: v.max,
		header: {
			type: h.type, encoding: h.encoding, endian: h.endian ?? '', space: h.space ?? '',
			dim: h.dim ?? 'NaN', sizes: h.sizes.map( ( x ) => Number.isNaN( x ) ? 'NaN' : x ),
			space_origin: h.space_origin ?? [], kinds: h.kinds ?? '',
		},
	};
}
writeFileSync( 'nrrd.json', JSON.stringify( reference ) );
