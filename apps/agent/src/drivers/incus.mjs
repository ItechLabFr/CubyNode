import fs from 'node:fs';
import { parseJsonResponse, unixRequest } from '../unix-http.mjs';

export class IncusDriver {
  constructor(socketPath = '/var/lib/incus/unix.socket') {
    this.socketPath = socketPath;
  }

  async available() {
    if (!fs.existsSync(this.socketPath)) return false;
    try {
      const response = await unixRequest({ socketPath: this.socketPath, path: '/1.0', timeoutMs: 2_000 });
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch {
      return false;
    }
  }

  async request(method, path, body = null) {
    const response = await unixRequest({ socketPath: this.socketPath, method, path, body });
    const envelope = parseJsonResponse(response, `Incus ${method} ${path}`);
    if (envelope?.type === 'error') {
      const error = new Error(envelope.error || 'Incus request failed');
      error.statusCode = envelope.error_code || 500;
      throw error;
    }
    return envelope?.metadata;
  }

  async listWorkloads() {
    if (!(await this.available())) return [];
    const instances = await this.request('GET', '/1.0/instances?recursion=2');
    const managed = (instances ?? []).filter((instance) => instance.config?.['user.cubynode.managed'] === 'true');

    return Promise.all(managed.map(async (instance) => {
      let state = null;
      try {
        state = await this.request('GET', `/1.0/instances/${encodeURIComponent(instance.name)}/state`);
      } catch {
        state = null;
      }

      return {
        id: instance.name,
        externalId: instance.name,
        runtime: 'incus',
        kind: instance.config?.['user.cubynode.kind'] || 'unknown',
        name: instance.config?.['user.cubynode.name'] || instance.name,
        status: normalizeIncusStatus(instance.status),
        statusDetail: instance.status ?? null,
        image: instance.config?.['image.description'] || instance.config?.['volatile.base_image'] || null,
        demo: instance.config?.['user.cubynode.demo'] === 'true',
        template: instance.config?.['user.cubynode.template'] || null,
        createdAt: instance.created_at || null,
        cpuPercent: null,
        memoryUsedBytes: state?.memory?.usage ?? 0,
        memoryLimitBytes: state?.memory?.usage_peak ?? 0,
        ports: [],
      };
    }));
  }

  async action(id, action) {
    if (!['start', 'stop', 'restart'].includes(action)) {
      const error = new Error(`Unsupported Incus action: ${action}`);
      error.statusCode = 400;
      throw error;
    }

    await this.request('PUT', `/1.0/instances/${encodeURIComponent(id)}/state`, {
      action,
      timeout: 30,
      force: false,
      stateful: false,
    });
    return { accepted: true };
  }

  async logs() {
    const error = new Error('Application log streaming for Incus workloads is not implemented in beta.1. Use exec/journal integration on the managed LXC instance.');
    error.statusCode = 501;
    throw error;
  }
}

export function normalizeIncusStatus(status) {
  const value = String(status || '').toLowerCase();
  if (value === 'running') return 'running';
  if (value === 'stopped' || value === 'frozen') return value === 'frozen' ? 'paused' : 'stopped';
  if (value === 'starting') return 'starting';
  if (value === 'stopping') return 'stopping';
  return value || 'unknown';
}
