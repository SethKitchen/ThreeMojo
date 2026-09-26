// Reads each font in this folder with three.js 0.180's TTFLoader, into
// ttf.json, plain and with `reversed` set. Run it where `three` is
// installed, after make_fonts.py.
import { readFileSync, writeFileSync } from 'node:fs';
import { TTFLoader } from 'three/examples/jsm/loaders/TTFLoader.js';

const reference = {};
for ( const name of [ 'curves.ttf', 'astral.ttf', 'kenpixel.ttf', 'edges.ttf', 'bare.ttf', 'zero.ttf' ] ) {
	for ( const reversed of [ false, true ] ) {
		const bytes = readFileSync( name );
		const buffer = bytes.buffer.slice( bytes.byteOffset, bytes.byteOffset + bytes.length );
		const loader = new TTFLoader();
		loader.reversed = reversed;
		const json = loader.parse( buffer );
		delete json.original_font_information;
		// A Mojo string cannot hold a lone surrogate: the port writes U+FFFD.
		if ( json.familyName ) json.familyName = json.familyName.toWellFormed();
		reference[ name + ( reversed ? ' reversed' : '' ) ] = JSON.parse( JSON.stringify( json ) );
	}
}
writeFileSync( 'ttf.json', JSON.stringify( reference ) );
