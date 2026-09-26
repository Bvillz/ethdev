// Tiny static server for the Goofer site. No dependencies, so Railway can run it with `npm start`.
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT) || 3000;
const PUBLIC_DIR = path.join(__dirname, 'public');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
};

const SECURITY_HEADERS = {
  'Content-Security-Policy': [
    "default-src 'self'",
    "style-src 'self' https://fonts.googleapis.com",
    "font-src https://fonts.gstatic.com",
    "img-src 'self' data:",
    "script-src 'self'",
    "connect-src 'self'",
    "frame-ancestors 'none'",
    "base-uri 'self'",
  ].join('; '),
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
};

// Site settings come from environment variables so they can be changed in Railway without code edits.
function siteConfig(env = process.env) {
  const safeUrl = (value) => (/^https:\/\/\S+$/i.test(value || '') ? value : '');
  return {
    contractAddress: /^0x[0-9a-fA-F]{40}$/.test(env.CONTRACT_ADDRESS || '') ? env.CONTRACT_ADDRESS : '',
    chainName: env.CHAIN_NAME || '',
    totalSupply: env.TOTAL_SUPPLY || '',
    launchDate: env.LAUNCH_DATE || '',
    feePercent: env.FEE_PERCENT || '',
    spinSchedule: env.SPIN_SCHEDULE || '',
    minHoldDays: env.MIN_HOLD_DAYS || '',
    xHandle: (env.X_HANDLE || '').replace(/^@/, '').replace(/[^A-Za-z0-9_]/g, ''),
    telegramUrl: safeUrl(env.TELEGRAM_URL),
    buyUrl: safeUrl(env.BUY_URL),
  };
}

function configScript(config) {
  // Escape "<" so no value can close the script tag.
  return `window.GOOFER_CONFIG = ${JSON.stringify(config).replace(/</g, '\\u003c')};\n`;
}

function send(res, status, body, type, extra = {}) {
  res.writeHead(status, { 'Content-Type': type, ...SECURITY_HEADERS, ...extra });
  res.end(body);
}

function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, 'Method not allowed', TYPES['.txt'], { Allow: 'GET, HEAD' });
  }

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    return send(res, 400, 'Bad request', TYPES['.txt']);
  }

  if (pathname === '/health') return send(res, 200, 'ok', TYPES['.txt']);
  if (pathname === '/config.js') {
    return send(res, 200, configScript(siteConfig()), TYPES['.js'], { 'Cache-Control': 'no-store' });
  }

  const filePath = path.join(PUBLIC_DIR, path.normalize(pathname === '/' ? '/index.html' : pathname));
  if (!filePath.startsWith(PUBLIC_DIR + path.sep)) return send(res, 403, 'Forbidden', TYPES['.txt']);

  fs.readFile(filePath, (err, data) => {
    if (err) {
      return fs.readFile(path.join(PUBLIC_DIR, '404.html'), (err404, page) =>
        send(res, 404, err404 ? 'Not found' : page, TYPES['.html']));
    }
    const type = TYPES[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
    send(res, 200, req.method === 'HEAD' ? '' : data, type, { 'Cache-Control': 'public, max-age=300' });
  });
}

if (require.main === module) {
  http.createServer(handler).listen(PORT, () => console.log(`Goofer is running on port ${PORT}`));
}

module.exports = { handler, siteConfig, configScript };
