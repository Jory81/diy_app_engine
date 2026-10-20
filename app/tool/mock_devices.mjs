// Mock ESP devices for browser previews and screenshots (not used by the app).
//
//   node tool/mock_devices.mjs [webDir]
//
// * http://localhost:8081/info  -> multi-mode controller (bbq|greenhouse) in
//                                 soft-AP mode; POST /mode set=<mode> restarts it
//                                 (offline for 6 s) into the new mode
// * http://localhost:8082/info  -> Greenhouse on the home Wi-Fi
// * http://localhost:8080/      -> serves [webDir] (a `flutter build web` output)
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const devices = {
  8081: { type: 'bbq', name: 'BBQ controller', id: 'a1b2c3', version: '2.0', mode: 'ap', ip: '192.168.4.1',
    modes: ['bbq', 'greenhouse'] },
  8082: { type: 'greenhouse', name: 'Greenhouse', id: 'd4e5f6', version: '2.0', mode: 'sta', ip: '192.168.1.23' },
};

for (const [port, info] of Object.entries(devices)) {
  let restartingUntil = 0;
  const names = { bbq: 'BBQ controller', greenhouse: 'Greenhouse' };
  createServer((req, res) => {
    const headers = { 'Access-Control-Allow-Origin': '*' };
    if (Date.now() < restartingUntil) return req.socket.destroy(); // rebooting
    const json = (body) => {
      res.writeHead(200, { ...headers, 'Content-Type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (req.url === '/mode' && info.modes) {
      if (req.method === 'OPTIONS') {
        res.writeHead(204, { ...headers, 'Access-Control-Allow-Headers': '*' });
        return res.end();
      }
      if (req.method !== 'POST') return json({ mode: info.type, modes: info.modes, restarting: false });
      let body = '';
      req.on('data', (c) => (body += c));
      req.on('end', () => {
        const mode = new URLSearchParams(body).get('set');
        if (!info.modes.includes(mode)) {
          res.writeHead(400, headers);
          return res.end('unknown mode');
        }
        json({ mode, modes: info.modes, restarting: true });
        Object.assign(info, { type: mode, name: names[mode] ?? mode });
        restartingUntil = Date.now() + 6000;
      });
      return;
    }
    if (req.url === '/info') {
      res.writeHead(200, { ...headers, 'Content-Type': 'application/json' });
      res.end(JSON.stringify(info));
    } else {
      res.writeHead(200, { ...headers, 'Content-Type': 'text/html' });
      res.end(`<h1>${info.name}</h1><p>Mock device UI</p>`);
    }
  }).listen(Number(port), () => console.log(`mock ${info.type} on :${port}`));
}

const webDir = process.argv[2];
if (webDir) {
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png',
    '.otf': 'font/otf', '.ttf': 'font/ttf', '.css': 'text/css', '.ico': 'image/x-icon' };
  createServer(async (req, res) => {
    const path = normalize(decodeURIComponent(req.url.split('?')[0])).replace(/^(\.\.[/\\])+/, '');
    const file = join(webDir, path.endsWith('/') ? `${path}index.html` : path);
    try {
      const body = await readFile(file);
      res.writeHead(200, { 'Content-Type': types[extname(file)] ?? 'application/octet-stream' });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end('not found');
    }
  }).listen(8080, () => console.log(`web app on :8080 from ${webDir}`));
}
