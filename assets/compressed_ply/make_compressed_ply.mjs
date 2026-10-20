// Writes the compressed PLY test files here with PlayCanvas splat-transform
// 3.10.1, and reads each one back with the same tool into a PLY file. The
// reader in extensions/scan/compressed_ply.mojo must make the same splats
// from the compressed files as the splat PLY reader makes from the PLY
// files.
//
// Run it where `@playcanvas/splat-transform` 3.10.1 is installed, with the
// output directory as its one argument:
//
//     node make_compressed_ply.mjs assets/compressed_ply
//
// SPLAT_TRANSFORM names the command when it is not in node_modules/.bin.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const out = process.argv[ 2 ] || '.';
const tool = process.env.SPLAT_TRANSFORM || join( 'node_modules', '.bin', 'splat-transform' );

// A small linear congruential generator, so the inputs are the same on
// every run.
let state = 20261021;
function random() {

	state = ( Math.imul( state, 1664525 ) + 1013904223 ) >>> 0;
	return state / 4294967296;

}

function between( low, high ) {

	return low + ( high - low ) * random();

}

// A binary little-endian splat PLY, as the 3DGS training code writes it.
// The opacities stay inside the alpha bytes 1 to 254: splat-transform
// writes 0 and 255 back as infinite logits, which a splat PLY cannot hold.
function writePly( path, splats, degree ) {

	const rest = [ 0, 9, 24, 45 ][ degree ];
	const names = [ 'x', 'y', 'z', 'f_dc_0', 'f_dc_1', 'f_dc_2' ];
	for ( let i = 0; i < rest; i ++ ) names.push( `f_rest_${i}` );
	names.push( 'opacity', 'scale_0', 'scale_1', 'scale_2', 'rot_0', 'rot_1', 'rot_2', 'rot_3' );
	const header = [ 'ply', 'format binary_little_endian 1.0', `element vertex ${splats}` ];
	for ( const name of names ) header.push( `property float ${name}` );
	header.push( 'end_header', '' );
	const head = Buffer.from( header.join( '\n' ), 'ascii' );
	const body = Buffer.alloc( splats * names.length * 4 );
	let at = 0;
	const put = ( value ) => {

		body.writeFloatLE( value, at );
		at += 4;

	};

	for ( let s = 0; s < splats; s ++ ) {

		put( between( - 6, 6 ) );
		put( between( - 0.5, 9 ) );
		put( between( - 3, 3 ) );
		for ( let i = 0; i < 3; i ++ ) put( between( - 1.5, 1.5 ) );
		for ( let i = 0; i < rest; i ++ ) put( between( - 0.6, 0.6 ) );
		put( between( - 5, 5.5 ) );
		for ( let i = 0; i < 3; i ++ ) put( between( - 7, - 0.5 ) );
		// Each of the four components is the largest in turn, with both
		// signs, so every rotation tag is written.
		const q = [ between( - 0.4, 0.4 ), between( - 0.4, 0.4 ), between( - 0.4, 0.4 ), between( - 0.4, 0.4 ) ];
		q[ s % 4 ] = ( s % 8 < 4 ? 1 : - 1 ) * between( 0.6, 1 );
		for ( const value of q ) put( value );

	}

	writeFileSync( path, Buffer.concat( [ head, body ] ) );

}

// The same file without the chunks' color bounds: 12 chunk properties, as
// SuperSplat wrote before it added them.
function dropChunkColors( from, to ) {

	const bytes = readFileSync( from );
	const marker = Buffer.from( '\nend_header\n', 'ascii' );
	const end = bytes.indexOf( marker ) + marker.length;
	const lines = bytes.subarray( 0, end ).toString( 'ascii' ).split( '\n' );
	const chunks = Number( lines.find( ( line ) => line.startsWith( 'element chunk ' ) ).split( ' ' )[ 2 ] );
	const colors = [ 'min_r', 'min_g', 'min_b', 'max_r', 'max_g', 'max_b' ];
	const kept = lines.filter( ( line ) => ! colors.some( ( name ) => line === `property float ${name}` ) );
	const parts = [ Buffer.from( kept.join( '\n' ), 'ascii' ) ];
	for ( let c = 0; c < chunks; c ++ ) {

		parts.push( bytes.subarray( end + c * 72, end + c * 72 + 48 ) );

	}

	parts.push( bytes.subarray( end + chunks * 72 ) );
	writeFileSync( to, Buffer.concat( parts ) );

}

function run( ...args ) {

	execFileSync( tool, [ '-q', '-w', '-g', 'cpu', '--max-workers', '0', ...args ], { stdio: 'inherit' } );

}

// Degree 3 over three chunks, the last one partly full; degree 2 and 1 in
// one chunk; degree 0 with no sh element. The degree 1 file is also written
// without chunk colors.
const cases = [
	{ name: 'sh3', splats: 600, degree: 3 },
	{ name: 'sh2', splats: 40, degree: 2 },
	{ name: 'sh1', splats: 30, degree: 1 },
	{ name: 'sh0', splats: 9, degree: 0 },
];

const work = join( out, 'work' );
mkdirSync( work, { recursive: true } );
for ( const item of cases ) {

	const input = join( work, `${item.name}.ply` );
	writePly( input, item.splats, item.degree );
	const packed = join( out, `${item.name}.compressed.ply` );
	run( input, packed );
	run( packed, join( out, `${item.name}_restored.ply` ) );

}

dropChunkColors( join( out, 'sh1.compressed.ply' ), join( out, 'untinted.compressed.ply' ) );
run( join( out, 'untinted.compressed.ply' ), join( out, 'untinted_restored.ply' ) );

rmSync( work, { recursive: true, force: true } );
