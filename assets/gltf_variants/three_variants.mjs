// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes variants.gltf, a file with KHR_materials_variants, and
// variants.json: what three.js 0.180's GLTFLoader, with the
// KHR_materials_variants plugin of takahirox/three-gltf-extensions at
// 9ae3a14 registered, draws each object with for each variant.
// `tests/test_gltf_variants.mojo` reads them. Run it with three 0.180
// installed beside it and the plugin copied beside it as
// KHR_materials_variants.js: `node three_variants.mjs`.

import { writeFileSync } from 'node:fs';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import GLTFMaterialsVariantsExtension from './KHR_materials_variants.js';

// Node has no ProgressEvent, which FileLoader makes for a data: URI.
globalThis.ProgressEvent ??= class ProgressEvent {

	constructor( type, init ) {

		Object.assign( this, { type }, init );

	}

};

// A triangle, and its three vertex colors.
const floats = new Float32Array( [ 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 ] );
const uri = 'data:application/octet-stream;base64,' + Buffer.from( floats.buffer ).toString( 'base64' );
const color = ( name, rgb ) => ( { name, pbrMetallicRoughness: { baseColorFactor: [ ...rgb, 1 ] } } );
const variants = ( mappings ) => ( { extensions: { KHR_materials_variants: { mappings } } } );

const gltf = {
	asset: { version: '2.0' },
	extensionsUsed: [ 'KHR_materials_variants' ],
	extensions: { KHR_materials_variants: { variants: [ { name: 'red' }, { name: 'red' }, { name: 'blue' }, { name: 'red.1' } ] } },
	buffers: [ { byteLength: 72, uri } ],
	bufferViews: [ { buffer: 0, byteLength: 36 }, { buffer: 0, byteOffset: 36, byteLength: 36 } ],
	accessors: [
		{ bufferView: 0, componentType: 5126, count: 3, type: 'VEC3', min: [ 0, 0, 0 ], max: [ 1, 1, 0 ] },
		{ bufferView: 1, componentType: 5126, count: 3, type: 'VEC3' },
	],
	materials: [ color( 'white', [ 1, 1, 1 ] ), color( 'red', [ 1, 0, 0 ] ), color( 'blue', [ 0, 0, 1 ] ), color( 'green', [ 0, 1, 0 ] ) ],
	meshes: [
		// Two primitives: the second has vertex colors and no material of
		// its own, and a later mapping of a variant wins.
		{ primitives: [
			{ attributes: { POSITION: 0 }, material: 0, ...variants( [ { material: 1, variants: [ 0, 1 ] }, { material: 2, variants: [ 2 ] } ] ) },
			{ attributes: { POSITION: 0, COLOR_0: 1 }, ...variants( [ { material: 3, variants: [ 1 ] }, { material: 2, variants: [ 1, 3 ] } ] ) },
		] },
		// Points, which three.js draws with a PointsMaterial made from the
		// variant's.
		{ primitives: [ { attributes: { POSITION: 0 }, mode: 0, material: 0, ...variants( [ { material: 3, variants: [ 2 ] } ] ) } ] },
		// A mesh with no mappings keeps its material.
		{ primitives: [ { attributes: { POSITION: 0 }, material: 2 } ] },
	],
	nodes: [ { mesh: 0 }, { mesh: 1 }, { mesh: 2 } ],
	scenes: [ { nodes: [ 0, 1, 2 ] } ],
	scene: 0,
};

const text = JSON.stringify( gltf );
writeFileSync( 'variants.gltf', text );

const loader = new GLTFLoader().register( ( parser ) => new GLTFMaterialsVariantsExtension( parser ) );
const result = await loader.parseAsync( text, '' );
const drawn = [];
result.scene.traverse( ( o ) => o.material && drawn.push( o ) );
// The plugin reads the glTF index of a material it restores, for a
// callback only, and throws for a material that three.js made itself: a
// default material, or a PointsMaterial. Give those an empty association.
for ( const o of drawn ) {

	if ( ! result.parser.associations.get( o.material ) ) result.parser.associations.set( o.material, {} );

}

const look = () => drawn.map( ( o ) => ( { type: o.type, material: o.material.type, color: o.material.color.getHexString(), vertexColors: o.material.vertexColors } ) );
const out = { variants: result.userData.variants, original: look(), selected: {} };
for ( const name of [ ...result.userData.variants, 'none' ] ) {

	await result.functions.selectVariant( result.scene, name );
	out.selected[ name ] = look();

}

await result.functions.selectVariant( result.scene, null );
out.restored = look();
writeFileSync( 'variants.json', JSON.stringify( out, null, 1 ) );
console.log( JSON.stringify( out ) );
