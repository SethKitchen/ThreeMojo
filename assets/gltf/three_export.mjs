// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three_export.gltf: the scene `tests/test_gltf_export_scene.mojo`
// builds, exported by three.js 0.180's GLTFExporter. Run it with three 0.180
// installed beside it: `node three_export.mjs > three_export.gltf`.

import * as THREE from 'three';
import { GLTFExporter } from 'three/addons/exporters/GLTFExporter.js';

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

function triangle() {
	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( [ 0, 0, 0, 1, 0, 0, 0, 1, 0 ], 3 ) );
	return geometry;
}

function path( count ) {
	const points = [];
	for ( let i = 0; i < count; i ++ ) points.push( i, i * i, 0 );
	const geometry = new THREE.BufferGeometry();
	geometry.setAttribute( 'position', new THREE.Float32BufferAttribute( points, 3 ) );
	return geometry;
}

const scene = new THREE.Scene();
const white = new THREE.MeshBasicMaterial();

const lamp = new THREE.PointLight( 0xff8000, 3, 10 );
lamp.name = 'lamp';
lamp.position.set( 0, 2, 0 );
scene.add( lamp );

const sun = new THREE.DirectionalLight( 0xffffff, 2 );
sun.name = 'sun';
sun.add( sun.target );
sun.target.position.set( 0, 0, - 1 );
scene.add( sun );

const spot = new THREE.SpotLight( 0x00ff00, 5, 5, 0.5, 0.2 );
spot.name = 'spot';
spot.add( spot.target );
spot.target.position.set( 0, 0, - 1 );
scene.add( spot );

const eye = new THREE.PerspectiveCamera( 50, 1.5, 0.1, 100 );
eye.name = 'eye';
eye.position.set( 0, 0, 5 );
scene.add( eye );

const flat = new THREE.OrthographicCamera( - 2, 2, 1, - 1, 0.5, 20 );
flat.name = 'flat';
scene.add( flat );

const shape = triangle();
const smile = new THREE.Float32BufferAttribute( [ 0, 1, 0, 0, 0, 0, 0, 0, 0 ], 3 );
smile.name = 'smile';
const frown = new THREE.Float32BufferAttribute( [ 0, 0, 0, 0, - 1, 0, 0, 0, 0 ], 3 );
frown.name = 'frown';
shape.morphAttributes.position = [ smile, frown ];
shape.morphTargetsRelative = true;
const blob = new THREE.Mesh( shape, white );
blob.name = 'blob';
blob.morphTargetInfluences[ 0 ] = 0.25;
blob.morphTargetInfluences[ 1 ] = 0.5;
scene.add( blob );

const root = new THREE.Bone();
root.name = 'root';
const tip = new THREE.Bone();
tip.name = 'tip';
tip.position.set( 0, 1, 0 );
root.add( tip );
scene.add( root );

const limb = triangle();
limb.setAttribute( 'skinIndex', new THREE.Uint16BufferAttribute( [ 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 ], 4 ) );
limb.setAttribute( 'skinWeight', new THREE.Float32BufferAttribute( [ 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 ], 4 ) );
const arm = new THREE.SkinnedMesh( limb, white );
arm.name = 'arm';
scene.add( arm );
scene.updateMatrixWorld( true );
arm.bind( new THREE.Skeleton( [ root, tip ] ) );

const crowd = new THREE.InstancedMesh( triangle(), white, 2 );
crowd.name = 'crowd';
crowd.setMatrixAt( 0, new THREE.Matrix4().makeTranslation( 1, 0, 0 ) );
crowd.setMatrixAt( 1, new THREE.Matrix4().compose(
	new THREE.Vector3( 0, 1, 0 ), new THREE.Quaternion(), new THREE.Vector3( 2, 2, 2 ) ) );
crowd.setColorAt( 0, new THREE.Color( 0xff0000 ) );
crowd.setColorAt( 1, new THREE.Color( 0x0000ff ) );
scene.add( crowd );

const ink = new THREE.MeshBasicMaterial( { color: 0x336699 } );
const wire = new THREE.LineSegments( path( 4 ), ink );
wire.name = 'wire';
scene.add( wire );
const loop = new THREE.LineLoop( path( 3 ), ink );
loop.name = 'loop';
scene.add( loop );
const strip = new THREE.Line( path( 3 ), ink );
strip.name = 'strip';
scene.add( strip );
const dots = new THREE.Points( path( 2 ), ink );
dots.name = 'dots';
scene.add( dots );

const discrete = new THREE.QuaternionKeyframeTrack(
	'root.quaternion', [ 0, 1 ], [ 0, 0, 0, 1, 0, 0, Math.SQRT1_2, Math.SQRT1_2 ] );
discrete.setInterpolation( THREE.InterpolateDiscrete );
const clip = new THREE.AnimationClip( 'move', - 1, [
	new THREE.VectorKeyframeTrack( 'lamp.position', [ 0, 1, 2 ], [ 0, 2, 0, 1, 2, 0, 1, 3, 0 ] ),
	discrete,
	new THREE.VectorKeyframeTrack( 'tip.scale', [ 0, 2 ], [ 1, 1, 1, 2, 2, 2 ] ),
	new THREE.NumberKeyframeTrack( 'blob.morphTargetInfluences[frown]', [ 0, 1 ], [ 0, 1 ] ),
	new THREE.NumberKeyframeTrack( 'blob.morphTargetInfluences[smile]', [ 0.5, 1.5 ], [ 1, 0 ] ),
] );

const gltf = await new GLTFExporter().parseAsync( scene, { trs: true, animations: [ clip ] } );
process.stdout.write( JSON.stringify( gltf, null, 1 ) + '\n' );
