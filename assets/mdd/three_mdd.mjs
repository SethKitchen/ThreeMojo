// Writes assets/mdd/fixture.mdd and reads it with three.js 0.180's
// MDDLoader, into assets/mdd/mdd.json. Run it where `three` is installed.
import { writeFileSync } from 'node:fs';
import { MDDLoader } from 'three/examples/jsm/loaders/MDDLoader.js';

const frames = 3, points = 4;
const times = [ 0, 0.5, 1.25 ];
const buffer = new ArrayBuffer( 8 + frames * 4 + frames * points * 12 );
const view = new DataView( buffer );
view.setUint32( 0, frames );
view.setUint32( 4, points );
let offset = 8;
for ( const t of times ) { view.setFloat32( offset, t ); offset += 4; }
for ( let f = 0; f < frames; f ++ ) {
	for ( let p = 0; p < points * 3; p ++ ) {
		view.setFloat32( offset, Math.fround( Math.sin( f * 7.1 + p * 1.3 ) * ( p + 1 ) ) );
		offset += 4;
	}
}
writeFileSync( 'fixture.mdd', new Uint8Array( buffer ) );

const result = new MDDLoader().parse( buffer );
const track = result.clip.tracks[ 0 ];
writeFileSync( 'mdd.json', JSON.stringify( {
	clip: result.clip.name,
	duration: result.clip.duration,
	track: track.name,
	times: Array.from( track.times ),
	values: Array.from( track.values ),
	names: result.morphTargets.map( ( a ) => a.name ),
	targets: result.morphTargets.map( ( a ) => Array.from( a.array ) ),
} ) );
