// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes three.json and coaster.json: what three.js 0.180's geometry tools
// make, for `tests/test_geometry_tools.mojo`. Run it with three 0.180
// installed beside it: `node three_tools.mjs > three.json` and
// `node three_tools.mjs coaster > coaster.json`. The roller coaster is in a
// file of its own, as it is most of the numbers.
//
// - `hilbert2d`, `hilbert3d`: the points of each curve, three numbers each.
// - `gosper`: the number of points, and every 97th point and the last.
// - `frame_corners`: a camera's projection, its view and its estimated field
//   of view after `frameCorners`, for a square-on and a tilted rectangle.
// - `breaker`: the pieces ConvexObjectBreaker cuts from a turned box, and
//   the debris it breaks a box into, with `Math.random` seeded from 3.
//   A uuid's draws are left out, as the port has no uuids.
// - `uvs_debug`, `uvs_debug_edge`: the corners and the labels UVsDebug draws
//   for a box at 64 pixels and a triangle at the right edge at 32,
//   recorded from a stand-in canvas.
// - `tube_painter`: the positions, normals and colors a TubePainter draws
//   for three strokes, the second thicker, and a stroke to where it is.
// - `roller_coaster`, in coaster.json: the attributes of the track, lifters and shadow of
//   webxr_vr_rollercoaster's curve at eight divisions, and of the sky and
//   the trees on a plane, with `Math.random` drawn from
//   `MathUtils.seededRandom` from 5 and from 9.

import * as THREE from 'three';
import * as GeometryUtils from 'three/examples/jsm/utils/GeometryUtils.js';
import { frameCorners } from 'three/examples/jsm/utils/CameraUtils.js';
import * as Coaster from 'three/examples/jsm/misc/RollerCoaster.js';
import { TubePainter } from 'three/examples/jsm/misc/TubePainter.js';
import { ConvexObjectBreaker } from 'three/examples/jsm/misc/ConvexObjectBreaker.js';
import { UVsDebug } from 'three/examples/jsm/utils/UVsDebug.js';

const r = ( v ) => + v.toFixed( 6 );
const flat = ( points ) => points.flatMap( ( p ) => [ r( p.x ), r( p.y ), r( p.z ) ] );
const out = {};
const coaster = {};
{
	const path = [];
	const labels = [];
	const context = {
		fillStyle: '', font: '',
		fillRect() {}, beginPath() {}, closePath() {}, stroke() {},
		moveTo( x, y ) { path.push( r( x ), r( y ) ); },
		lineTo( x, y ) { path.push( r( x ), r( y ) ); },
		fillText( text, x, y ) { labels.push( [ String( text ), r( x ), r( y ), parseInt( this.font ), this.fillStyle ] ); },
	};
	globalThis.document = { createElement: () => ( { getContext: () => context } ) };
	UVsDebug( new THREE.BoxGeometry( 1, 1, 1 ), 64 );
	out.uvs_debug = { path: path.splice( 0 ), labels: labels.splice( 0 ) };
	// A triangle near the right edge, whose labels three.js writes twice.
	const edge = new THREE.BufferGeometry();
	edge.setAttribute( 'uv', new THREE.Float32BufferAttribute( [ 0.9, 0.1, 1, 0.2, 1, 0.9 ], 2 ) );
	UVsDebug( edge, 32 );
	out.uvs_debug_edge = { path, labels };
}
{
	const breaker = new ConvexObjectBreaker();
	const piece = ( mesh ) => mesh && ( {
		position: mesh.position.toArray().map( r ),
		count: mesh.geometry.attributes.position.count,
		mass: r( mesh.userData.mass ),
		breakable: mesh.userData.breakable,
	} );
	const box = new THREE.Mesh( new THREE.BoxGeometry( 2, 2, 2 ) );
	box.position.set( 1, 0, 0 );
	box.rotation.y = 0.3;
	breaker.prepareBreakableObject( box, 10, new THREE.Vector3( 1, 2, 3 ), new THREE.Vector3( 0, 1, 0 ), true );
	const output = {};
	const plane = new THREE.Plane( new THREE.Vector3( 1, 0.2, 0 ).normalize(), - 1.1 );
	breaker.cutByPlane( box, plane, output );
	out.breaker = { cut: [ piece( output.object1 ), piece( output.object2 ) ] };
	// Seed every draw but a uuid's.
	let first = true;
	const plain = Math.random;
	Math.random = () => {

		if ( new Error().stack.includes( 'generateUUID' ) ) return plain();
		if ( first ) {

			first = false;
			return THREE.MathUtils.seededRandom( 3 );

		}

		return THREE.MathUtils.seededRandom();

	};
	const big = new THREE.Mesh( new THREE.BoxGeometry( 3, 3, 3 ) );
	breaker.prepareBreakableObject( big, 20, new THREE.Vector3(), new THREE.Vector3(), true );
	const debris = breaker.subdivideByImpact( big, new THREE.Vector3( 0, 1.5, 0.2 ), new THREE.Vector3( 0, - 1, 0 ), 2, 1 );
	Math.random = plain;
	out.breaker.debris = debris.map( piece );
}
{
	const painter = TubePainter();
	painter.moveTo( new THREE.Vector3( 0, 1, 0 ) );
	painter.lineTo( new THREE.Vector3( 0.3, 1.1, 0.2 ) );
	painter.setSize( 2 );
	painter.lineTo( new THREE.Vector3( 0.5, 1.4, - 0.1 ) );
	painter.lineTo( new THREE.Vector3( 0.5, 1.4, - 0.1 ) );
	painter.lineTo( new THREE.Vector3( 0.2, 1.6, 0.4 ) );
	const geometry = painter.mesh.geometry;
	const count = geometry.drawRange.count;
	const take = ( name ) => Array.from( geometry.attributes[ name ].array.slice( 0, count * 3 ) ).map( r );
	out.tube_painter = { count, position: take( 'position' ), normal: take( 'normal' ), color: take( 'color' ) };
}

