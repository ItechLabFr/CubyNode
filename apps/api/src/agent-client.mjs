export class AgentClient {
  constructor(baseUrl, token) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.token = token;
  }

  async request(path, options = {}) {
    const response = await fetch(`${this.baseUrl}${path}`, {
      ...options,
      headers: {
        Authorization: `Bearer ${this.token}`,
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
      signal: AbortSignal.timeout(options.timeoutMs || 10_000),
    });

    const contentType = response.headers.get('content-type') || '';
    const body = contentType.includes('application/json') ? await response.json() : await response.text();
    if (!response.ok) {
      const error = new Error(body?.error || body?.message || String(body) || `Agent HTTP ${response.status}`);
      error.statusCode = response.status;
      throw error;
    }
    return body;
  }

  node() {
    return this.request('/v1/node');
  }

  workloads() {
    return this.request('/v1/workloads');
  }

  action(runtime, externalId, action) {
    return this.request(`/v1/workloads/${encodeURIComponent(runtime)}/${encodeURIComponent(externalId)}/${action}`, { method: 'POST' });
  }

  logs(runtime, externalId, tail = 200) {
    return this.request(`/v1/workloads/${encodeURIComponent(runtime)}/${encodeURIComponent(externalId)}/logs?tail=${Math.max(1, Math.min(2000, Number(tail) || 200))}`);
  }
}
