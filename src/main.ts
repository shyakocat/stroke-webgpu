import { mat4, vec3, quat, mat3 } from 'gl-matrix'
//@ts-ignore
import fullscreenQuadWGSL from '../shaders/fullscreenQuad.wgsl?raw';
//@ts-ignore
import computeRasterizerWGSL from '../shaders/computeRasterizer.wgsl?raw';
import { loadModel } from './loadModel.ts';
import Stats from 'stats.js';


import testData from '../test/transforms_test.json';

type Tuple16<T> = [T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T];

const ENABLE_FXAA = 0;

//@ts-ignore
const mode = import.meta.env.VITE_EXEC_MODE === "test" ? "test" : "viewer";
init(mode);

async function init(mode: "viewer" | "test" = "viewer") {
    const adapter = await navigator.gpu.requestAdapter() as GPUAdapter;
    const device = await adapter.requestDevice();
    const canvas = document.querySelector("canvas") as HTMLCanvasElement;
    const context = canvas.getContext("webgpu") as GPUCanvasContext;
    canvas.width = canvas.offsetWidth
    canvas.height = canvas.offsetHeight

    const devicePixelRatio = window.devicePixelRatio || 1;
    const presentationSize: [number, number] = [
        Math.floor(canvas.clientWidth /* * devicePixelRatio */),
        Math.floor(canvas.clientHeight /* * devicePixelRatio */),
    ];

    const presentationFormat = navigator.gpu.getPreferredCanvasFormat();
    context.configure({
        device,
        format: presentationFormat,
        alphaMode: "opaque"
    });

    const strokeData = await loadModel();

    const cameraCtrl = mode === "viewer" ? new CameraWander(...presentationSize) : new CameraCustom();
    const { addRasterizerPass, outputBuffer } = createRasterizerPass(device, presentationSize, strokeData, cameraCtrl);
    const { addFullscreenPass } = createFullscreenPass(device, presentationSize, presentationFormat, outputBuffer);

    if (mode === "viewer") {
        var stats = new Stats();
        stats.showPanel(0); // 0: fps, 1: ms, 2: mb, 3+: custom
        document.body.appendChild(stats.dom);

        function draw() {

            //stats.begin()

            const commandEncoder = device.createCommandEncoder();

            addRasterizerPass(commandEncoder);
            addFullscreenPass(context, commandEncoder);

            device.queue.submit([commandEncoder.finish()]);

            //stats.end()
            stats.update()

            requestAnimationFrame(draw);
        }

        draw();
    }
    else if (mode === "test") {

        const cam = <CameraCustom>cameraCtrl;

        const [WIDTH, HEIGHT] = presentationSize;
        cam.projectionMatrix = mat4.create()
        mat4.perspective(cam.projectionMatrix, testData.camera_angle_x, WIDTH / HEIGHT, 0.01, 10)

        const magic_scale = 1.5
        cam.modelMatrix = mat4.create();
        mat4.scale(cam.modelMatrix, cam.modelMatrix, vec3.fromValues(magic_scale, magic_scale, magic_scale));

        const frameIter = testData.frames[Symbol.iterator]()

        async function exportCanvasAsPNG(canvas: HTMLCanvasElement, fileName: string) {
            return new Promise((resolve, reject) => {
                canvas.toBlob(async (blob) => {
                    if (blob) {
                        try {
                            const formData = new FormData()
                            formData.append('image', blob, fileName + ".png")
                            const response = await fetch('/api/saveImage', { method: 'POST', body: formData, })
                            if (response.ok) {
                                const data = await response.json();
                                console.log("Upload success", data);
                                resolve(data);
                            }
                            else { reject("Upload fail") }
                        }
                        catch (error) { reject(`Error: ${error}`) }
                    } else { reject("Blob is null") }
                }, "image/png");
            })
        }

        function render() {
            const { value: frame, done } = frameIter.next();
            if (done) { return }

            //function transpose(m : number[][]) { return m[0].map((col, c) => m.map((row, r) => row[c])) }
            cam.viewMatrix = mat4.fromValues(...<Tuple16<number>>frame.transform_matrix.flat());
            mat4.transpose(cam.viewMatrix, cam.viewMatrix);
            mat4.invert(cam.viewMatrix, cam.viewMatrix);
            // const rotateMatrix = mat4.create();
            // mat4.rotateX(rotateMatrix, rotateMatrix, frame.rotation);
            // mat4.mul(cam.viewMatrix, cam.viewMatrix, rotateMatrix);
            const reflectionMatrix = mat4.fromValues(1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
            mat4.mul(cam.viewMatrix, reflectionMatrix, cam.viewMatrix);

            const commandEncoder = device.createCommandEncoder();
            addRasterizerPass(commandEncoder);
            addFullscreenPass(context, commandEncoder);
            device.queue.submit([commandEncoder.finish()]);
            // device.queue.onSubmittedWorkDone().then(() => {
            //     exportCanvasAsPNG(canvas, frame.file_path)
            //         .then(() => render())
            //         .catch(err => console.error(err))
            // });
            exportCanvasAsPNG(canvas, frame.file_path)
                    .then(() => render())
                    .catch(err => console.error(err))
        }
        render()
    }
}

function createFullscreenPass(device: GPUDevice, presentationSize: number[], presentationFormat: GPUTextureFormat, finalColorBuffer: any) {
    const fullscreenQuadBindGroupLayout = device.createBindGroupLayout({
        entries: [
            { binding: 0, visibility: GPUShaderStage.FRAGMENT, buffer: { type: "uniform" } },
            { binding: 1, visibility: GPUShaderStage.FRAGMENT, buffer: { type: "read-only-storage" } }, // color buffer
        ]
    })

    const fullscreenQuadPipeline = device.createRenderPipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [fullscreenQuadBindGroupLayout] }),
        vertex: {
            module: device.createShaderModule({ code: fullscreenQuadWGSL }), entryPoint: "vert_main"
        },
        fragment: {
            module: device.createShaderModule({ code: fullscreenQuadWGSL }), entryPoint: "frag_main",
            targets: [{ format: presentationFormat }]
        },
        primitive: { topology: "triangle-list" }
    })

    const uniformBufferSize = 4 * 3;    // screenWidth, screenHeight, enableFXAA
    const uniformBuffer = device.createBuffer({ size: uniformBufferSize, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST })

    const fullscreenQuadBindGroup = device.createBindGroup({
        layout: fullscreenQuadBindGroupLayout,
        entries: [
            { binding: 0, resource: { buffer: uniformBuffer } },
            { binding: 1, resource: { buffer: finalColorBuffer } }
        ]
    })

    const renderPassDescriptor: GPURenderPassDescriptor | any = {
        colorAttachments: [{
            view: undefined,
            clearValue: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
            loadOp: "clear",
            storeOp: "store"
        }]
    }

    const addFullscreenPass = (context: GPUCanvasContext, commandEncoder: GPUCommandEncoder) => {
        device.queue.writeBuffer(uniformBuffer, 0, new Float32Array([presentationSize[0], presentationSize[1]]));
        device.queue.writeBuffer(uniformBuffer, 8, new Int32Array([ENABLE_FXAA, ]));

        renderPassDescriptor.colorAttachments[0].view = context.getCurrentTexture().createView();

        const cmd = commandEncoder.beginRenderPass(renderPassDescriptor)
        cmd.setPipeline(fullscreenQuadPipeline)
        cmd.setBindGroup(0, fullscreenQuadBindGroup)
        cmd.draw(6, 1, 0, 0)
        cmd.end()
    }

    return { addFullscreenPass }
}


