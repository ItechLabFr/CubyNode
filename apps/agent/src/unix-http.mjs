import http from 'node:http';

export function unixRequest({ socketPath, method = 'GET', path, body = null, headers = {}, timeoutMs = 15_000 }) {
  return new Promise((resolve, reject) => {
    const payload = body == null ? null : Buffer.from(JSON.stringify(body));
    const request = http.request({
      socketPath,
      path,
      method,
      headers: {
        Host: 'localhost',
        ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': payload.length } : {}),
        ...headers,
      },
      timeout: timeoutMs,
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => {
        const buffer = Buffer.concat(chunks);
        resolve({ statusCode: response.statusCode ?? 0, headers: response.headers, buffer });
      });
    });

    request.on('timeout', () => request.destroy(new Error(`Unix socket request timed out: ${method} ${path}`)));
    request.on('error', reject);
    if (payload) request.write(payload);
    request.end();
  });
}

export function parseJsonResponse(response, context = 'request') {
  const text = response.buffer.toString('utf8');
  let parsed = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch (error) {
      throw new Error(`${context} returned invalid JSON (${response.statusCode}): ${error.message}`);
    }
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    const message = parsed?.message || parsed?.error || text || `HTTP ${response.statusCode}`;
    const error = new Error(`${context} failed: ${message}`);
    error.statusCode = response.statusCode;
    throw error;
  }
  return parsed;
}
