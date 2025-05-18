import { mat4, vec3, quat } from 'gl-matrix';
//import { WebIO } from '@gltf-transform/core';
//@ts-ignore
import modelData from '../models/lego_line/temp.json'
//import modelData from '../models/chair_line_1000/stroke.json'
//import modelData from '../models/lego_ellipsoid_1250/stroke.json'
//import modelData from '../models/lego_cylinder/temp.json'
//import modelData from '../models/lego_mix_ellipsoid_obb_line/strokes.proc.json'
//import modelData from '../models/lego_mix_ellipsoid_obb_line/strokes.json'
//import modelData from '../models/lego_mix_line_aabb/temp.json'
//import modelData from '../models/lego_mix_ellipsoid_tetrahedron/temp.json'
//import modelData from '../models/lego_ellipsoid_softmax/stroke.json'
//import modelData from '../models/lego_bezier_max/stroke.json'
//import modelData from '../models/lego_octahedron_max/stroke.json'
//import modelData from '../models/lego_tetrahedron_max/stroke.json'
//import modelData from '../models/lego_cube_max/stroke.json'
//import modelData from '../models/lego_ellipsoid_max/stroke.json'
//import modelData from '../models/lego_ellipsoid_500_strokes/stroke.json'
//import modelUrl from '../models/suzanne.glb?url';
//import modelUrl from '../models/box.gltf?url';

/**
 * ref: https://github.com/toji/gl-matrix/issues/329
 * Returns an euler angle representation of a quaternion
 * @param  {vec3} out Euler angles, pitch-yaw-roll
 * @param  {quat} mat Quaternion
 * @return {vec3} out
 */
function getEuler(out: vec3, quat: quat) {
	let x = quat[0],
		y = quat[1],
		z = quat[2],
		w = quat[3],
		x2 = x * x,
		y2 = y * y,
		z2 = z * z,
		w2 = w * w;
	let unit = x2 + y2 + z2 + w2;
	let test = x * w - y * z;
	if (test > 0.499995 * unit) { //TODO: Use glmatrix.EPSILON
		// singularity at the north pole
		out[0] = Math.PI / 2;
		out[1] = 2 * Math.atan2(y, x);
		out[2] = 0;
	} else if (test < -0.499995 * unit) { //TODO: Use glmatrix.EPSILON
		// singularity at the south pole
		out[0] = -Math.PI / 2;
		out[1] = 2 * Math.atan2(y, x);
		out[2] = 0;
	} else {
		out[0] = Math.asin(2 * (x * z - w * y));
		out[1] = Math.atan2(2 * (x * w + y * z), 1 - 2 * (z2 + w2));
		out[2] = Math.atan2(2 * (x * y + z * w), 1 - 2 * (y2 + z2));
	}
	// TODO: Return them as degrees and not as radians
	return out;
}

