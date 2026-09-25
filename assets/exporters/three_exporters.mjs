// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json: what three.js 0.180 writes and reads for the scenes that
// `tests/test_export_options.mojo` builds. Run it with three 0.180 installed
// beside it: `node three_exporters.mjs > three.json`.
//
// - `obj`, `stl_ascii`, `stl_binary`, `ply_*`: the exporters' output for one
//   scene of a mesh, a skinned mesh, an instanced mesh, three lines and
//   points. Binary files are base64.
// - `usdz`: the `.usda` files of the three meshes, and the ids three.js gave
//   their geometries and materials.
// - `gltf_plain`, `gltf_custom`: GLTFExporter's JSON for a scene with user
//   data, without and with `includeCustomExtensions`.
// - `gltf_extras`: a glTF document with extras, and the user data
//   GLTFLoader gives each object.
// - `ply_mapped`: a PLY text, and the attributes PLYLoader reads from it
//   with both property name mappings.
// - `ply_colors_ascii`, `gltf_unlit_material`: a triangle with vertex colors
//   as PLY, and the material GLTFExporter writes for its `MeshBasicMaterial`.
// - `gltf_primitive_extras`: a geometry's `userData` as GLTFExporter writes
//   it on its primitive, and as GLTFLoader reads it back.

import * as THREE from 'three';
import { OBJExporter } from 'three/addons/exporters/OBJExporter.js';
import { STLExporter } from 'three/addons/exporters/STLExporter.js';
import { PLYExporter } from 'three/addons/exporters/PLYExporter.js';
import { USDZExporter } from 'three/addons/exporters/USDZExporter.js';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { PLYLoader } from 'three/addons/loaders/PLYLoader.js';
import { unzipSync, strFromU8 } from 'three/addons/libs/fflate.module.js';

// GLTFExporter reads its buffer back through a FileReader, which Node has not
// got.
globalThis.FileReader = class {
	readAsDataURL( blob ) {
		blob.arrayBuffer().then( ( bytes ) => {
			this.result = 'data:application/octet-stream;base64,' + Buffer.from( bytes ).toString( 'base64' );
			this.onloadend();
		} );
	}
};

function geometry( positions, extra = {} ) {
	const shape = new THREE.BufferGeometry();
	shape.setAttribute( 'position', new THREE.Float32BufferAttribute( positions, 3 ) );
	for ( const name in extra ) {
		shape.setAttribute( name, new THREE.Float32BufferAttribute( extra[ name ][ 0 ], extra[ name ][ 1 ] ) );
	}
	return shape;
}

const TRIANGLE = [ 0, 0, 0, 1, 0, 0, 0, 1, 0 ];

// GLTFLoader reads a `data:` buffer through `fetch`, and reports progress
// with a ProgressEvent, which Node has not got either.
globalThis.ProgressEvent = class extends Event {
	constructor( type, init = {} ) {
		super( type );
		Object.assign( this, init );
	}
};

// --- the scene of every kind the model exporters write ----------------------

