import path from 'path';
import fs from 'fs';
import express from 'express';
import multer from 'multer';
import ViteExpress from 'vite-express';
import colors from 'colors-console';

const RENDER_OUTPUT = './test/outputs'

const app = express();

// 设置 multer 存储配置
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const dir = RENDER_OUTPUT;
        if (!fs.existsSync(dir)) { fs.mkdirSync(dir); }
        cb(null, dir);
    },
    filename: (req, file, cb) => {
        cb(null, file.originalname);
    }
});

const upload = multer({ storage: storage });

// 定义 POST 路由来接收图片
app.post('/api/saveImage', upload.single('image'), (req, res) => {
    if (req.file) {
        res.status(200).json({ message: 'File uploaded successfully', file: req.file })
    }
    else {
        return res.status(400).json({ message: 'File upload failed' });
    }
});


const PORT = 5173
ViteExpress.listen(app, PORT, () => console.log('Server is running on ' + colors('cyan', `http://localhost:${PORT}`) + '...'));