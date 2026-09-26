const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const { handler, siteConfig, configScript } = require('../server');

function get(server, path) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: server.address().port, path }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body }));
    }).on('error', reject);
  });
}

test('serves pages, health, config and 404s', async (t) => {
  const server = http.createServer(handler).listen(0);
  t.after(() => server.close());
  await new Promise((r) => server.once('listening', r));

  const home = await get(server, '/');
  assert.strictEqual(home.status, 200);
  assert.match(home.body, /Goofer Flywheel/);
  assert.ok(home.headers['content-security-policy']);

  assert.strictEqual((await get(server, '/health')).body, 'ok');
  assert.match((await get(server, '/config.js')).body, /^window\.GOOFER_CONFIG = /);
  assert.strictEqual((await get(server, '/nope')).status, 404);
  assert.strictEqual((await get(server, '/..%2fserver.js')).status, 404);
  assert.notStrictEqual((await get(server, '/%2e%2e/server.js')).status, 200);
});

test('config only passes safe values through', () => {
  const cfg = siteConfig({
    CONTRACT_ADDRESS: 'not-an-address',
    X_HANDLE: '@goofer<script>',
    TELEGRAM_URL: 'javascript:alert(1)',
    BUY_URL: 'https://example.com/buy',
  });
  assert.strictEqual(cfg.contractAddress, '');
  assert.strictEqual(cfg.xHandle, 'gooferscript');
  assert.strictEqual(cfg.telegramUrl, '');
  assert.strictEqual(cfg.buyUrl, 'https://example.com/buy');
  assert.doesNotMatch(configScript({ chainName: '</script>' }), /<\/script>/);
});
