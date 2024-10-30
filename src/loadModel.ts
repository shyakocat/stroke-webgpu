import { mat4, vec3, quat } from 'gl-matrix';
//import { WebIO } from '@gltf-transform/core';
//@ts-ignore
import modelData from '../models/lego_bezier_max/stroke.json'
//import modelData from '../models/lego_octahedron_max/stroke.json'
//import modelData from '../models/lego_tetrahedron_max/stroke.json'
//import modelData from '../models/lego_cube_max/stroke.json'
//import modelData from '../models/lego_ellipsoid_max/stroke.json'
// import modelData from '../models/lego_ellipsoid_500_strokes/stroke.json'
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

export async function loadModel() {

	const finalPositions = [];

	// modelData.shape_type = "cubic_bezier"
	// modelData.stroke_params = {
	// 	// "strokeNo.1": {
	// 	// 	shape_params: [1.0, 1.0, 1.0, 0, 0, 0, 0, 0, 0, 1.0, 2.0],
	// 	// 	color_params: [1.0, 0, 0],
	// 	// 	density_params: 1.0,
	// 	// },
	// 	// "strokeNo.2": {
	// 	// 	shape_params: [1.0, 1.0, 1.0, 0, 0, 0, -2, 0, 0, 1.0, 0.6],
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
	// 	"strokeNo.5": {
	// 		shape_params: [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.1, 0.1],
	// 		color_params: [1.0, 0, 0],
	// 		density_params: 1.0,
	// 	},
	// 	// "strokeNo.6": {
	// 	// 	shape_params: [1.0, 0, 0, 0, 0, 0, 0, 0.1, 2],
	// 	// 	color_params: [0, 1, 0],
	// 	// 	density_params: 1.0,
	// 	// },
	// 	// "strokeNo.7": {
	// 	// 	shape_params: [1.0, 0, 0, 0, 0, 0, 1, 0.1, 2],
	// 	// 	color_params: [1, 0, 0],
	// 	// 	density_params: 1.0,
	// 	// },
	// }

	if (modelData.shape_type === "cubic_bezier") {
		const PARTITION_COUNT = 10;
		let strokeNo = 0;
		let params: any = {};
		for (let o of Object.values(modelData.stroke_params)) {
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
				let radius = ra + (ra - rb) * (t1 + t2) * 0.5;
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
				params[`strokeNo.${++strokeNo}`] = {
					shape_params: [1, ea[1], ea[0], ea[2], ...e0, radius, vec3.len(d),],
					color_params: o.color_params,
					density_params: o.density_params,
				}
			}
		}
		modelData.shape_type = "capsule";
		modelData.stroke_params = params;
	}

	if (modelData.shape_type === "ellipsoid") {
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
	}
	else if (modelData.shape_type === "cube" ||
		modelData.shape_type === "tetrahedron" ||
		modelData.shape_type === "octahedron") {
		for (let o of Object.values(modelData.stroke_params)) {
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
		}
	}
	else if (modelData.shape_type === "capsule") {
		for (let o of Object.values(modelData.stroke_params)) {
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
			finalPositions.push(ps[7], ps[8]);
		}
	}

	return new Float32Array(finalPositions);
}