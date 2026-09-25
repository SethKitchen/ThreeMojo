// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json: what three.js 0.180 does with the track paths that
// `tests/test_animation_paths.mojo` plays. Run it with three 0.180 installed
// beside it: `node three_paths.mjs > three.json`.
//
// - `element`: a node's position, scale and quaternion after one number of
//   each is driven at half weight, `.position[x]`, `.scale[z]` and
//   `.rotation[y]`.
// - `map`: a map's offset, repeat, center and rotation after `.map.` tracks.
// - `document`: a scene's JSON, with a mesh of two materials and a mesh of
//   named morph targets, and a clip on `material[1]`, a morph target by
//   name and `position[y]`. It also has a track on `materials[0]`, which
//   three.js binds to nothing: it reads the old `material.materials`.
// - `loaded`: what that clip sets, a quarter of a second in.
// - `set_time`: a node's position after `setTime` with each loop mode.
// - `user_data`: the JSON three.js writes for a clip's user data.
// - `creator`: the clips `AnimationClipCreator` makes, as `toJSON` writes
//   them, with `Math.random` drawn from `MathUtils.seededRandom`: from 7
//   for the shake and from 11 for the pulse.

import * as THREE from 'three';

const out = {};
const r = ( v ) => + v.toFixed( 6 );

// One number of each vector, at half weight.
{
	const node = new THREE.Object3D();
	node.position.set( 1, 2, 3 );
	node.rotation.set( 0.1, 0.2, 0.3 );
	const clip = new THREE.AnimationClip( 'e', - 1, [
		new THREE.NumberKeyframeTrack( '.position[x]', [ 0, 1 ], [ 0, 4 ] ),
		new THREE.NumberKeyframeTrack( '.scale[z]', [ 0, 1 ], [ 1, 3 ] ),
		new THREE.NumberKeyframeTrack( '.rotation[y]', [ 0, 1 ], [ 0, 1.5 ] ),
	] );
	const mixer = new THREE.AnimationMixer( node );
	const action = mixer.clipAction( clip );
	action.weight = 0.5;
	action.play();
	mixer.update( 0.5 );
	out.element = {
		position: node.position.toArray().map( r ),
		scale: node.scale.toArray().map( r ),
		quaternion: node.quaternion.toArray().map( r ),
	};
}

// A map's offset, repeat, center and rotation.
{
	const map = new THREE.Texture();
	const mesh = new THREE.Mesh( new THREE.BoxGeometry(), new THREE.MeshBasicMaterial( { map } ) );
	const clip = new THREE.AnimationClip( 'm', - 1, [
		new THREE.VectorKeyframeTrack( '.map.offset', [ 0, 1 ], [ 0, 0, 1, 0.5 ] ),
		new THREE.VectorKeyframeTrack( '.map.repeat', [ 0, 1 ], [ 1, 1, 3, 5 ] ),
		new THREE.VectorKeyframeTrack( '.map.center', [ 0, 1 ], [ 0, 0, 0.5, 0.5 ] ),
		new THREE.NumberKeyframeTrack( '.map.rotation', [ 0, 1 ], [ 0, 2 ] ),
	] );
	const mixer = new THREE.AnimationMixer( mesh );
	mixer.clipAction( clip ).play();
	mixer.update( 0.25 );
	out.map = {
		offset: map.offset.toArray().map( r ),
		repeat: map.repeat.toArray().map( r ),
		center: map.center.toArray().map( r ),
		rotation: r( map.rotation ),
	};
}

