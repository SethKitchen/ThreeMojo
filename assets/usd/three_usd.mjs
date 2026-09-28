// Reads the USD fixtures in this folder with three.js r186's `USDLoader`,
// `USDAParser` and `USDCParser`, into `usd.json`. `make_usd.py` writes the
// crates and the archives first. Run it from the repository's root, with
// `THREE` set to the folder that holds three.js r186's `package.json`:
//
//     THREE=/path/to/node_modules/three node assets/usd/three_usd.mjs
//
// A texture loads through an <img>, which Node has not got. A stand-in
// loads a blob, and a file that is on the disk, and fails any other.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const THREE = process.env.THREE;
const { USDLoader } = await import( THREE + '/examples/jsm/loaders/USDLoader.js' );
const { USDAParser } = await import( THREE + '/examples/jsm/loaders/usd/USDAParser.js' );
const { USDCParser } = await import( THREE + '/examples/jsm/loaders/usd/USDCParser.js' );

globalThis.Image = class {

	set src( url ) {

		this.url = url;
		const ok = url.startsWith( 'blob:' ) || existsSync( url );
		setTimeout( () => ok ? this.onload() : this.onerror(), 0 );

	}

};

console.warn = () => {};

const DIR = 'assets/usd/';

// A value as JSON: `undefined` as a string, a number that JSON has not got
// as a string, and a typed array as an array.
function value( v ) {

	if ( v === undefined ) return '__undefined__';
	if ( typeof v === 'number' ) return Number.isFinite( v ) ? v : String( v );
	if ( ArrayBuffer.isView( v ) ) return Array.from( v, value );
	if ( Array.isArray( v ) ) return v.map( value );
	if ( v !== null && typeof v === 'object' ) {

		const out = {};
		for ( const key of Object.keys( v ) ) out[ key ] = value( v[ key ] );
		return out;

	}

	return v;

}

function layer( data ) {

	const out = [];
	for ( const path of Object.keys( data.specsByPath ) ) {

		const spec = data.specsByPath[ path ];
		out.push( { path, specType: spec.specType, fields: value( spec.fields ) } );

	}

	return out;

}

const r = ( x ) => Number.isFinite( x ) ? Math.round( x * 1e6 ) / 1e6 : String( x );

function texture( map ) {

	if ( ! map ) return null;
	return {
		url: map.image ? ( map.image.url.startsWith( 'blob:' ) ? 'blob' : map.image.url ) : null,
		wrapS: map.wrapS, wrapT: map.wrapT, colorSpace: map.colorSpace, channel: map.channel,
		rotation: r( map.rotation ), repeat: [ r( map.repeat.x ), r( map.repeat.y ) ],
		offset: [ r( map.offset.x ), r( map.offset.y ) ],
		scale: map.userData.scale ? value( map.userData.scale ) : null,
		bias: map.userData.bias ? value( map.userData.bias ) : null,
	};

}

function material( m ) {

	return {
		color: m.color.toArray().map( r ), emissive: m.emissive.toArray().map( r ),
		specularColor: m.specularColor.toArray().map( r ),
		roughness: r( m.roughness ), metalness: r( m.metalness ), clearcoat: r( m.clearcoat ),
		clearcoatRoughness: r( m.clearcoatRoughness ), ior: r( m.ior ), opacity: r( m.opacity ),
		transparent: m.transparent, alphaTest: r( m.alphaTest ),
		normalScale: [ r( m.normalScale.x ), r( m.normalScale.y ) ],
		map: texture( m.map ), emissiveMap: texture( m.emissiveMap ), normalMap: texture( m.normalMap ),
		roughnessMap: texture( m.roughnessMap ), metalnessMap: texture( m.metalnessMap ),
		aoMap: texture( m.aoMap ), specularColorMap: texture( m.specularColorMap ),
	};

}

// A geometry three.js makes, such as `BoxGeometry`, keeps its arrays in
// `scene.usda text` only, to keep this file small.
let full = true;

function describe( object ) {

	const out = {
		name: object.name, type: object.type,
		position: object.position.toArray().map( r ), quaternion: object.quaternion.toArray().map( r ),
		scale: object.scale.toArray().map( r ),
		children: object.children.map( describe ),
	};
	if ( object.isMesh ) {

		const geometry = object.geometry;
		out.geometry = geometry.type;
		out.parameters = geometry.parameters ? value( geometry.parameters ) : null;
		out.attributes = {};
		const keep = full || geometry.type === 'BufferGeometry';
		for ( const [ key, attribute ] of Object.entries( geometry.attributes ) ) out.attributes[ key ] = keep ? Array.from( attribute.array, r ) : attribute.array.length;
		out.index = geometry.index ? Array.from( geometry.index.array ) : null;
		out.groups = geometry.groups.map( ( g ) => [ g.start, g.count, g.materialIndex ] );
		out.materials = ( Array.isArray( object.material ) ? object.material : [ object.material ] ).map( material );

	}

	return out;

}

async function load( name, input, path ) {

	let done;
	const ready = new Promise( ( resolve ) => done = resolve );
	const group = new USDLoader().parse( input, path, done, ( e ) => done( e ) );
	await ready;
	return describe( group );

}

const bytes = ( name ) => {

	const b = readFileSync( DIR + name );
	return b.buffer.slice( b.byteOffset, b.byteOffset + b.length );

};

const reference = { layers: {}, scenes: {} };

for ( const name of [ 'scene.usda', 'values.usda', 'variants.usda', 'stage.usda', 'geo.usda' ] ) {

	reference.layers[ name ] = layer( new USDAParser().parseData( readFileSync( DIR + name, 'utf8' ) ) );

}

for ( const name of [ 'scene.usdc', 'values.usdc', 'values_0_3.usdc', 'values_0_6.usdc', 'variants.usdc', 'geo.usdc' ] ) {

	reference.layers[ name ] = layer( new USDCParser().parseData( bytes( name ) ) );

}

// A string is read as USDA text with no folder, as `parse` reads it.
reference.scenes[ 'scene.usda text' ] = await load( 'scene.usda', readFileSync( DIR + 'scene.usda', 'utf8' ), '' );

// Each file is read as `load` reads it: as bytes, from its folder.
full = false;
for ( const name of [ 'scene.usda', 'scene.usdc', 'variants.usdc', 'values.usdc', 'package.usdz', 'crate.usdz', 'roundtrip.usdz' ] ) {

	if ( ! existsSync( DIR + name ) ) continue;
	reference.scenes[ name ] = await load( name, bytes( name ), DIR );

}

writeFileSync( DIR + 'usd.json', JSON.stringify( reference ) );