function modelScene( withLines ) {
	const scene = new THREE.Scene();
	const standard = new THREE.MeshStandardMaterial();

	const square = geometry( [ 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0 ], {
		normal: [ [ 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1 ], 3 ],
		uv: [ [ 0, 0, 1, 0, 1, 1, 0, 1 ], 2 ],
	} );
	square.setIndex( [ 0, 1, 2, 0, 2, 3 ] );
	const plain = new THREE.Mesh( square, standard );
	plain.name = 'plain';
	plain.position.set( 1, 2, 3 );
	plain.scale.set( 2, 2, 2 );
	scene.add( plain );

	const limb = geometry( TRIANGLE, {
		skinIndex: [ [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ], 4 ],
		skinWeight: [ [ 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 ], 4 ],
	} );
	const skin = new THREE.SkinnedMesh( limb, standard );
	skin.name = 'skin';
	const bone = new THREE.Bone();
	bone.name = 'bone';
	bone.position.set( 0, 1, 0 );
	skin.add( bone );
	scene.add( skin );
	scene.updateMatrixWorld( true );
	skin.bind( new THREE.Skeleton( [ bone ] ) );
	bone.position.set( 0, 3, 0 );

	const many = new THREE.InstancedMesh( geometry( TRIANGLE ), standard, 2 );
	many.name = 'many';
	many.position.set( - 2, 0, 0 );
	many.setMatrixAt( 1, new THREE.Matrix4().makeTranslation( 5, 0, 0 ) );
	scene.add( many );

	if ( withLines ) {
		const ink = new THREE.LineBasicMaterial();
		const path = new THREE.Line( geometry( [ 0, 0, 0, 1, 0, 0, 1, 1, 0 ] ), ink );
		path.name = 'path';
		path.position.set( 0, 0, 1 );
		scene.add( path );
		const sticks = new THREE.LineSegments( geometry( [ 0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 4, 0, 0 ] ), ink );
		sticks.name = 'sticks';
		scene.add( sticks );
		const loop = new THREE.LineLoop( geometry( TRIANGLE ), ink );
		loop.name = 'loop';
		scene.add( loop );
		const cloud = new THREE.Points( geometry( [ 0, 0, 0, 0.5, 0, 0, 0, 0.25, 0 ], {
			color: [ [ 0, 0.002, 1, 1, 0, 0, 0.001, 1, 0 ], 3 ],
			normal: [ [ 0, 1, 0, 0, 1, 0, 0, 1, 0 ], 3 ],
		} ), new THREE.PointsMaterial() );
		cloud.name = 'cloud';
		cloud.position.set( 0, - 1, 0 );
		scene.add( cloud );
	}

	scene.updateMatrixWorld( true );
	return { scene, square, limb, many, standard };
}

function base64( buffer ) {
	return Buffer.from( buffer instanceof ArrayBuffer ? buffer : buffer.buffer ).toString( 'base64' );
}

const out = {};
const full = modelScene( true ).scene;
const meshes = modelScene( false );

out.obj = new OBJExporter().parse( full );
out.stl_ascii = new STLExporter().parse( full );
out.stl_binary = base64( new STLExporter().parse( full, { binary: true } ).buffer );

const ply = new PLYExporter();
out.ply_points_ascii = ply.parse( full, null, { excludeAttributes: [ 'color' ] } );
out.ply_points_little = base64( ply.parse( full, null, { binary: true, littleEndian: true, excludeAttributes: [ 'color' ] } ) );
out.ply_faces_ascii = ply.parse( meshes.scene );
out.ply_faces_big = base64( ply.parse( meshes.scene, null, { binary: true } ) );
out.ply_cloud_ascii = ply.parse( meshes.scene, null, { excludeAttributes: [ 'index', 'normal', 'uv' ] } );

const zipped = await new USDZExporter().parseAsync( meshes.scene );
const files = unzipSync( zipped );
out.usdz = {
	files: Object.fromEntries( Object.entries( files ).map( ( [ name, bytes ] ) => [ name, strFromU8( bytes ) ] ) ),
	geometries: [ meshes.square.id, meshes.limb.id, meshes.many.geometry.id ],
	material: meshes.standard.id,
};

// --- glTF user data ---------------------------------------------------------

function userScene() {
	const scene = new THREE.Scene();
	scene.userData = { s: 'scene', gltfExtensions: { EXT_scene: { on: true } } };
	const holder = new THREE.Object3D();
	holder.name = 'holder';
	holder.userData = { tag: 'node', n: 1, list: [ 1, 'two', null ], gltfExtensions: { EXT_node: { a: 1 } } };
	scene.add( holder );
	const paint = new THREE.MeshStandardMaterial();
	paint.userData = { m: true, gltfExtensions: { EXT_mat: { b: [ 1, 2 ] } } };
	const thing = new THREE.Mesh( geometry( TRIANGLE ), paint );
	thing.name = 'thing';
	thing.userData = { only: { gltfExtensions: 3 } };
	holder.add( thing );
	const bare = new THREE.Object3D();
	bare.name = 'bare';
	bare.userData = { gltfExtensions: { EXT_bare: {} } };
	scene.add( bare );
	return scene;
}

const gltf = new GLTFExporter();
out.gltf_plain = await gltf.parseAsync( userScene() );
out.gltf_custom = await gltf.parseAsync( userScene(), { includeCustomExtensions: true } );

