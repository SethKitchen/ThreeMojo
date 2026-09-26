// Writes the USD fixtures in this folder and reads each with three.js
// 0.180's USDLoader, into usd.json. Run it where `three` is installed, with
// ../brick.png beside this folder. `TextureLoader` makes an <img>, which
// Node has not got, so a stand-in records the URL it is given.
import { readFileSync, writeFileSync } from 'node:fs';
import * as fflate from 'three/examples/jsm/libs/fflate.module.js';
import { USDLoader } from 'three/examples/jsm/loaders/USDLoader.js';

globalThis.document = {
	createElementNS: () => ( { addEventListener() {}, removeEventListener() {}, set src( url ) { this.url = url; } } ),
};

// A plain USDA scene. The Cube's quads have normals for each corner and
// texture coordinates with their own index. The Tri has no normals, so
// three.js computes flat ones. The binding </Materials/Red> names its
// material; </Root/Looks/Blue> names `Looks`, which three.js looks for.
const cube = `#usda 1.0
(
    defaultPrim = "Root"
    upAxis = "Y"
)

def Xform "Root"
{
    def Xform "Cube" (
        prepend apiSchemas = ["MaterialBindingAPI"]
    )
    {
        matrix4d xformOp:transform = ( (2, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (1, 2, 3, 1) )
        uniform token[] xformOpOrder = ["xformOp:transform"]
        rel material:binding = </Materials/Red>

        def Mesh "Box"
        {
            int[] faceVertexCounts = [4, 4]
            int[] faceVertexIndices = [0, 1, 2, 3, 4, 5, 6, 7]
            point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]
            normal3f[] normals = [(0, 0, -1), (0, 0, -1), (0, 0, -1), (0, 0, -1), (0, 0, 1), (0, 0, 1), (0, 0, 1), (0, 0, 1)] (
                interpolation = "faceVarying"
            )
            texCoord2f[] primvars:st = [(0, 0), (1, 0), (1, 1), (0, 1)] (
                interpolation = "faceVarying"
            )
            int[] primvars:st:indices = [0, 1, 2, 3, 3, 2, 1, 0]
        }
    }

    def Xform "Tri"
    {
        rel material:binding = </Root/Looks/Blue>
        def Mesh "Face"
        {
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0, 1, 2]
            point3f[] points = [(0, 0, 0), (2, 0, 0), (0, 2, 1)]
            float2[] primvars:st = [(0, 0), (1, 0), (0, 1)]
        }
    }

    def Xform "not-a-word"
    {
    }
}

def Scope "Materials"
{
    def Material "Red"
    {
        token outputs:surface.connect = </Materials/Red/Surface.outputs:surface>

        def Shader "Surface"
        {
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor = (0.8, 0.1, 0.05)
            color3f inputs:emissiveColor = (0.1, 0.2, 0.3)
            float inputs:roughness = 0.3
            float inputs:metallic = 0.5
            float inputs:clearcoat = 0.25
            float inputs:clearcoatRoughness = 0.75
            float inputs:ior = 1.4
            token outputs:surface
        }
    }
}
`;