function createRasterizerPass(device: GPUDevice, presentationSize: number[], strokeData: Float32Array, cameraCtrl?: CameraControl) {
    const [WIDTH, HEIGHT] = presentationSize
    const [TILE_COUNT_X, TILE_COUNT_Y] = [Math.ceil(WIDTH / 16), Math.ceil(HEIGHT / 16)]

    // const NUMBER_PRE_ELEMENT = 3 * 4     // triangle, 3 vertex, (3 + 1) f32 per vertex
    //const NUMBER_PRE_ELEMENT = 20           // transform 4x4 f32, color 3 f32, density 1 f32
    //const NUMBER_PRE_ELEMENT = 23           // Capsule
    //const NUMBER_PRE_ELEMENT = strokeType == 5 ? 23 : 20;
    const NUMBER_PRE_ELEMENT = 27;
    const strokeCount = strokeData.length / NUMBER_PRE_ELEMENT
    const strokeBuffer = device.createBuffer({ size: strokeData.byteLength, usage: GPUBufferUsage.STORAGE, mappedAtCreation: true, })
    new Float32Array(strokeBuffer.getMappedRange()).set(strokeData);
    strokeBuffer.unmap();

    const outputBufferSize = Float32Array.BYTES_PER_ELEMENT * (WIDTH * HEIGHT) * 4;
    const outputBuffer = device.createBuffer({ size: outputBufferSize, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC })

    const binBufferSize = Uint32Array.BYTES_PER_ELEMENT * (TILE_COUNT_X * TILE_COUNT_Y) * strokeCount;
    const binBuffer = device.createBuffer({ size: binBufferSize, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC })

    const binSizeBufferSize = Uint32Array.BYTES_PER_ELEMENT * (TILE_COUNT_X * TILE_COUNT_Y);
    const binSizeBuffer = device.createBuffer({ size: binSizeBufferSize, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC })

    const UBOBufferSize =
        4 + 4 + 4 +     // screenWidth, screenHeight, strokeCount
        4 * 16 +        // MVP
        4 * 16 +        // MV
        4               // (align)
    const UBOBuffer = device.createBuffer({ size: UBOBufferSize, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST })

    const bindGroupLayout = device.createBindGroupLayout({
        entries: [
            { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
            { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
            { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: "read-only-storage" } },
            { binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
            { binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } },
        ]
    })
    const bindGroup = device.createBindGroup({
        layout: bindGroupLayout,
        entries: [
            { binding: 0, resource: { buffer: binSizeBuffer } },
            { binding: 1, resource: { buffer: binBuffer } },
            { binding: 2, resource: { buffer: strokeBuffer } },
            { binding: 3, resource: { buffer: outputBuffer } },
            { binding: 4, resource: { buffer: UBOBuffer } },
        ]
    })

    const computeRasterizerModule = device.createShaderModule({ code: computeRasterizerWGSL })
    const clearPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
        compute: { module: computeRasterizerModule, entryPoint: "clear" }
    })
    const tilePipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
        compute: { module: computeRasterizerModule, entryPoint: "tile" }
    })
    const rasterizerPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
        compute: { module: computeRasterizerModule, entryPoint: "rasterize" }
    })

    if (cameraCtrl === undefined) {
        cameraCtrl = new CameraWander(WIDTH, HEIGHT);
    }

    const addRasterizerPass = (commandEncoder: GPUCommandEncoder) => {

        const mvp = cameraCtrl.getMVP()
        const mv = cameraCtrl.getMV()
        //console.log(mvp, [WIDTH, HEIGHT])

        device.queue.writeBuffer(UBOBuffer, 0, new Uint32Array([WIDTH, HEIGHT]).buffer)
        device.queue.writeBuffer(UBOBuffer, 8, new Uint32Array([strokeCount,]).buffer)
        device.queue.writeBuffer(UBOBuffer, 16, (mvp as Float32Array).buffer)
        device.queue.writeBuffer(UBOBuffer, 80, (mv as Float32Array).buffer)

        const cmd = commandEncoder.beginComputePass()
        // Clear pass
        cmd.setPipeline(clearPipeline)
        cmd.setBindGroup(0, bindGroup)
        cmd.dispatchWorkgroups(Math.ceil(WIDTH / 16), Math.ceil(HEIGHT / 16))
        // Tile pass
        cmd.setPipeline(tilePipeline)
        cmd.setBindGroup(0, bindGroup)
        cmd.dispatchWorkgroups(Math.ceil(strokeCount / 256), TILE_COUNT_X, TILE_COUNT_Y)
        // Rasterizer pass
        cmd.setPipeline(rasterizerPipeline)
        cmd.setBindGroup(0, bindGroup)
        cmd.dispatchWorkgroups(TILE_COUNT_X, TILE_COUNT_Y, 16 * 16 / 64)
        cmd.end()
    }

    return { addRasterizerPass, outputBuffer, cameraCtrl }
}

