'use strict';

// Локальный сервер для разработки: отдаёт public/ и запускает функции из api/ как на Vercel.
// Запуск: node server.js  (порт по умолчанию 3000, PORT=... чтобы поменять)

const http = require('http');
const fs = require('fs');
const path = require('path');

for (const name of ['.env.local', '.env']) {
  const file = path.join(__dirname, name);
  if (!fs.existsSync(file)) continue;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !line.trim().startsWith('#') && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  }
}

const PUBLIC = path.join(__dirname, 'public');
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
};

function createServer() {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://local');
    const pathname = decodeURIComponent(url.pathname);

    if (pathname.startsWith('/api/')) {
      const name = pathname.slice(5).replace(/[^\w-]/g, '');
      const file = path.join(__dirname, 'api', `${name}.js`);
      if (!name || name.startsWith('_') || !fs.existsSync(file)) {
        res.statusCode = 404;
        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({ error: 'Нет такого эндпоинта' }));
      }
      delete require.cache[require.resolve(file)];
      return require(file)(req, res);
    }

    let rel = pathname === '/' ? '/index.html' : pathname;
    const full = path.normalize(path.join(PUBLIC, rel));
    if (!full.startsWith(PUBLIC)) {
      res.statusCode = 403;
      return res.end('forbidden');
    }
    fs.readFile(full, (err, data) => {
      if (err) {
        res.statusCode = 404;
        return res.end('not found');
      }
      res.setHeader('Content-Type', TYPES[path.extname(full)] || 'application/octet-stream');
      res.setHeader('Cache-Control', 'no-store');
      res.end(data);
    });
  });
}

module.exports = { createServer };

if (require.main === module) {
  const port = Number(process.env.PORT) || 3000;
  createServer().listen(port, () => console.log(`Пульт: http://localhost:${port}`));
}
