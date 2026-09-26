// Renders a scene with three.js 0.180's SVGRenderer, and writes the SVG it
// builds, attribute by attribute, into svg.json. Node has no DOM, so a stub
// records what the renderer sets. Run it where `three` is installed.
import { writeFileSync } from 'node:fs';
import * as THREE from 'three';
import { SVGRenderer } from 'three/examples/jsm/renderers/SVGRenderer.js';

function element( name ) {
	return {
		name, attributes: {}, style: {}, childNodes: [],
		setAttribute( k, v ) { this.attributes[ k ] = String( v ); },
		appendChild( c ) { this.childNodes.push( c ); },
		removeChild( c ) { this.childNodes.splice( this.childNodes.indexOf( c ), 1 ); },
	};
}
globalThis.document = { createElementNS: ( ns, name ) => element( name ) };

function scene() {
	const scene = new THREE.Scene();
	scene.add( new THREE.AmbientLight( 0x202040, 3 ) );
	const sun = new THREE.DirectionalLight( 0xffeecc, 2 );
	sun.position.set( 2, 4, 3 );
	scene.add( sun );
	const bulb = new THREE.PointLight( 0x88ccff, 1.5, 12 );
	bulb.position.set( - 3, 1, 2 );
	scene.add( bulb );

	// A lit box and a box of normals, a double-sided basic plane of vertex
	// colors, and a wireframe box.
	const box = new THREE.BoxGeometry( 1, 1, 1 );
	const lit = new THREE.Mesh( box, new THREE.MeshLambertMaterial( { color: 0xcc8844, emissive: 0x100000 } ) );
	lit.position.set( - 1.5, 0, 0 );
	lit.rotation.y = 0.5;
	scene.add( lit );
	const normals = new THREE.Mesh( box, new THREE.MeshNormalMaterial() );
	normals.position.set( 0, 0, - 1 );
	scene.add( normals );
	const plane = new THREE.PlaneGeometry( 2, 1 );
	plane.setAttribute( 'color', new THREE.Float32BufferAttribute( [ 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0 ], 3 ) );
	const painted = new THREE.Mesh( plane, new THREE.MeshBasicMaterial( { color: 0xffffff, vertexColors: true, side: THREE.DoubleSide, opacity: 0.75, transparent: true } ) );
	painted.position.set( 1.5, 0.5, 0.5 );
	scene.add( painted );
	const wire = new THREE.Mesh( box, new THREE.MeshBasicMaterial( { color: 0x33ff33, wireframe: true } ) );
	wire.position.set( 1.5, - 1, 0 );
	wire.scale.set( 0.5, 0.5, 0.5 );
	scene.add( wire );
	// Skipped: see-through, hidden, and a hidden parent's child.
	const clear = new THREE.Mesh( box, new THREE.MeshBasicMaterial( { opacity: 0, transparent: true } ) );
	scene.add( clear );
	const hidden = new THREE.Mesh( box, new THREE.MeshBasicMaterial() );
	hidden.visible = false;
	hidden.add( new THREE.Mesh( box, new THREE.MeshBasicMaterial() ) );
	scene.add( hidden );

	// A strip, segments, and a dashed line through the near plane.
	const strip = new THREE.BufferGeometry().setFromPoints( [ new THREE.Vector3( - 2, 1.5, 0 ), new THREE.Vector3( - 1, 2, 0 ), new THREE.Vector3( 0, 1.5, 0 ) ] );
	scene.add( new THREE.Line( strip, new THREE.LineBasicMaterial( { color: 0xff00ff } ) ) );
	const pairs = new THREE.BufferGeometry().setFromPoints( [ new THREE.Vector3( 0.5, - 1.5, 0 ), new THREE.Vector3( 1, - 2, 0 ), new THREE.Vector3( 2, - 1.5, 0 ), new THREE.Vector3( 2.5, - 2, 0 ) ] );
	scene.add( new THREE.LineSegments( pairs, new THREE.LineBasicMaterial( { color: 0x00ffff, opacity: 0.5 } ) ) );
	const through = new THREE.BufferGeometry().setFromPoints( [ new THREE.Vector3( - 0.5, - 0.5, 0 ), new THREE.Vector3( 0.25, - 0.25, 12 ) ] );
	scene.add( new THREE.Line( through, new THREE.LineDashedMaterial( { color: 0xffff00, dashSize: 2, gapSize: 0.5 } ) ) );

	// Points and a sprite.
	const dots = new THREE.BufferGeometry().setFromPoints( [ new THREE.Vector3( - 2, - 1, 1 ), new THREE.Vector3( - 1.5, - 1.5, 1 ) ] );
	scene.add( new THREE.Points( dots, new THREE.PointsMaterial( { color: 0xff8800, size: 0.2 } ) ) );
	const sprite = new THREE.Sprite( new THREE.SpriteMaterial( { color: 0x4444ff, opacity: 0.5 } ) );
	sprite.position.set( 0, 2.25, 1 );
	sprite.scale.set( 0.5, 0.25, 1 );
	scene.add( sprite );
	return scene;
}

const camera = new THREE.PerspectiveCamera( 50, 400 / 300, 0.1, 100 );
camera.position.set( 0, 1, 8 );
camera.lookAt( 0, 0, 0 );
camera.updateMatrixWorld();

function render( setup ) {
	const renderer = new SVGRenderer();
	renderer.setSize( 400, 300 );
	setup( renderer );
	const s = scene();
	renderer.render( s, camera );
	const svg = renderer.domElement;
	return {
		attributes: svg.attributes,
		background: svg.style.backgroundColor,
		paths: svg.childNodes.map( ( p ) => p.attributes ),
		info: renderer.info.render,
	};
}

writeFileSync( 'svg.json', JSON.stringify( {
	plain: render( () => {} ),
	precise: render( ( r ) => { r.setPrecision( 2 ); r.setQuality( 'low' ); r.setClearColor( 0x336699 ); r.overdraw = 0; } ),
	unsorted: render( ( r ) => { r.sortObjects = false; r.sortElements = false; } ),
} ) );
