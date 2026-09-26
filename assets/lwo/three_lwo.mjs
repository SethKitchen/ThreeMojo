// Reads each LightWave object here with three.js 0.180's LWOLoader, and
// writes the meshes and materials it makes into lwo.json. Node has no
// images, so a texture is recorded by the path three.js would load. Run it
// where `three` is installed.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { Texture, TextureLoader } from 'three';
import { LWOLoader } from 'three/examples/jsm/loaders/LWOLoader.js';

TextureLoader.prototype.load = function ( url ) {

	const texture = new Texture();
	texture.name = ( this.path || '' ) + url;
	return texture;

};

const numbers = ( a ) => Array.from( a, ( v ) => ( Number.isNaN( v ) ? 'NaN' : v ) );

function attribute( a ) {

	return a ? { itemSize: a.itemSize, array: numbers( a.array ) } : null;

}

function mesh( m ) {

	const g = m.geometry;
	return {
		type: m.type,
		name: m.name,
		position: m.position.toArray(),
		pivot: m.userData.pivot,
		material: Array.isArray( m.material ) ? m.material.map( ( x ) => x ? x.name + '|' + x.type : null ) : m.material.name + '|' + m.material.type,
		position_attribute: attribute( g.attributes.position ),
		normal: attribute( g.attributes.normal ),
		uv: attribute( g.attributes.uv ),
		index: g.index ? numbers( g.index.array ) : null,
		groups: g.groups.map( ( x ) => [ x.start, x.count, x.materialIndex ] ),
		morphs: ( g.morphAttributes.position || [] ).map( ( x ) => ( { name: x.name, array: numbers( x.array ) } ) ),
		morphRelative: g.morphTargetsRelative,
		matNames: g.userData.matNames,
		children: m.children.map( mesh ),
	};

}

function texture( t ) {

	return t ? { name: t.name, wrapS: t.wrapS, wrapT: t.wrapT, mapping: t.mapping, colorSpace: t.colorSpace } : null;

}

function material( m ) {

	const out = { type: m.type, name: m.name };
	for ( const key of [ 'side', 'flatShading', 'opacity', 'transparent', 'emissiveIntensity', 'shininess', 'reflectivity', 'combine', 'refractionRatio', 'roughness', 'metalness', 'clearcoat', 'clearcoatRoughness', 'bumpScale', 'size' ] ) {

		if ( m[ key ] !== undefined ) out[ key ] = m[ key ];

	}

	for ( const key of [ 'color', 'emissive', 'specular' ] ) {

		if ( m[ key ] !== undefined ) out[ key ] = m[ key ].toArray();

	}

	for ( const key of [ 'map', 'aoMap', 'roughnessMap', 'specularMap', 'emissiveMap', 'metalnessMap', 'alphaMap', 'normalMap', 'bumpMap', 'envMap' ] ) {

		if ( m[ key ] ) out[ key ] = texture( m[ key ] );

	}

	if ( m.normalScale ) out.normalScale = m.normalScale.toArray();
	return out;

}

const out = {};
const broken = readdirSync( 'broken' ).filter( ( n ) => n.endsWith( '.lwo' ) ).sort().map( ( n ) => 'broken/' + n.slice( 0, - 4 ) );
for ( const name of [ 'scene', 'standard', 'phong', 'physical', 'kitchen', 'kitchen3', ...broken ] ) {

	const bytes = readFileSync( name + '.lwo' );
	const buffer = bytes.buffer.slice( bytes.byteOffset, bytes.byteOffset + bytes.byteLength );
	try {

		const result = new LWOLoader().parse( buffer, 'models/', name );
		out[ name ] = {
			meshes: result.meshes.map( mesh ),
			materials: result.materials.map( material ),
		};

	} catch ( e ) {

		out[ name ] = { error: String( e ) };

	}

}

writeFileSync( 'lwo.json', JSON.stringify( out, null, 1 ) );
