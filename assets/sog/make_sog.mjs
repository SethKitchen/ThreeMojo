// Writes the SOG test files here with PlayCanvas splat-transform 3.10.1,
// and reads each one back with the same tool into a PLY file. The SOG
// reader in extensions/scan/sog.mojo must make the same splats from the
// SOG files as the splat PLY reader makes from the PLY files.
//
// Run it where `@playcanvas/splat-transform` 3.10.1 is installed, with the
// output directory as its one argument:
//
//     node make_sog.mjs assets/sog
//
// SPLAT_TRANSFORM names the command when it is not in node_modules/.bin.
import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const out = process.argv[ 2 ] || '.';
const tool = process.env.SPLAT_TRANSFORM || join( 'node_modules', '.bin', 'splat-transform' );

// A small linear congruential generator, so the inputs are the same on
// every run.
let state = 20261020;
function random() {

	state = ( Math.imul( state, 1664525 ) + 1013904223 ) >>> 0;
	return state / 4294967296;

}

function between( low, high ) {

	return low + ( high - low ) * random();

}

// A binary little-endian splat PLY, as the 3DGS training code writes it.
function writePly( path, splats, degree, flatZ ) {

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
		put( flatZ ? 1.25 : between( - 3, 3 ) );
		for ( let i = 0; i < 3; i ++ ) put( between( - 1.5, 1.5 ) );
		for ( let i = 0; i < rest; i ++ ) put( between( - 0.9, 0.9 ) );
		put( between( - 5, 7 ) );
		for ( let i = 0; i < 3; i ++ ) put( between( - 7, - 0.5 ) );
		// Each of the four components is the largest in turn, with both
		// signs, so every quaternion tag is written.
		const q = [ between( - 0.4, 0.4 ), between( - 0.4, 0.4 ), between( - 0.4, 0.4 ), between( - 0.4, 0.4 ) ];
		q[ s % 4 ] = ( s % 8 < 4 ? 1 : - 1 ) * between( 0.6, 1 );
		for ( const value of q ) put( value );

	}

	writeFileSync( path, Buffer.concat( [ head, body ] ) );

}

function run( ...args ) {

	execFileSync( tool, [ '-q', '-w', '-g', 'cpu', '--max-workers', '0', ...args ], { stdio: 'inherit' } );

}

// Degree 3 as files beside a meta.json and as one bundle, degree 1 and 2
// as bundles, and degree 0 with every z the same, so one axis has no range.
const cases = [
	{ name: 'sh3', splats: 300, degree: 3, flatZ: false, folder: true },
	{ name: 'sh2', splats: 40, degree: 2, flatZ: false, folder: false },
	{ name: 'sh1', splats: 30, degree: 1, flatZ: false, folder: false },
	{ name: 'flat', splats: 9, degree: 0, flatZ: true, folder: true },
];

const work = join( out, 'work' );
mkdirSync( work, { recursive: true } );
for ( const item of cases ) {

	const input = join( work, `${item.name}.ply` );
	writePly( input, item.splats, item.degree, item.flatZ );
	const bundle = join( out, `${item.name}.sog` );
	run( input, bundle );
	run( bundle, join( out, `${item.name}_restored.ply` ) );
	if ( item.folder ) {

		const folder = join( out, item.name );
		rmSync( folder, { recursive: true, force: true } );
		mkdirSync( folder );
		// The palette's k-means starts at random, so these files are read
		// back on their own.
		run( input, join( folder, 'meta.json' ) );
		run( join( folder, 'meta.json' ), join( out, `${item.name}_folder_restored.ply` ) );

	}

}

rmSync( work, { recursive: true, force: true } );
