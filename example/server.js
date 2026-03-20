const http = require('http');

const PORT = 3001;

// In-memory storage: { [documentId]: AnnotationPage[] }
const store = {};

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => (data += chunk));
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://localhost:${PORT}`);
  const docId = url.searchParams.get('docId') || 'default';

  // GET /annotations?docId=xxx — load annotations
  if (req.method === 'GET' && url.pathname === '/annotations') {
    const annotations = store[docId] || null;
    console.log(`[GET] docId=${docId} -> ${annotations ? annotations.length + ' pages' : 'none'}`);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ annotations }));
    return;
  }

  // POST /annotations?docId=xxx — save annotations
  if (req.method === 'POST' && url.pathname === '/annotations') {
    const body = await parseBody(req);
    store[docId] = body.annotations;
    const pageCount = body.annotations ? body.annotations.length : 0;
    const strokeCount = (body.annotations || []).reduce(
      (sum, p) => sum + (p.strokes ? p.strokes.length : 0), 0
    );
    const textCount = (body.annotations || []).reduce(
      (sum, p) => sum + (p.text ? p.text.length : 0), 0
    );
    console.log(`[POST] docId=${docId} -> ${pageCount} pages, ${strokeCount} strokes, ${textCount} texts`);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, pageCount, strokeCount, textCount }));
    return;
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Annotation server running on http://0.0.0.0:${PORT}`);
  console.log('Endpoints:');
  console.log('  GET  /annotations?docId=xxx');
  console.log('  POST /annotations?docId=xxx  body: { annotations: AnnotationPage[] }');
});
