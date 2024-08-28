import { mat4, vec3, quat } from 'gl-matrix';
//import { WebIO } from '@gltf-transform/core';
//@ts-ignore
import modelData from '../models/lego_ellipsoid_500_strokes/stroke.json'
//import modelUrl from '../models/suzanne.glb?url';
//import modelUrl from '../models/box.gltf?url';

export async function loadModel() {

	const finalPositions = [];

	for (let o of Object.values(modelData.stroke_params)) {
		let ps = o.shape_params;
		let m = mat4.create();
		let s = vec3.fromValues(ps[0], ps[1], ps[2]);
		let q = quat.create();
		quat.fromEuler(q, ps[3] * 180 / Math.PI, ps[4] * 180 / Math.PI, ps[5] * 180 / Math.PI);
		let t = vec3.fromValues(ps[6], ps[7], ps[8]);
		mat4.fromRotationTranslationScale(m, q, t, s);
		finalPositions.push(...m);
		finalPositions.push(...o.color_params);
		finalPositions.push(o.density_params);
	}

	return new Float32Array(finalPositions);
}