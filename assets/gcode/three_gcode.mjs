// Reads assets/gcode/fixture.gcode with three.js 0.180's GCodeLoader, as one
// pair of objects and split into layers, into assets/gcode/gcode.json. Run it
// where `three` is installed.
import { readFileSync, writeFileSync } from 'node:fs';
import { GCodeLoader } from 'three/examples/jsm/loaders/GCodeLoader.js';

const text = readFileSync( 'fixture.gcode', 'utf8' );
function objects( split ) {
	const loader = new GCodeLoader();
	loader.splitLayer = split;
	const group = loader.parse( text );
	return {
		name: group.name,
		rotation: [ group.rotation.x, group.rotation.y, group.rotation.z ],
		children: group.children.map( ( c ) => ( {
			name: c.name,
			material: c.material.name,
			color: c.material.color.getHex(),
			positions: Array.from( c.geometry.attributes.position.array, ( v ) => Number.isNaN( v ) ? 'NaN' : v ),
		} ) ),
	};
}
writeFileSync( 'gcode.json', JSON.stringify( { whole: objects( false ), split: objects( true ) } ) );
