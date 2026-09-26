// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// Writes output.json: how three.js 0.180 writes linear light out in each
// `outputColorSpace`, for `tests/test_output_color_space.mojo`. Run it with
// three 0.180 installed beside it: `node three_output.mjs > output.json`.
//
// For each space: the `mat3` elements `getEncodingComponents` puts in the
// shader, rounded by `toFixed( 4 )`, whether it applies sRGB's curve, and
// the bytes `linearToOutputTexel` gives a few linear colors.

import * as THREE from 'three';
import * as Spaces from 'three/examples/jsm/math/ColorSpaces.js';

THREE.ColorManagement.define( {
	[ Spaces.DisplayP3ColorSpace ]: Spaces.DisplayP3ColorSpaceImpl,
	[ Spaces.LinearDisplayP3ColorSpace ]: Spaces.LinearDisplayP3ColorSpaceImpl,
	[ Spaces.LinearRec2020ColorSpace ]: Spaces.LinearRec2020ColorSpaceImpl,
	[ Spaces.ExtendedSRGBColorSpace ]: Spaces.ExtendedSRGBColorSpaceImpl,
} );

const colors = [ [ 0.2, 0.5, 0.8 ], [ 1, 0, 0 ], [ 0.05, 0.9, 0.3 ], [ 0.001, 0.002, 0.5 ] ];
const oetf = ( v ) => ( v <= 0.0031308 ? v * 12.92 : Math.pow( v, 0.41666 ) * 1.055 - 0.055 );
const byte = ( v ) => Math.round( Math.min( 1, Math.max( 0, v ) ) * 255 );

const spaces = [ 'srgb', 'srgb-linear', 'display-p3', 'display-p3-linear', 'rec2020-linear', 'extended-srgb' ];
const out = spaces.map( ( space ) => {
	const m = new THREE.Matrix3();
	THREE.ColorManagement._getMatrix( m, THREE.ColorManagement.workingColorSpace, space );
	const elements = m.elements.map( ( v ) => + v.toFixed( 4 ) );
	const srgb = THREE.ColorManagement.getTransfer( space ) === THREE.SRGBTransfer;
	const bytes = colors.map( ( c ) => {
		// GLSL's `value.rgb * mat3( elements )`: the color dotted with each column.
		const rgb = [ 0, 1, 2 ].map( ( j ) => c[ 0 ] * elements[ j * 3 ] + c[ 1 ] * elements[ j * 3 + 1 ] + c[ 2 ] * elements[ j * 3 + 2 ] );
		return rgb.map( ( v ) => byte( srgb ? oetf( v ) : v ) );
	} );
	return { space, elements, srgb, bytes };
} );

console.log( JSON.stringify( { colors, spaces: out } ) );
