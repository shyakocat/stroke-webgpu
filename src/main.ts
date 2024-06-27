import { mat4, vec3, quat, mat3 } from 'gl-matrix'
//@ts-ignore
import fullscreenQuadWGSL from '../shaders/fullscreenQuad.wgsl?raw';
//@ts-ignore
import computeRasterizerWGSL from '../shaders/computeRasterizer.wgsl?raw';
import { loadModel } from './loadModel.ts';
import Stats from 'stats.js';

init();

async function init() {
    const adapter = await navigator.gpu.requestAdapter() as GPUAdapter;
    const device = await adapter.requestDevice();
    const canvas = document.querySelector("canvas") as HTMLCanvasElement;
    const context = canvas.getContext("webgpu") as GPUCanvasContext;
    canvas.width = window.innerWidth * 0.9;
    canvas.height = window.innerHeight * 0.9;

    const devicePixelRatio = window.devicePixelRatio || 1;
    const presentationSize = [
        Math.floor(canvas.clientWidth * devicePixelRatio),
        Math.floor(canvas.clientHeight * devicePixelRatio),
    ];

    const presentationFormat = navigator.gpu.getPreferredCanvasFormat();
    context.configure({
        device,
        format: presentationFormat,
        alphaMode: "opaque"
    });

    const strokeData: Float32Array = await loadModel();

    const { addRasterizerPass, outputColorBuffer } = createRasterizerPass(device, presentationSize, strokeData);
    const { addFullscreenPass } = createFullscreenPass(device, presentationSize, presentationFormat, outputColorBuffer);

    var stats = new Stats();
    stats.showPanel(0); // 0: fps, 1: ms, 2: mb, 3+: custom
    document.body.appendChild(stats.dom);

    function draw() {

        stats.begin()

        const commandEncoder = device.createCommandEncoder();

        addRasterizerPass(commandEncoder);
        addFullscreenPass(context, commandEncoder);

        device.queue.submit([commandEncoder.finish()]);

        stats.end()

        requestAnimationFrame(draw);
    }

    draw();
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

    const uniformBufferSize = 4 * 2;    // screenWidth, screenHeight
    const uniformBuffer = device.createBuffer({
        size: uniformBufferSize,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    })

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

        renderPassDescriptor.colorAttachments[0].view = context.getCurrentTexture().createView();

        const cmd = commandEncoder.beginRenderPass(renderPassDescriptor)
        cmd.setPipeline(fullscreenQuadPipeline)
        cmd.setBindGroup(0, fullscreenQuadBindGroup)
        cmd.draw(6, 1, 0, 0)
        cmd.end()
    }

    return { addFullscreenPass }
}


function createRasterizerPass(device: GPUDevice, presentationSize: number[], strokeData: Float32Array) {
    const [WIDTH, HEIGHT] = presentationSize
    const COLOR_CHANNELS = 3

    const NUMBER_PRE_ELEMENT = 3 * 4    // triangle, 3 vertex, (3 + 1) f32 per vertex
    const strokeCount = strokeData.length / NUMBER_PRE_ELEMENT
    const strokeBuffer = device.createBuffer({
        size: strokeData.byteLength,
        usage: GPUBufferUsage.STORAGE,
        mappedAtCreation: true,
    })
    new Float32Array(strokeBuffer.getMappedRange()).set(strokeData);
    strokeBuffer.unmap();

    const outputColorBufferSize = Uint32Array.BYTES_PER_ELEMENT * (WIDTH * HEIGHT) * COLOR_CHANNELS;
    const outputColorBuffer = device.createBuffer({ size: outputColorBufferSize, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC })

    const UBOBufferSize =
        (4 + 12) * 2 +  // screenWidth, screenHeight
        4 * 16 +        // MVP
        (4 + 12)        // strokeType
    const UBOBuffer = device.createBuffer({ size: UBOBufferSize, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST })

    const bindGroupLayout = device.createBindGroupLayout({
        entries: [
            { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
            { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: "read-only-storage" } },
            { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } },
        ]
    })
    const bindGroup = device.createBindGroup({
        layout: bindGroupLayout,
        entries: [
            { binding: 0, resource: { buffer: outputColorBuffer } },
            { binding: 1, resource: { buffer: strokeBuffer } },
            { binding: 2, resource: { buffer: UBOBuffer } }
        ]
    })

    const computeRasterizerModule = device.createShaderModule({ code: computeRasterizerWGSL })
    const rasterizerPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
        compute: { module: computeRasterizerModule, entryPoint: "main" }
    })
    const clearPipeline = device.createComputePipeline({
        layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
        compute: { module: computeRasterizerModule, entryPoint: "clear" }
    })

    const cameraCtrl: CameraControl = new CameraWander(WIDTH, HEIGHT)

    const addRasterizerPass = (commandEncoder: GPUCommandEncoder) => {

        const mvp = cameraCtrl.getMVP()

        const uniformData = [WIDTH, HEIGHT]
        const uniformTypeArray = new Float32Array(uniformData)
        device.queue.writeBuffer(UBOBuffer, 0, uniformTypeArray.buffer)
        device.queue.writeBuffer(UBOBuffer, 16, (mvp as Float32Array).buffer)

        const cmd = commandEncoder.beginComputePass()
        let totalTimesToRun = Math.ceil((WIDTH * HEIGHT) / 256)
        // Clear pass
        cmd.setPipeline(clearPipeline)
        cmd.setBindGroup(0, bindGroup)
        cmd.dispatchWorkgroups(totalTimesToRun)
        // Rasterizer pass
        totalTimesToRun = Math.ceil((strokeCount) / 256)
        cmd.setPipeline(rasterizerPipeline)
        cmd.setBindGroup(0, bindGroup)
        cmd.dispatchWorkgroups(totalTimesToRun)
        cmd.end()
    }

    return { addRasterizerPass, outputColorBuffer }
}

