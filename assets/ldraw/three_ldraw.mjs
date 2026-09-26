// Reads each LDraw model here with three.js 0.180's LDrawLoader, parts from
// `library/`, and writes the groups, objects and materials it makes into
// ldraw.json. Node has no fetch for files, so a stub reads them from disk.
// Run it where `three` is installed.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { FileLoader } from 'three';
import { LDrawLoader } from 'three/examples/jsm/loaders/LDrawLoader.js';
import { LDrawConditionalLineMaterial } from 'three/examples/jsm/materials/LDrawConditionalLineMaterial.js';

FileLoader.prototype.load = function ( url, onLoad, onProgress, onError ) {

	try {

		onLoad( readFileSync( ( this.path || '' ) + url, 'utf8' ) );

	} catch ( e ) {

		onError( e );

	}

};

const numbers = ( a ) => Array.from( a, ( v ) => ( Number.isFinite( v ) ? v : String( v ) ) );

function material( m ) {

	if ( m === null || m === undefined ) return null;
	if ( typeof m === 'string' ) return { code: m };
	const out = { type: m.constructor.type || m.type, name: m.name, code: m.userData.code === undefined ? null : m.userData.code };
	for ( const key of [ 'roughness', 'metalness', 'opacity', 'transparent', 'depthWrite', 'premultipliedAlpha', 'polygonOffset', 'polygonOffsetFactor' ] ) {

		if ( m[ key ] !== undefined ) out[ key ] = m[ key ];

	}

	if ( m.color ) out.color = m.color.toArray();
	if ( m.emissive ) out.emissive = m.emissive.toArray();
	if ( m.uniforms && m.uniforms.diffuse ) out.color = m.uniforms.diffuse.value.toArray();
	return out;

}

function node( o ) {

	const out = {
		type: o.isConditionalLine ? 'ConditionalLineSegments' : o.type,
		name: o.name,
		position: o.position.toArray(),
		quaternion: o.quaternion.toArray(),
		scale: o.scale.toArray(),
		userData: o.userData,
		children: o.children.map( node ),
	};
	if ( o.geometry ) {

		const g = o.geometry;
		out.attributes = {};
		for ( const name in g.attributes ) out.attributes[ name ] = numbers( g.attributes[ name ].array );
		out.groups = g.groups.map( ( x ) => [ x.start, x.count === Infinity ? 'Infinity' : x.count, x.materialIndex ] );
		out.material = Array.isArray( o.material ) ? o.material.map( material ) : material( o.material );

	}

	return out;

}

async function read( name, setup, useLoad = true ) {

	const loader = new LDrawLoader();
	loader.setConditionalLineMaterial( LDrawConditionalLineMaterial );
	loader.setPartsLibraryPath( 'library/' );
	if ( setup ) setup( loader );
	try {

		const group = await new Promise( ( resolve, reject ) => {

			if ( useLoad ) loader.load( name, resolve, undefined, reject );
			else loader.parse( readFileSync( name, 'utf8' ), resolve, reject );

		} );
		return { group: node( group ), materials: loader.materials.map( material ) };

	} catch ( e ) {

		return { error: String( e ) };

	}

}

const out = {};
out.scene = await read( 'scene.mpd' );
out.flat = await read( 'scene.mpd', ( l ) => {

	l.smoothNormals = false;

} );
out.parsed = await read( 'scene.mpd', null, false );
out.mapped = await read( 'scene.mpd', ( l ) => {

	l.setFileMap( { 'plate.dat': 'parts/brick.dat' } );

} );
out.kitchen = await read( 'kitchen.mpd' );
for ( const name of readdirSync( 'broken' ).filter( ( n ) => n.endsWith( '.ldr' ) ).sort() ) {

	out[ 'broken/' + name ] = await read( 'broken/' + name );

}

writeFileSync( 'ldraw.json', JSON.stringify( out, null, 1 ) );