// A USDZ: the first file is the stage. It references a mesh in another
// layer, and a material whose maps are the archive's PNG, one of them
// missing.
const stage = `#usda 1.0

def Xform "Scene"
{
    def Xform "Thing" (
        prepend references = @./geo.usda@</Shape>
    )
    {
        rel material:binding = </Looks/Painted>
    }
}

def Scope "Looks"
{
    def Material "Painted"
    {
        token outputs:surface.connect = </Looks/Painted/PBR.outputs:surface>

        def Shader "PBR"
        {
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor.connect = </Looks/Painted/Color.outputs:rgb>
            normal3f inputs:normal.connect = </Looks/Painted/Bumps.outputs:rgb>
            float inputs:roughness.connect = </Looks/Painted/Color.outputs:r>
            float inputs:occlusion.connect = </Looks/Painted/Color.outputs:g>
            token outputs:surface
        }

        def Shader "Transform2d_diffuse"
        {
            uniform token info:id = "UsdTransform2d"
            float inputs:rotation = 45
            float2 inputs:scale = (2, 3)
            float2 inputs:translation = (0.25, 0.5)
        }

        def Shader "Color"
        {
            uniform token info:id = "UsdUVTexture"
            asset inputs:file = @textures/brick.png@
            token inputs:wrapS = "repeat"
            token inputs:wrapT = "mirror"
            float3 outputs:rgb
        }

        def Shader "Bumps"
        {
            uniform token info:id = "UsdUVTexture"
            asset inputs:file = @textures/missing.png@
            token inputs:wrapS = "clamp"
            float3 outputs:rgb
        }
    }
}
`;
const geo = `#usda 1.0

def Xform "Other"
{
    def Mesh "Wrong"
    {
        point3f[] points = [(9, 9, 9), (9, 9, 9), (9, 9, 9)]
    }
}

def Mesh "Shape"
{
    int[] faceVertexCounts = [3, 3]
    int[] faceVertexIndices = [0, 1, 2, 0, 2, 3]
    point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
    normal3f[] normals = [(0, 0, 1), (0, 0, 1), (0, 0, 1), (0, 0, 1)]
}
`;

const files = {
	'cube.usda': Buffer.from( cube ),
	'scene.usdz': Buffer.from( fflate.zipSync( {
		'scene.usda': fflate.strToU8( stage ),
		'geo.usda': fflate.strToU8( geo ),
		'textures/brick.png': new Uint8Array( readFileSync( '../brick.png' ) ),
	}, { level: 0, mtime: new Date( '2026-01-01T00:00:00Z' ) } ) ),
};

const round = ( a ) => Array.from( a, ( x ) => Number.isNaN( x ) ? 'NaN' : x );

function texture( map ) {
	if ( ! map ) return null;
	return {
		url: map.image ? ( map.image.url.startsWith( 'blob:' ) ? 'blob' : map.image.url ) : null,
		wrapS: map.wrapS, wrapT: map.wrapT, colorSpace: map.colorSpace,
		rotation: map.rotation, repeat: [ map.repeat.x, map.repeat.y ], offset: [ map.offset.x, map.offset.y ],
	};
}

function describe( object ) {
	const out = {
		name: object.name, type: object.type,
		position: object.position.toArray(), quaternion: object.quaternion.toArray(), scale: object.scale.toArray(),
		children: object.children.map( describe ),
	};
	if ( object.isMesh ) {
		out.attributes = {};
		for ( const [ key, attribute ] of Object.entries( object.geometry.attributes ) ) out.attributes[ key ] = round( attribute.array );
		const m = object.material;
		out.material = {
			color: m.color.toArray(), emissive: m.emissive.toArray(), roughness: m.roughness, metalness: m.metalness,
			clearcoat: m.clearcoat, clearcoatRoughness: m.clearcoatRoughness, ior: m.ior,
			map: texture( m.map ), emissiveMap: texture( m.emissiveMap ), normalMap: texture( m.normalMap ),
			roughnessMap: texture( m.roughnessMap ), metalnessMap: texture( m.metalnessMap ),
			clearcoatMap: texture( m.clearcoatMap ), clearcoatRoughnessMap: texture( m.clearcoatRoughnessMap ),
			aoMap: texture( m.aoMap ),
		};
	}
	return out;
}

const reference = {};
for ( const [ name, bytes ] of Object.entries( files ) ) {
	writeFileSync( name, bytes );
	const buffer = bytes.buffer.slice( bytes.byteOffset, bytes.byteOffset + bytes.length );
	const input = name.endsWith( '.usda' ) ? bytes.toString( 'utf8' ) : buffer;
	reference[ name ] = describe( new USDLoader().parse( input ) );
}
writeFileSync( 'usd.json', JSON.stringify( reference ) );