abstract class CameraControl {
    abstract getMVP(): mat4;
}

class CameraSpin extends CameraControl {
    modelMatrix: mat4;
    viewMatrix: mat4;
    projectionMatrix: mat4;

    constructor(WIDTH: number, HEIGHT: number) {
        super();
        const aspect = WIDTH / HEIGHT
        this.projectionMatrix = mat4.create()
        mat4.perspective(this.projectionMatrix, 0.4 * Math.PI, aspect, 1, 100.0)
        this.viewMatrix = mat4.create()
        this.modelMatrix = mat4.create()
    }

    getMVP() {
        const now = Date.now() / 1000
        this.viewMatrix = mat4.create()
        mat4.translate(this.viewMatrix, this.viewMatrix, vec3.fromValues(0, 0, -10))
        this.modelMatrix = mat4.create()
        mat4.rotate(this.modelMatrix, this.modelMatrix, now, vec3.fromValues(0, 1, 0))
        mat4.rotate(this.modelMatrix, this.modelMatrix, Math.PI / 2, vec3.fromValues(1, 0, 0))
        const modelViewProjectionMatrix = <Float32Array>mat4.create()
        mat4.multiply(modelViewProjectionMatrix, this.viewMatrix, this.modelMatrix)
        mat4.multiply(modelViewProjectionMatrix, this.projectionMatrix, modelViewProjectionMatrix)
        return modelViewProjectionMatrix
    }
}

class CameraWander extends CameraControl {
    distance: number;
    intersect: vec3;
    rotate: vec3;
    projectionMatrix: mat4;


    constructor(WIDTH: number, HEIGHT: number) {
        super()
        const aspect = WIDTH / HEIGHT
        this.projectionMatrix = mat4.create()
        mat4.perspective(this.projectionMatrix, 0.4 * Math.PI, aspect, 1, 100.0)
        this.distance = 10
        this.intersect = vec3.fromValues(0, 0, 0)
        this.rotate = vec3.fromValues(0, 0, 0)
        let mouseDownDirection = <boolean | undefined> undefined
        let _this = this
        document.onmousedown = function (event : MouseEvent) {
            const q = quat.create()
            quat.fromEuler(q, _this.rotate[1], _this.rotate[0], _this.rotate[2])
            const m_up = vec3.create()
            vec3.transformQuat(m_up, vec3.fromValues(0, 1, 0), q)
            const up_dot_y = vec3.dot(m_up, vec3.fromValues(0, 1, 0))
            mouseDownDirection = up_dot_y > 0
        }
        document.onmousemove = function (event: MouseEvent) {
            if (event.buttons & 1 && mouseDownDirection !== undefined) {
                let dx = event.movementX
                let dy = event.movementY
                let ay = -0.2
                let ax = mouseDownDirection ? -0.2 : 0.2
                vec3.add(_this.rotate, _this.rotate, vec3.fromValues(dx * ax, dy * ay, 0))
            }
        }
        document.onmouseup = function (event : MouseEvent) {
            mouseDownDirection = undefined
        }
        document.onwheel = function (event: WheelEvent) {
            _this.distance += event.deltaY * 0.01
        }

    }

    getMVP(): mat4 {
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
        // world = mat4 Identity
        const mvp = <Float32Array>mat4.create()
        mat4.multiply(mvp, this.projectionMatrix, viewMatrix)
        return mvp
    }
}