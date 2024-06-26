import { WebIO } from '@gltf-transform/core';
//@ts-ignore
import modelUrl from '../models/suzanne.glb?url';
// import modelUrl from '../models/box.gltf?url';

export async function loadModel() {
	const io = new WebIO({credentials: 'include'});
	const doc = await io.read(modelUrl);

	const positions = doc.getRoot().listMeshes()[0].listPrimitives()[0].getAttribute('POSITION')!.getArray()!;
	const indices = doc.getRoot().listMeshes()[0].listPrimitives()[0].getIndices()!.getArray()!;
	const finalPositions = [];

	for (let i = 0; i < indices.length; i++) {
		const index = indices[i] * 3;

		finalPositions.push(positions[index    ]);
		finalPositions.push(positions[index + 1]);
		finalPositions.push(positions[index + 2]);
	}
	return new Float32Array(finalPositions);
}