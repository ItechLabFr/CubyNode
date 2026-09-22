import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { DockerDriver } from '../src/drivers/docker.mjs';
import { IncusDriver } from '../src/drivers/incus.mjs';

function tempSocket(name) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cubynode-test-'));
  return { dir, socket: path.join(dir, `${name}.sock`) };
}

function listenUnix(server, socket) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(socket, () => { server.unref(); resolve(); });
  });
}

function close(server, dir) {
  server.closeAllConnections?.();
  return new Promise((resolve) => server.close(() => {
    fs.rmSync(dir, { recursive: true, force: true });
    resolve();
  }));
}

function dockerFrame(text) {
  const body = Buffer.from(text);
  const header = Buffer.alloc(8);
  header[0] = 1;
  header.writeUInt32BE(body.length, 4);
  return Buffer.concat([header, body]);
}

test('DockerDriver discovers a managed real-runtime shape and controls it over the Engine API', async () => {
  const { dir, socket } = tempSocket('docker');
  const calls = [];
  const server = http.createServer((req, res) => {
    calls.push(`${req.method} ${req.url}`);
    if (req.url === '/_ping') return res.end('OK');
    if (req.url === '/version') return res.end(JSON.stringify({ ApiVersion: '1.99' }));
    if (req.url.startsWith('/v1.99/containers/json')) {
      res.setHeader('content-type', 'application/json');
      return res.end(JSON.stringify([{
        Id: 'abc123', Names: ['/demo'], Image: 'alpine:3.22', State: 'running', Status: 'Up 1 minute', Created: 1_800_000_000,
        Labels: { 'cubynode.managed': 'true', 'cubynode.demo': 'true', 'cubynode.kind': 'minecraft', 'cubynode.name': 'Demo Minecraft' },
        Ports: [],
      }]));
    }
    if (req.url === '/v1.99/containers/abc123/stats?stream=false') {
      res.setHeader('content-type', 'application/json');
      return res.end(JSON.stringify({
        cpu_stats: { online_cpus: 1, system_cpu_usage: 200, cpu_usage: { total_usage: 100 } },
        precpu_stats: { system_cpu_usage: 100, cpu_usage: { total_usage: 50 } },
        memory_stats: { usage: 1024, limit: 2048 },
      }));
    }
    if (req.url?.startsWith('/v1.99/containers/abc123/logs')) return res.end(dockerFrame('hello from docker\n'));
    if (req.method === 'POST' && req.url === '/v1.99/containers/abc123/restart?t=10') {
      res.writeHead(204); return res.end();
    }
    res.writeHead(404); res.end(JSON.stringify({ message: 'not found' }));
  });

  await listenUnix(server, socket);
  const driver = new DockerDriver(socket);
  assert.equal(await driver.available(), true);
  const workloads = await driver.listWorkloads();
  assert.equal(workloads.length, 1);
  assert.equal(workloads[0].name, 'Demo Minecraft');
  assert.equal(workloads[0].demo, true);
  assert.equal(workloads[0].memoryUsedBytes, 1024);
  assert.equal(await driver.logs('abc123'), 'hello from docker\n');
  await driver.action('abc123', 'restart');
  assert.ok(calls.includes('POST /v1.99/containers/abc123/restart?t=10'));
  await close(server, dir);
});

test('IncusDriver discovers only CubyNode-managed LXC instances and issues lifecycle actions', async () => {
  const { dir, socket } = tempSocket('incus');
  let stateAction = null;
  const server = http.createServer((req, res) => {
    res.setHeader('content-type', 'application/json');
    if (req.url === '/1.0') return res.end(JSON.stringify({ type: 'sync', metadata: { api_version: '1.0' } }));
    if (req.url === '/1.0/instances?recursion=2') {
      return res.end(JSON.stringify({ type: 'sync', metadata: [
        { name: 'mc-lxc', status: 'Running', created_at: '2026-09-22T00:00:00Z', config: { 'user.cubynode.managed': 'true', 'user.cubynode.kind': 'minecraft', 'user.cubynode.name': 'LXC Minecraft' } },
        { name: 'other', status: 'Running', config: {} },
      ] }));
    }
    if (req.url === '/1.0/instances/mc-lxc/state' && req.method === 'GET') return res.end(JSON.stringify({ type: 'sync', metadata: { memory: { usage: 4096, usage_peak: 8192 } } }));
    if (req.url === '/1.0/instances/mc-lxc/state' && req.method === 'PUT') {
      let body = '';
      req.on('data', (chunk) => { body += chunk; });
      req.on('end', () => {
        stateAction = JSON.parse(body).action;
        res.end(JSON.stringify({ type: 'async', metadata: { id: 'op-1' } }));
      });
      return;
    }
    res.writeHead(404); res.end(JSON.stringify({ type: 'error', error: 'not found', error_code: 404 }));
  });

  await listenUnix(server, socket);
  const driver = new IncusDriver(socket);
  assert.equal(await driver.available(), true);
  const workloads = await driver.listWorkloads();
  assert.equal(workloads.length, 1);
  assert.equal(workloads[0].runtime, 'incus');
  assert.equal(workloads[0].name, 'LXC Minecraft');
  assert.equal(workloads[0].memoryUsedBytes, 4096);
  await driver.action('mc-lxc', 'stop');
  assert.equal(stateAction, 'stop');
  await close(server, dir);
});
