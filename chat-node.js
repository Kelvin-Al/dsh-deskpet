// 由 pet-chat.ps1 调用：node chat-node.js <req.json> <out.json>
// .NET 的 schannel 在受限环境里可能拿不到 TLS 凭据，这里用 Node 自带的 OpenSSL 发请求。
const fs = require('fs');
const https = require('https');
const http = require('http');

function done(obj) {
  try { fs.writeFileSync(process.argv[3], JSON.stringify(obj)); } catch (_) { }
}

try {
  const req = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const url = new URL(req.url);
  const lib = url.protocol === 'http:' ? http : https;
  const body = Buffer.from(req.body, 'utf8');
  const r = lib.request(url, {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ' + req.key,
      'Content-Type': 'application/json',
      'Content-Length': body.length
    }
  }, res => {
    const chunks = [];
    res.on('data', c => chunks.push(c));
    res.on('end', () => done({ status: res.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
  });
  r.on('error', e => done({ status: 0, error: String((e && e.message) || e) }));
  r.setTimeout(120000, () => { r.destroy(); done({ status: 0, error: 'timeout' }); });
  r.write(body);
  r.end();
} catch (e) {
  done({ status: 0, error: String((e && e.message) || e) });
}