abstract class CameraControl {
    abstract getMVP(): mat4;
    abstract getMV(): mat4;
}

// class CameraSpin extends CameraControl {
//     modelMatrix: mat4;
//     viewMatrix: mat4;
//     projectionMatrix: mat4;

//     constructor(WIDTH: number, HEIGHT: number) {
//         super();
//         const aspect = WIDTH / HEIGHT
//         this.projectionMatrix = mat4.create()
//         mat4.perspective(this.projectionMatrix, 0.4 * Math.PI, aspect, 0.01, 100.0)
//         this.viewMatrix = mat4.create()
//         this.modelMatrix = mat4.create()
//     }

//     getMVP() {
//         const now = Date.now() / 1000
//         this.viewMatrix = mat4.create()
//         mat4.translate(this.viewMatrix, this.viewMatrix, vec3.fromValues(0, 0, -10))
//         this.modelMatrix = mat4.create()
//         mat4.rotate(this.modelMatrix, this.modelMatrix, now, vec3.fromValues(0, 1, 0))
//         mat4.rotate(this.modelMatrix, this.modelMatrix, Math.PI / 2, vec3.fromValues(1, 0, 0))
//         const modelViewProjectionMatrix = <Float32Array>mat4.create()
//         mat4.multiply(modelViewProjectionMatrix, this.viewMatrix, this.modelMatrix)
//         mat4.multiply(modelViewProjectionMatrix, this.projectionMatrix, modelViewProjectionMatrix)
//         return modelViewProjectionMatrix
//     }

//     getMV() {
//         throw new Error("Not Impl")
//     }
// }