const document = {
	asset: { version: '2.0' },
	scene: 0,
	scenes: [ { nodes: [ 0, 1, 2 ], extras: { s: 1 } } ],
	nodes: [
		{ name: 'one', mesh: 0, extras: { n: 'node', shared: 'node' } },
		{ name: 'two', mesh: 1, extras: { n: 2 } },
		{ mesh: 0, extras: 5 },
	],
	meshes: [
		{ primitives: [ { attributes: { POSITION: 0 }, material: 0 } ], extras: { m: 'mesh', shared: 'mesh' } },
		{ primitives: [ { attributes: { POSITION: 0 } }, { attributes: { POSITION: 0 } } ], extras: { m: 'two' } },
	],
	materials: [ { extras: { k: [ 1, 2 ] } } ],
	accessors: [ { bufferView: 0, componentType: 5126, count: 3, type: 'VEC3', max: [ 1, 1, 0 ], min: [ 0, 0, 0 ] } ],
	bufferViews: [ { buffer: 0, byteLength: 36 } ],
	buffers: [ { byteLength: 36, uri: 'data:application/octet-stream;base64,' + base64( new Float32Array( TRIANGLE ) ) } ],
};
const text = JSON.stringify( document );
const loaded = await new GLTFLoader().parseAsync( text, '' );
const one = loaded.scene.children[ 0 ];
const two = loaded.scene.children[ 1 ];
const three = loaded.scene.children[ 2 ];
out.gltf_extras = {
	text,
	scene: loaded.scene.userData,
	nodes: [ one.userData, two.userData, three.userData ],
	parts: two.children.map( ( part ) => part.userData ),
	material: one.material.userData,
};

// --- primitive extras ------------------------------------------------------
//
// GLTFExporter writes a geometry's `userData` as its primitive's `extras`,
// and GLTFLoader reads them back into the geometry's `userData`.

const leaf = geometry( TRIANGLE );
leaf.userData = { kind: 'leaf', count: 3 };
const leafScene = new THREE.Scene();
leafScene.add( new THREE.Mesh( leaf, new THREE.MeshStandardMaterial() ) );
const leafDocument = await gltf.parseAsync( leafScene );
const leafRead = await new GLTFLoader().parseAsync( JSON.stringify( leafDocument ), '' );
out.gltf_primitive_extras = {
	written: leafDocument.meshes[ 0 ].primitives[ 0 ].extras,
	read: leafRead.scene.children[ 0 ].geometry.userData,
};

// --- PLY property name mappings ---------------------------------------------

const plyText = [
	'ply',
	'format ascii 1.0',
	'element vertex 2',
	'property float x',
	'property float y',
	'property float z',
	'property uchar cr',
	'property uchar cg',
	'property uchar cb',
	'property float q1',
	'property float q2',
	'end_header',
	'0 0 0 255 0 0 1 2',
	'1 2 3 0 255 0 3 4',
	'',
].join( '\n' );
const reader = new PLYLoader();
reader.setPropertyNameMapping( { cr: 'red', cg: 'green', cb: 'blue' } );
reader.setCustomPropertyNameMapping( { quality: [ 'q1', 'q2' ] } );
const read = reader.parse( plyText );
out.ply_mapped = {
	text: plyText,
	position: Array.from( read.getAttribute( 'position' ).array ),
	color: Array.from( read.getAttribute( 'color' ).array ),
	quality: Array.from( read.getAttribute( 'quality' ).array ),
	quality_size: read.getAttribute( 'quality' ).itemSize,
};

// --- vertex colors and an unlit material ------------------------------------
//
// PLYExporter writes `Math.floor( color * 255 )` after the sRGB encode, and
// GLTFExporter writes an unlit material's roughness as 0.9.

const tinted = new THREE.Scene();
tinted.add( new THREE.Mesh(
	geometry( TRIANGLE, { color: [ [ 1, 1, 1, 0.5, 0.25, 0, 0.2, 0.6, 0.9 ], 3 ] } ),
	new THREE.MeshBasicMaterial( { vertexColors: true } ),
) );
out.ply_colors_ascii = ply.parse( tinted );
out.gltf_unlit_material = ( await gltf.parseAsync( tinted ) ).materials[ 0 ];

console.log( JSON.stringify( out, null, 1 ) );
