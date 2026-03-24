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

  // GET /seed?docId=xxx — generate test annotations for all 17 pages
  if (req.method === 'GET' && url.pathname === '/seed') {
    const PAGE_COUNT = 17;
    const annotations = [];

    for (let page = 0; page < PAGE_COUNT; page++) {
      const offset = page / PAGE_COUNT; // vary positions per page

      const strokes = [
        // Drawing stroke 1: diagonal line
        {
          color: '#ff0000',
          width: 2,
          opacity: 1,
          path: Array.from({ length: 20 }, (_, i) => [
            0.1 + (i / 19) * 0.3,
            (0.1 + offset * 0.05) + (i / 19) * 0.2,
          ]),
        },
        // Drawing stroke 2: zigzag
        {
          color: '#0000ff',
          width: 3,
          opacity: 1,
          path: Array.from({ length: 30 }, (_, i) => [
            0.5 + (i / 29) * 0.4,
            0.3 + Math.sin(i * 0.8) * 0.05 + offset * 0.02,
          ]),
        },
        // Drawing stroke 3: curve
        {
          color: '#00aa00',
          width: 2,
          opacity: 1,
          path: Array.from({ length: 25 }, (_, i) => [
            0.05 + (i / 24) * 0.9,
            0.7 + Math.sin(i * 0.3) * 0.08,
          ]),
        },
        // Highlight stroke 1
        {
          color: '#FFC107',
          width: 12,
          opacity: 0.3,
          path: [[0.05, 0.15 + offset * 0.03], [0.7, 0.15 + offset * 0.03]],
        },
        // Highlight stroke 2
        {
          color: '#FFC107',
          width: 15,
          opacity: 0.3,
          path: [[0.05, 0.45], [0.85, 0.45]],
        },
        // Single-point stroke (dot)
        {
          color: '#9C27B0',
          width: 5,
          opacity: 1,
          path: [[0.8, 0.1 + offset * 0.04]],
        },
      ];

      const text = [
        {
          color: '#000000',
          fontSize: 14,
          point: [0.05, 0.05 + offset * 0.02],
          str: `Page ${page + 1} annotation`,
        },
        {
          color: '#ff0000',
          fontSize: 18,
          point: [0.4, 0.55],
          str: 'Test note',
        },
        {
          color: '#0000ff',
          fontSize: 12,
          point: [0.6, 0.85],
          str: `Comment #${page + 1}`,
        },
      ];

      annotations.push({ strokes, text });
    }

    store[docId] = annotations;

    const strokeCount = annotations.reduce((s, p) => s + p.strokes.length, 0);
    const textCount = annotations.reduce((s, p) => s + p.text.length, 0);
    console.log(`[SEED] docId=${docId} -> ${PAGE_COUNT} pages, ${strokeCount} strokes, ${textCount} texts`);

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, pages: PAGE_COUNT, strokes: strokeCount, texts: textCount }));
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