class CameraCustom extends CameraControl {
    viewMatrix: mat4;
    modelMatrix: mat4;
    projectionMatrix: mat4;

    constructor() {
        super()
        this.modelMatrix = mat4.create()
        this.viewMatrix = mat4.create()
        this.projectionMatrix = mat4.create()
    }

    getMVP(): mat4 {
        const mvp = mat4.create()
        mat4.multiply(mvp, this.projectionMatrix, this.getMV())
        return mvp
    }
    getMV(): mat4 {
        const mv = mat4.create()
        mat4.multiply(mv, this.viewMatrix, this.modelMatrix)
        return mv
    }

}

class CameraWander extends CameraControl {
    distance: number;
    intersect: vec3;
    rotate: vec3;
    modelMatrix: mat4;
    projectionMatrix: mat4;


    constructor(WIDTH: number, HEIGHT: number) {
        super()
        const aspect = WIDTH / HEIGHT
        this.projectionMatrix = mat4.create()
        mat4.perspective(this.projectionMatrix, 0.5 * Math.PI, aspect, 0.01, 100.0)
        this.modelMatrix = mat4.create()
        mat4.rotate(this.modelMatrix, this.modelMatrix, Math.PI / 2, vec3.fromValues(1, 0, 0))
        this.distance = 5.5
        this.intersect = vec3.fromValues(0, 0, 0)
        this.rotate = vec3.fromValues(0, 0, 0)
        let mouseDownDirection = <boolean | undefined>undefined
        let _this = this
        document.onmousedown = function (event: MouseEvent) {
            if (event.buttons & (1 ^ 4)) {
                const q = quat.create()
                quat.fromEuler(q, _this.rotate[1], _this.rotate[0], _this.rotate[2])
                const m_up = vec3.create()
                vec3.transformQuat(m_up, vec3.fromValues(0, 1, 0), q)
                const up_dot_y = vec3.dot(m_up, vec3.fromValues(0, 1, 0))
                mouseDownDirection = up_dot_y > 0
            }
        }
        document.onmousemove = function (event: MouseEvent) {
            if (event.buttons & 1 && mouseDownDirection !== undefined) {
                let dx = event.movementX
                let dy = event.movementY
                let ay = -0.2
                let ax = mouseDownDirection ? -0.2 : 0.2
                vec3.add(_this.rotate, _this.rotate, vec3.fromValues(dx * ax, dy * ay, 0))
            }
            if (event.buttons & 4) {
                let dx = event.movementX
                let dy = event.movementY
                let ay = -0.05
                let ax = _this.distance > 0 ? -0.05 : 0.05
                const q = quat.create()
                quat.fromEuler(q, _this.rotate[1], _this.rotate[0], _this.rotate[2])
                let dir_z = vec3.create()
                vec3.transformQuat(dir_z, vec3.fromValues(0, 0, -_this.distance), q)
                let dir_y = vec3.create()
                vec3.transformQuat(dir_y, vec3.fromValues(0, 1, 0), q)
                let dir_x = vec3.create()
                vec3.cross(dir_x, dir_y, dir_z)
                vec3.normalize(dir_x, dir_x)
                vec3.normalize(dir_y, dir_y)
                vec3.scaleAndAdd(_this.intersect, _this.intersect, dir_x, dx * ax)
                vec3.scaleAndAdd(_this.intersect, _this.intersect, dir_y, dy * ay)
            }
        }
        document.onmouseup = function (event: MouseEvent) {
            mouseDownDirection = undefined
        }
        document.onwheel = function (event: WheelEvent) {
            _this.distance += event.deltaY * 0.002
        }

    }

    getMVP(): mat4 {
        const mvp = <Float32Array>mat4.create()
        mat4.multiply(mvp, this.projectionMatrix, this.getMV())
        return mvp
    }

    getMV(): mat4 {
        const q = quat.create()
        quat.fromEuler(q, this.rotate[1], this.rotate[0], this.rotate[2])

        const m_eye = vec3.create()
        vec3.transformQuat(m_eye, vec3.fromValues(0, 0, -this.distance), q)
        vec3.add(m_eye, m_eye, this.intersect)
        const m_center = vec3.create()
        vec3.transformQuat(m_center, vec3.fromValues(0, 0, 1), q)
        vec3.add(m_center, m_center, m_eye)
        const m_up = vec3.create()
        vec3.transformQuat(m_up, vec3.fromValues(0, 1, 0), q)

        const viewMatrix = mat4.create()
        mat4.lookAt(viewMatrix, m_eye, m_center, m_up)

        const modelViewMatrix = <Float32Array>mat4.create()
        mat4.multiply(modelViewMatrix, viewMatrix, this.modelMatrix)
        return modelViewMatrix
    }
}