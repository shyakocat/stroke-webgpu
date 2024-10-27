import { mat4, vec3, quat } from 'gl-matrix';
//import { WebIO } from '@gltf-transform/core';
//@ts-ignore
import modelData from '../models/lego_octahedron_max/stroke.json'
//import modelData from '../models/lego_tetrahedron_max/stroke.json'
//import modelData from '../models/lego_cube_max/stroke.json'
// import modelData from '../models/lego_ellipsoid_500_strokes/stroke.json'
//import modelUrl from '../models/suzanne.glb?url';
//import modelUrl from '../models/box.gltf?url';

export async function loadModel() {

	const finalPositions = [];

	// modelData.stroke_params = {
	// 	"strokeNo.1": {
	// 		shape_params: [1.0, 1.0, 1.0, 0, 0, 0, 0, 0, 0],
	// 		color_params: [1.0, 0, 0],
	// 		density_params: 1.0,
	// 	},
	// 	// "strokeNo.2": {
	// 	// 	shape_params: [1.0, 1.0, 1.0, 0, 0, 0, -2, 0, 0],
	// 	// 	color_params: [0, 1.0, 0],
	// 	// 	density_params: 1.0,
	// 	// },
	// 	// "strokeNo.3": {
	// 	// 	shape_params: [0.5, 1.0, 0.7, 0.1, 0.5, -0.2, 0.1, -0.5, 0.33],
	// 	// 	color_params: [0, 0, 1.0],
	// 	// 	density_params: 1.0,
	// 	// },
	// 	// "strokeNo.4": {
	// 	// 	shape_params: [1.0, 1.0, 1.0, 0, 0, 0, -4, 0, 0],
	// 	// 	color_params: [0, 0, 1.0],
	// 	// 	density_params: 1.0,
	// 	// },
	// }

	if (modelData.shape_type === "ellipsoid") {
		for (let o of Object.values(modelData.stroke_params)) {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[0], ps[1], ps[2]);
			vec3.scale(s, s, 1)
			let q = quat.create();
			quat.fromEuler(q, ps[3] * 180 / Math.PI, ps[4] * 180 / Math.PI, ps[5] * 180 / Math.PI);
			let t = vec3.fromValues(ps[6], ps[7], ps[8]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
		}
	}
	else if (modelData.shape_type === "cube" ||
		modelData.shape_type === "tetrahedron" ||
		modelData.shape_type === "octahedron") {
		for (let o of Object.values(modelData.stroke_params)) {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[0], ps[0], ps[0]);
			vec3.scale(s, s, 1)
			let q = quat.create();
			quat.fromEuler(q, ps[1] * 180 / Math.PI, ps[2] * 180 / Math.PI, ps[3] * 180 / Math.PI);
			let t = vec3.fromValues(ps[4], ps[5], ps[6]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
		}
	}

	return new Float32Array(finalPositions);
}