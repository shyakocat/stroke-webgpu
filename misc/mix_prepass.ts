import * as fs from 'fs';

const input_path = "models/lego_mix_ellipsoid_obb_line/strokes.json"
const output_path = "models/lego_mix_ellipsoid_obb_line/strokes.proc.json"


type STROKE_PARAM = { shape_params: number[], color_params: number[], density_params: number, stroke_type: string };
let o = JSON.parse(fs.readFileSync(input_path, 'utf-8'))
o.shape_type = "mix"
for (const [k, v] of Object.entries(o.stroke_params)) {
    let d = v as STROKE_PARAM;
    const [w1, w2, w3] = d.shape_params.slice(0, 3);    // ellipsoid, box, capsule
    const [h, r_diff] = d.shape_params.slice(3, 5);
    const ps = d.shape_params.slice(5);
    if (w1 >= w2 && w1 >= w3) {
        d.stroke_type = "ellipsoid";
        d.shape_params = ps;
    }
    else if (w2 >= w1 && w2 >= w3) {
        d.stroke_type = "cube_a";
        d.shape_params = ps;
    }
    else if (w3 >= w1 && w3 >= w2) {
        d.stroke_type = "line_a";
        d.shape_params = [h, r_diff, ...ps];
    }
}
fs.writeFileSync(output_path, JSON.stringify(o))