export async function loadModel(): Promise<Float32Array> {

	const ALIGN_SIZE = 27;			// max size of stroke for align
	const PARTITION_COUNT = 10;		// count of capsules which segment from bezier
	const primitiveTypeTable: { [key: string]: number } = {
		"sphere": 1,
		"ellipsoid": 1,
		"cube": 2,
		"tetrahedron": 3,
		"octahedron": 4,
		"capsule": 5,
		"line": 5,
		"line_a": 5,
		"cubic_bezier": 5,
		"cube_a": 2,
		"aabb": 2,
		"tetrahedron_a": 3,
		"octahedron_a": 4,
		"capsule_a": 5,
		"cylinder": 6,
		"roundcube": 7,
		"mix_ellipsoid_obb_line": 8,
	};	// 带_a的指multiscale，否则是singlescale
	const finalPositions = [];

	// modelData.shape_type = "mix_ellipsoid_obb_line"
	// modelData.stroke_params = {
	// 	"strokeNo.1": {
	// 		shape_params: [-1e7, -1e7, 0, 1, 0, 1, 1, 1, 1, 0, 0, 1, 0, 0],
	// 		color_params: [1.0, 0, 0],
	// 		density_params: 1.0,
	// 	},
	// 	"strokeNo.2": {
	// 		shape_params: [-1e7, 0, 1e-7, 2, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1],
	// 		color_params: [0, 1.0, 0],
	// 		density_params: 1.0,
	// 	},
	// 	"strokeNo.3": {
	// 		shape_params: [-1e7, 1e-7, 0, 1.5, 0, 1, 2, 1, 0, 0, 0, 0, 1, 0],
	// 		color_params: [0, 0, 1.0],
	// 		density_params: 1.0,
	// 	},
	// }

	for (let [strokeNo, o] of Object.entries(modelData.stroke_params)) {
		const m = /strokeNo.(\d+)/.exec(strokeNo);
		if (m === null) { continue; }
		const stroke_id = Number(m[1]); 
		const shape_type = modelData.shape_type === 'mix' ? o.stroke_type : modelData.shape_type;
		const shape_type_id = primitiveTypeTable[shape_type];
		if (shape_type === "cubic_bezier") {
			let ps = o.shape_params;
			let p0 = vec3.fromValues(ps[0], ps[1], ps[2]);
			let p1 = vec3.fromValues(ps[3], ps[4], ps[5]);
			let p2 = vec3.fromValues(ps[6], ps[7], ps[8]);
			let p3 = vec3.fromValues(ps[9], ps[10], ps[11]);
			let ra = ps[12];
			let rb = ps[13];
			for (let i = 0; i < PARTITION_COUNT; ++i) {
				let e1 = vec3.create();
				let e2 = vec3.create();
				let t1 = i / PARTITION_COUNT;
				let t2 = (i + 1) / PARTITION_COUNT;
				vec3.bezier(e1, p0, p1, p2, p3, t1);
				vec3.bezier(e2, p0, p1, p2, p3, t2);
				let _r1 = ra + (rb - ra) * t1;
				let _r2 = ra + (rb - ra) * t2;
				let e0 = vec3.create();								// center point of capsule
				vec3.add(e0, e1, e2);
				vec3.scale(e0, e0, 0.5);
				let d = vec3.create();
				vec3.sub(d, e1, e2);
				let rt = vec3.create();
				vec3.sub(rt, e1, e0);
				vec3.normalize(rt, rt);
				let rt_axis = vec3.fromValues(rt[1], -rt[0], 0);	// cross of (0, 0, 1) and rt
				vec3.normalize(rt_axis, rt_axis);
				let rt_angle = Math.acos(rt[2]);		   		   	// dot of (0, 0, 1) and rt
				let _q = quat.create();
				quat.setAxisAngle(_q, rt_axis, rt_angle);
				let ea = vec3.create();
				getEuler(ea, _q);
				{
					let ps = [1, ea[1], ea[0], ea[2], ...e0, _r1, _r2, vec3.len(d),];
					let m = mat4.create();
					let s = vec3.fromValues(ps[0], ps[0], ps[0]);
					let q = quat.create();
					quat.fromEuler(q, ps[1] * 180 / Math.PI, ps[2] * 180 / Math.PI, ps[3] * 180 / Math.PI);
					let t = vec3.fromValues(ps[4], ps[5], ps[6]);
					mat4.fromRotationTranslationScale(m, q, t, s);
					finalPositions.push(...m);
					finalPositions.push(...o.color_params);
					finalPositions.push(o.density_params);
					finalPositions.push(shape_type_id);
					finalPositions.push(stroke_id);
					finalPositions.push(ps[7], ps[8], ps[9]);
					while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
				}
			}
		}
		else if (shape_type === "ellipsoid" || shape_type === "cube_a" || shape_type === "tetrahedron_a" || 
			shape_type === "octahedron_a" || shape_type === "cylinder" || shape_type === "roundcube") {
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
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			if (shape_type === "roundcube") { finalPositions.push(ps[9]); }
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
		else if (shape_type === "sphere" || shape_type === "cube" || shape_type === "tetrahedron" || shape_type === "octahedron") {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[0], ps[0], ps[0]);
			let q = quat.create();
			quat.fromEuler(q, ps[1] * 180 / Math.PI, ps[2] * 180 / Math.PI, ps[3] * 180 / Math.PI);
			let t = vec3.fromValues(ps[4], ps[5], ps[6]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
		else if (shape_type === "aabb") {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[0], ps[1], ps[2]);
			let q = quat.create();
			let t = vec3.fromValues(ps[3], ps[4], ps[5]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
		else if (shape_type === "capsule") {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[0], ps[0], ps[0]);
			let q = quat.create();
			quat.fromEuler(q, ps[1] * 180 / Math.PI, ps[2] * 180 / Math.PI, ps[3] * 180 / Math.PI);
			let t = vec3.fromValues(ps[4], ps[5], ps[6]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			finalPositions.push(ps[7], ps[8], ps[9]);
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
		else if (shape_type === "line") {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[2], ps[2], ps[2]);
			let q = quat.create();
			quat.fromEuler(q, ps[3] * 180 / Math.PI, ps[4] * 180 / Math.PI, ps[5] * 180 / Math.PI);
			let rx = quat.create();
			quat.rotateX(rx, rx, Math.PI / 2);
			quat.multiply(q, q, rx);
			let t = vec3.fromValues(ps[6], ps[7], ps[8]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			let h = ps[0] * 2, r_diff = ps[1];
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			finalPositions.push(1 + r_diff, 1 - r_diff, h);
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
		else if (shape_type === "line_a") {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[2], ps[3], ps[4]);
			let q = quat.create();
			quat.fromEuler(q, ps[5] * 180 / Math.PI, ps[6] * 180 / Math.PI, ps[7] * 180 / Math.PI);
			let t = vec3.fromValues(ps[8], ps[9], ps[10]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			let rx = mat4.create();
			mat4.rotateX(rx, rx, Math.PI / 2);
			mat4.multiply(m, m, rx);
			let h = ps[0] * 2, r_diff = ps[1];
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			finalPositions.push(1 + r_diff, 1 - r_diff, h);
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
		else if (shape_type === "capsule_a") {
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
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			finalPositions.push(ps[9], ps[10], ps[11]);
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
		else if (shape_type === "mix_ellipsoid_obb_line") {
			let ps = o.shape_params;
			let m = mat4.create();
			let s = vec3.fromValues(ps[5], ps[6], ps[7]);
			let q = quat.create();
			quat.fromEuler(q, ps[8] * 180 / Math.PI, ps[9] * 180 / Math.PI, ps[10] * 180 / Math.PI);
			let t = vec3.fromValues(ps[11], ps[12], ps[13]);
			mat4.fromRotationTranslationScale(m, q, t, s);
			finalPositions.push(...m);
			finalPositions.push(...o.color_params);
			finalPositions.push(o.density_params);
			finalPositions.push(shape_type_id);
			finalPositions.push(stroke_id);
			let [w1, w2, w3] = ps.slice(0, 3).map(Math.exp);
			let ws = w1 + w2 + w3;
			[w1, w2, w3] = [w1 / ws, w2 / ws, w3 / ws];
			if (w1 >= w2 && w2 >= w3) [w1, w2, w3] = [1, 0, 0];
			else if (w2 >= w1 && w2 >= w3) [w1, w2, w3] = [0, 1, 0];
			else [w1, w2, w3] = [0, 0, 1];
			finalPositions.push(ps[3], ps[4], w1, w2, w3);
			while (finalPositions.length % ALIGN_SIZE !== 0) { finalPositions.push(0); }
		}
	}


	return new Float32Array(finalPositions);
}