out.hilbert2d = {
	plain: flat( GeometryUtils.hilbert2D() ),
	moved: flat( GeometryUtils.hilbert2D( new THREE.Vector3( 1, 2, 3 ), 4, 2, 1, 2, 3, 0 ) ),
};
out.hilbert3d = {
	plain: flat( GeometryUtils.hilbert3D() ),
	moved: flat( GeometryUtils.hilbert3D( new THREE.Vector3( - 1, 0, 2 ), 6, 2, 7, 6, 5, 4, 3, 2, 1, 0 ) ),
};
{
	const points = GeometryUtils.gosper( 2 );
	const count = points.length / 3;
	const samples = [];
	for ( let i = 0; i < count; i += 97 ) samples.push( i, r( points[ 3 * i ] ), r( points[ 3 * i + 1 ] ), r( points[ 3 * i + 2 ] ) );
	samples.push( count - 1, r( points[ 3 * count - 3 ] ), r( points[ 3 * count - 2 ] ), r( points[ 3 * count - 1 ] ) );
	out.gosper = { count, samples };
}

out.frame_corners = [];
for ( const [ corners, estimate ] of [
	[ [ [ - 2, - 1, 0 ], [ 3, - 1, 0 ], [ - 2, 2, 0 ] ], false ],
	[ [ [ 0, 0, - 1 ], [ 2, 1, - 2 ], [ 0, 3, - 1 ] ], true ],
] ) {

	const camera = new THREE.PerspectiveCamera( 50, 1.5, 0.5, 50 );
	camera.position.set( 1, 2, 10 );
	const [ a, b, c ] = corners.map( ( v ) => new THREE.Vector3( ...v ) );
	frameCorners( camera, a, b, c, estimate );
	camera.updateMatrixWorld();
	out.frame_corners.push( {
		projection: camera.projectionMatrix.elements.map( r ),
		view: camera.matrixWorldInverse.elements.map( r ),
		fov: r( camera.fov ),
	} );

}

// The curve of three.js's roller coaster example, as a `Curve`.
class Track extends THREE.Curve {

	getPoint( t, target = new THREE.Vector3() ) {

		t = t * Math.PI * 2;
		const x = Math.sin( t * 3 ) * Math.cos( t * 4 ) * 50;
		const y = Math.sin( t * 10 ) * 2 + Math.cos( t * 17 ) * 2 + 5;
		const z = Math.sin( t ) * Math.sin( t * 4 ) * 50;
		return target.set( x, y, z ).multiplyScalar( 2 );

	}

}

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
const attributes = ( geometry ) => {

	const o = {};
	for ( const name in geometry.attributes ) o[ name ] = Array.from( geometry.attributes[ name ].array ).map( r );
	return o;

};
{
	const track = new Track();
	seed( 5 );
	const sky = attributes( new Coaster.SkyGeometry() );
	const ground = new THREE.Mesh( new THREE.PlaneGeometry( 100, 100 ).rotateX( - Math.PI / 2 ).translate( 0, 1.5, 0 ) );
	ground.updateMatrixWorld();
	seed( 9 );
	const trees = attributes( new Coaster.TreesGeometry( ground ) );
	coaster.roller_coaster = {
		track: attributes( new Coaster.RollerCoasterGeometry( track, 8 ) ),
		lifters: attributes( new Coaster.RollerCoasterLiftersGeometry( track, 8 ) ),
		shadow: attributes( new Coaster.RollerCoasterShadowGeometry( track, 8 ) ),
		sky,
		trees,
	};
}

console.log( JSON.stringify( process.argv[ 2 ] === 'coaster' ? coaster : out ) );
