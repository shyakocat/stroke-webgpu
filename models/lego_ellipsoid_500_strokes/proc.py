import json
import numpy as np
from scipy.spatial.transform import Rotation as R

with open('stroke.json', 'r') as fin:
    scene = json.load(fin)

xml = '''<?xml version="1.0" encoding="utf-8"?>

<scene version="0.5.0">
    <integrator type="path" />

    <sensor type="perspective">
        <string name="fovAxis" value="smaller" />
        <float name="nearClip" value="0.01" />
        <float name="farClip" value="100" />
        <float name="focusDistance" value="1000" />
        <transform name="toWorld">
            <lookAt origin="0, 0, -10" target="0, 0, 0" up="0, 1, 0" />
        </transform>
        <float name="fov" value="39.3077" />

        <sampler type="ldsampler">
            <integer name="sampleCount" value="64" />
        </sampler>

        <film type="hdrfilm">
            <integer name="width" value="1024" />
            <integer name="height" value="1024" />

            <rfilter type="gaussian" />
        </film>
    </sensor>
'''

for i, data in scene["stroke_params"].items():
    p = data["shape_params"]
    c = data["color_params"]
    d = data["density_params"]
    Ms = np.diag(p[:3] + [1])
    Mr = np.eye(4)
    Mr[:3, :3] = R.from_euler('zyx', p[3:6]).as_matrix()
    Mt = np.eye(4)
    Mt[:3, 3] = p[6:]
    Msrt = Mt @ Mr @ Ms
    # custom_rot = np.eye(4)
    # custom_rot[:3, :3] = R.from_euler('xyz', [0, 90, 90], degrees=True).as_matrix()
    # Msrt = custom_rot @ Msrt
    xml += '''
    <shape type="sphere">
        <transform name="toWorld">
            <matrix value="{}"/>
        </transform>
        <bsdf type="diffuse">
            <srgb name="reflectance" value="{}, {}, {}"/>
        </bsdf>
    </shape>
'''.format(','.join(map(str, Msrt.reshape(16))), c[0], c[1], c[2])

xml += '''
</scene>
'''

with open('scene.xml', 'w') as fout:
    fout.write(xml)