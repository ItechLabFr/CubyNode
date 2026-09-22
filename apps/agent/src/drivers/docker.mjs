import fs from 'node:fs';
import { parseJsonResponse, unixRequest } from '../unix-http.mjs';

export class DockerDriver {
  constructor(socketPath = '/var/run/docker.sock') {
    this.socketPath = socketPath;
    this.apiPrefix = null;
  }

  async available() {
    if (!fs.existsSync(this.socketPath)) return false;
    try {
      const response = await unixRequest({ socketPath: this.socketPath, path: '/_ping', timeoutMs: 2_000 });
      return response.statusCode === 200 && response.buffer.toString('utf8').trim() === 'OK';
    } catch {
      return false;
    }
  }

  async prefix() {
    if (this.apiPrefix) return this.apiPrefix;
    const response = await unixRequest({ socketPath: this.socketPath, path: '/version', timeoutMs: 3_000 });
    const version = parseJsonResponse(response, 'Docker version');
    this.apiPrefix = `/v${version.ApiVersion}`;
    return this.apiPrefix;
  }

  async request(method, path, body = null, { raw = false, timeoutMs = 15_000 } = {}) {
    const prefix = await this.prefix();
    const response = await unixRequest({
      socketPath: this.socketPath,
      method,
      path: `${prefix}${path}`,
      body,
      timeoutMs,
    });

    if (raw) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        const text = response.buffer.toString('utf8');
        const error = new Error(`Docker ${method} ${path} failed: ${text || response.statusCode}`);
        error.statusCode = response.statusCode;
        throw error;
      }
      return response.buffer;
    }
    return parseJsonResponse(response, `Docker ${method} ${path}`);
  }

  async listWorkloads() {
    if (!(await this.available())) return [];
    const filters = encodeURIComponent(JSON.stringify({ label: ['cubynode.managed=true'] }));
    const containers = await this.request('GET', `/containers/json?all=1&filters=${filters}`);

    return Promise.all(containers.map(async (container) => {
      let stats = null;
      if (container.State === 'running') {
        try {
          stats = await this.request('GET', `/containers/${container.Id}/stats?stream=false`, null, { timeoutMs: 5_000 });
        } catch {
          stats = null;
        }
      }

      const labels = container.Labels ?? {};
      const name = labels['cubynode.name'] || container.Names?.[0]?.replace(/^\//, '') || container.Id.slice(0, 12);
      const memoryUsage = stats?.memory_stats?.usage ?? 0;
      const memoryLimit = stats?.memory_stats?.limit ?? 0;

      return {
        id: container.Id,
        externalId: container.Id,
        runtime: 'docker',
        kind: iabels['cubynode.kind'] || 'unknown',
        name,
        status: normalizeDockerStatus(container.State),
        statusDetail: container.Status ?? null,
        image: container.Image,
        demo: labels['cubynode.demo'] === 'true',
        template: labels['cubynode.template'] || null,
        createdAt: container.Created ? new Date(container.Created * 1000).toISOString() : null,
        cpuPercent: stats ? dockerCpuPercent(stats) : 0,
        memoryUsedBytes: memoryUsage,
        memoryLimitBytes: memoryLimit,
        ports: (container.Ports ?? []).map((port) => ({
          privatePort: port.PrivatePort,
          publicPort: port.PublicPort ?? null,
          type: port.Type,
          ip: port.IP ?? null,
        })),
      };
    }));
  }

  async action(id, action) {
    const encoded = encodeURIComponent(id);
    if (action === 'start') {
      await this.request('POST', `/containers/${encoded}/start`);
    } else if (action === 'stop') {
      await this.request('POST', `/containers/${encoded}/stop?t=10`);
    } else if (action === 'restart') {
      await this.request('POST', `/containers/${encoded}/restart?t=10`);
    } else {
      const error = new Error(`Unsupported Docker action: ${action}`);
      error.statusCode = 400;
      throw error;
    }
    return { accepted: true };
  }

  async logs(id, tail = 200) {
    const safeTail = Math.max(1, Math.min(2_000, Number(tail) || 200));
    const raw = await this.request(
      'GET',
      `/containers/${encodeURIComponent(id)}/logs?stdout=1&stderr=1&timestamps=1&tail=${safeTail}`,
      null,
      { raw: true, timeoutMs: 10_000 },
    );
    return decodeDockerStream(raw);
  }
}

export function normalizeDockerStatus(state) {
  const map = {
    running: 'running',
    paused: 'paused',
    restarting: 'restarting',
    created: 'created',
    exited: 'stopped',
    dead: 'stopped',
    removing: 'stopping',
  };
  return map[state] || state || 'unknown';
}

export function dockerCpuPercent(stats) {
  const cpuDelta = (stats.cpu_stats?.cpu_usage?.total_usage ?? 0) - (stats.precpu_stats?.cpu_usage?.total_usage ?? 0);
  const systemDelta = (stats.cpu_stats?.system_cpu_usage ?? 0) - (stats.precpu_stats?.system_cpu_usage ?? 0);
  const onlineCpus = stats.cpu_stats?.online_cpus || stats.cpu_stats?.cpu_usage?.percpu_usage?.length || 1;
  if (cpuDelta <= 0 || systemDelta <= 0) return 0;
  return Number(((cpuDelta / systemDelta) * onlineCpus * 100).toFixed(2));
}

export function decodeDockerStream(buffer) {
  if (!buffer?.length) return '';

  const chunks = [];
  let offset = 0;
  let framed = true;

  while (offset + 8 <= buffer.length) {
    const streamType = buffer[offset];
    if (![0, 1, 2, 3].includes(streamType) || buffer[offset + 1] !== 0 || buffer[offset + 2] !== 0 || buffer[offset + 3] !== 0) {
      framed = false;
      break;
    }
    const length = buffer.readUInt32BE(offset + 4);
    if (offset + 8 + length > buffer.length) {
      framed = false;
      break;
    }
    chunks.push(buffer.subarray(offset + 8, offset + 8 + length));
    offset += 8 + length;
  }

  if (!framed || (offset === 0 && chunks.length === 0)) return buffer.toString('utf8');
  return Buffer.concat(chunks).toString('utf8');
}