// A scene written as JSON, and what its clip does.
{
	const scene = new THREE.Scene();
	const multi = new THREE.Mesh( new THREE.BoxGeometry(), [
		new THREE.MeshBasicMaterial( { opacity: 1 } ),
		new THREE.MeshBasicMaterial( { opacity: 1 } ),
	] );
	multi.name = 'Multi';
	scene.add( multi );
	const shape = new THREE.BufferGeometry();
	shape.setAttribute( 'position', new THREE.Float32BufferAttribute( [ 0, 0, 0, 1, 0, 0, 0, 1, 0 ], 3 ) );
	const smile = new THREE.Float32BufferAttribute( [ 0, 1, 0, 1, 1, 0, 0, 2, 0 ], 3 );
	smile.name = 'smile';
	const frown = new THREE.Float32BufferAttribute( [ 0, - 1, 0, 1, - 1, 0, 0, 0, 0 ], 3 );
	frown.name = 'frown';
	shape.morphAttributes.position = [ smile, frown ];
	const face = new THREE.Mesh( shape, new THREE.MeshBasicMaterial() );
	face.name = 'Face';
	scene.add( face );
	const clip = new THREE.AnimationClip( 'paths', - 1, [
		new THREE.NumberKeyframeTrack( 'Multi.material[1].opacity', [ 0, 1 ], [ 1, 0 ] ),
		new THREE.NumberKeyframeTrack( 'Multi.materials[0].opacity', [ 0, 1 ], [ 1, 0.5 ] ),
		new THREE.NumberKeyframeTrack( 'Face.morphTargetInfluences[frown]', [ 0, 1 ], [ 0, 1 ] ),
		new THREE.NumberKeyframeTrack( 'Multi.position[y]', [ 0, 1 ], [ 0, 2 ] ),
	] );
	clip.userData = { take: 3 };
	scene.animations.push( clip );
	out.document = JSON.stringify( scene.toJSON() );
	const mixer = new THREE.AnimationMixer( scene );
	mixer.clipAction( clip ).play();
	mixer.update( 0.25 );
	out.loaded = {
		opacity: [ r( multi.material[ 0 ].opacity ), r( multi.material[ 1 ].opacity ) ],
		influences: face.morphTargetInfluences.map( r ),
		position: multi.position.toArray().map( r ),
	};
}

// setTime, with each loop mode.
{
	const clip = new THREE.AnimationClip( 's', - 1, [
		new THREE.VectorKeyframeTrack( '.position', [ 0, 1, 2 ], [ 0, 0, 0, 1, 2, 3, 4, 0, 0 ] ),
	] );
	out.set_time = {};
	for ( const [ name, loop ] of [ [ 'repeat', THREE.LoopRepeat ], [ 'ping_pong', THREE.LoopPingPong ], [ 'once', THREE.LoopOnce ] ] ) {
		const node = new THREE.Object3D();
		const mixer = new THREE.AnimationMixer( node );
		const action = mixer.clipAction( clip );
		action.setLoop( loop, Infinity );
		action.clampWhenFinished = true;
		action.play();
		mixer.update( 0.7 );
		mixer.setTime( 2.5 );
		out.set_time[ name ] = node.position.toArray().map( r );
	}
}

// A clip's user data.
{
	const clip = new THREE.AnimationClip( 'u', 1, [ new THREE.NumberKeyframeTrack( '.visible', [ 0 ], [ 1 ] ) ] );
	clip.userData = { take: 3, tag: 'a' };
	out.user_data = THREE.AnimationClip.toJSON( clip ).userData;
}

// AnimationClipCreator, with seeded random numbers.
{
	const { AnimationClipCreator } = await import( 'three/examples/jsm/animation/AnimationClipCreator.js' );
	// Each random clip starts from its own seed: three.js's clip takes
	// numbers from `Math.random` too, for its uuid.
	const seed = ( s ) => {

		let first = true;
		Math.random = () => {

			if ( first ) {

				first = false;
				return THREE.MathUtils.seededRandom( s );

			}

			return THREE.MathUtils.seededRandom();

		};

	};
	const tracks = ( clip ) => clip.tracks.map( ( t ) => ( { times: Array.from( t.times ).map( r ), values: Array.from( t.values ).map( ( v ) => typeof v === 'number' ? r( v ) : ( v ? 1 : 0 ) ) } ) );
	out.creator = {
		rotation: tracks( AnimationClipCreator.CreateRotationAnimation( 2, 'y' ) ),
		scale_axis: tracks( AnimationClipCreator.CreateScaleAxisAnimation( 1.5, 'z' ) ),
		shake: ( seed( 7 ), tracks( AnimationClipCreator.CreateShakeAnimation( 0.35, new THREE.Vector3( 1, 2, 3 ) ) ) ),
		pulsation: ( seed( 11 ), tracks( AnimationClipCreator.CreatePulsationAnimation( 0.25, 4 ) ) ),
		visibility: tracks( AnimationClipCreator.CreateVisibilityAnimation( 3 ) ),
		color: tracks( AnimationClipCreator.CreateMaterialColorAnimation( 2, [ new THREE.Color( 1, 0, 0 ), new THREE.Color( 0, 0.5, 0 ), new THREE.Color( 0.25, 0.25, 1 ) ] ) ),
	};
}

console.log( JSON.stringify( out ) );
