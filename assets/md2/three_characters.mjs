// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes characters.json: what three.js 0.180's MorphBlendMesh,
// MorphAnimMesh, MD2Character and MD2CharacterComplex do with fixture.md2
// and many.md2 beside it, for `tests/test_md2_character.mojo`. Run it with
// three 0.180 installed beside it:
// `node three_characters.mjs > characters.json`.
//
// - `blend`: the animations `autoCreateAnimations( 6 )` makes, and the
//   morph weights after each update of a run played forward, back, and
//   back and forth.
// - `anim`: the weights of a MorphAnimMesh playing `run` at 6 frames a
//   second, forward and then back.
// - `character`: an MD2Character of fixture.md2 with the weapons
//   fixture.md2 and many.md2, at scale 2: the root's height, and the
//   weights of the body and the weapons after each step.
// - `complex`: an MD2CharacterComplex of the same parts, driven forward,
//   left, and then let go: the root's place and turn, the speed, and the
//   body's weights after each update.

import * as THREE from 'three';
import { readFileSync } from 'fs';
import { MD2Loader } from 'three/examples/jsm/loaders/MD2Loader.js';
import { MorphBlendMesh } from 'three/examples/jsm/misc/MorphBlendMesh.js';
import { MorphAnimMesh } from 'three/examples/jsm/misc/MorphAnimMesh.js';
import { MD2Character } from 'three/examples/jsm/misc/MD2Character.js';
import { MD2CharacterComplex } from 'three/examples/jsm/misc/MD2CharacterComplex.js';

const here = new URL( '.', import.meta.url ).pathname.replace( /^\/([A-Za-z]:)/, '$1' );
const read = ( name ) => {

	const bytes = readFileSync( here + name );
	return bytes.buffer.slice( bytes.byteOffset, bytes.byteOffset + bytes.byteLength );

};
const loader = new MD2Loader();
const parse = ( name ) => loader.parse( read( name ) );

// The loaders read the files beside this script, at once.
MD2Loader.prototype.load = function ( url, onLoad ) {

	onLoad( this.parse( read( url ) ) );

};
THREE.TextureLoader.prototype.load = function ( url, onLoad ) {

	const texture = new THREE.Texture();
	texture.name = url;
	if ( onLoad ) queueMicrotask( () => onLoad( texture ) );
	return texture;

};

const r = ( v ) => + v.toFixed( 6 );
const weights = ( mesh ) => mesh.morphTargetInfluences.map( r );
const out = {};

// MorphBlendMesh.
{
	const mesh = new MorphBlendMesh( parse( 'fixture.md2' ), new THREE.MeshBasicMaterial() );
	mesh.autoCreateAnimations( 6 );
	out.blend = {
		first: mesh.firstAnimation,
		animations: mesh.animationsList.map( ( a ) => ( { name: Object.keys( mesh.animationsMap ).find( ( k ) => mesh.animationsMap[ k ] === a ), start: a.start, end: a.end, fps: a.fps, duration: r( a.duration ) } ) ),
		steps: [],
	};
	mesh.playAnimation( 'run' );
	mesh.setAnimationWeight( 'run', 0.8 );
	for ( const delta of [ 0.1, 0.15, 0.2 ] ) {

		mesh.update( delta );
		out.blend.steps.push( weights( mesh ) );

	}

	mesh.setAnimationDirectionBackward( 'run' );
	for ( const delta of [ 0.1, 0.25 ] ) {

		mesh.update( delta );
		out.blend.steps.push( weights( mesh ) );

	}

	mesh.setAnimationDirectionForward( 'run' );
	mesh.animationsMap[ 'run' ].mirroredLoop = true;
	for ( const delta of [ 0.2, 0.3, 0.3 ] ) {

		mesh.update( delta );
		out.blend.steps.push( weights( mesh ) );

	}

}

// MorphAnimMesh.
{
	const geometry = parse( 'fixture.md2' );
	const mesh = new MorphAnimMesh( geometry, new THREE.MeshBasicMaterial() );
	mesh.playAnimation( 'run', 6 );
	out.anim = { steps: [] };
	for ( const delta of [ 0.05, 0.1 ] ) {

		mesh.updateAnimation( delta );
		out.anim.steps.push( weights( mesh ) );

	}

	mesh.setDirectionBackward();
	mesh.updateAnimation( 0.07 );
	out.anim.steps.push( weights( mesh ) );
	mesh.setDirectionForward();
	mesh.playAnimation( 'stand', 4 );
	mesh.updateAnimation( 0.1 );
	out.anim.steps.push( weights( mesh ) );

}

// MD2Character.
{
	const character = new MD2Character();
	character.scale = 2;
	character.loadParts( { baseUrl: '', body: 'fixture.md2', skins: [ 'a.png', 'b.png' ], weapons: [ [ 'fixture.md2', 'w.png' ], [ 'many.md2', 'v.png' ] ] } );
	const body = character.meshBody;
	const step = ( delta ) => {

		character.update( delta );
		return {
			body: weights( body ),
			weapons: character.weapons.map( weights ),
		};

	};

	out.character = {
		root: character.root.position.toArray().map( r ),
		first: character.activeAnimationClipName,
		weapon_names: character.weapons.map( ( w ) => w.name ),
		steps: [],
	};
	character.setAnimation( 'stand' );
	out.character.steps.push( step( 0.3 ) );
	character.setWeapon( 0 );
	out.character.steps.push( step( 0.2 ) );
	character.setPlaybackRate( 2 );
	out.character.steps.push( step( 0.1 ) );
	character.setAnimation( 'run' );
	out.character.steps.push( step( 0.15 ) );

}

// MD2CharacterComplex.
{
	const character = new MD2CharacterComplex();
	character.scale = 2;
	character.loadParts( {
		baseUrl: '', body: 'fixture.md2', skins: [ 'a.png' ], weapons: [ [ 'fixture.md2', 'w.png' ] ],
		animations: { move: 'run', idle: 'stand', jump: 'run', attack: 'stand', crouchMove: 'run', crouchIdle: 'stand', crouchAttack: 'run' },
		walkSpeed: 300, crouchSpeed: 150,
	} );
	character.controls = { moveForward: false, moveBackward: false, moveLeft: false, moveRight: false, crouch: false, jump: false, attack: false };
	out.complex = { steps: [] };
	const plan = [
		[ { moveForward: true }, 0.1 ], [ { moveForward: true }, 0.1 ], [ { moveForward: true, moveLeft: true }, 0.1 ],
		[ { moveBackward: true }, 0.05 ], [ {}, 0.1 ], [ {}, 0.2 ], [ { crouch: true, moveRight: true }, 0.1 ], [ {}, 0.3 ],
	];
	for ( const [ asked, delta ] of plan ) {

		for ( const key in character.controls ) character.controls[ key ] = !! asked[ key ];
		character.update( delta );
		out.complex.steps.push( {
			position: character.root.position.toArray().map( r ),
			turn: r( character.root.rotation.y ),
			speed: r( character.speed ),
			active: character.activeAnimation,
			body: weights( character.meshBody ),
		} );

	}

}

console.log( JSON.stringify( out ) );
