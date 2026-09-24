import crypto from 'node:crypto';
import http from 'node:http';
import { URL } from 'node:url';
import { DockerDriver } from './drivers/docker.mjs';
import { collectNodeMetrics } from './metrics.mjs';

const port = Number(process.env.CUBYNODE_AGENT_PORT || 8081);
const token = process.env.CUBYNODE_AGENT_TOKEN || '';
const nodeId = process.env.CUBYNODE_NODE_ID || 'local-node';
const nodeName = process.env.CUBYNODE_NODE_NAME || nodeId;
const metricsRoot = process.env.CUBYNODE_METRICS_ROOT || '/';

if (!token) {
  console.error('CUBYNODE_AGENT_TOKEN is required.');
  process.exit(1);
}

const docker = new DockerDriver(process.env.CUBYNODE_DOCKER_SOCKET || '/var/run/docker.sock');

function json(response, statusCode, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  response.end(body);
}

function authorized(request) {
  const header = request.headers.authorization || '';
  const candidate = header.startsWith('Bearer ') ? header.slice(7) : '';
  const a = Buffer.from(candidate);
  const b = Buffer.from(token);
  return a.length === b.length && a.length > 0 && crypto.timingSafeEqual(a, b);
}

async function capabilities() {
  const dockerAvailable = await docker.available();
  return {
    runtimes: dockerAvailable ? ['docker'] : [],
    docker: dockerAvailable,
  };
}

async function listWorkloads() {
  return (await docker.available()) ? docker.listWorkloads() : [];
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);

  try {
    if (request.method === 'GET' && url.pathname === '/health') {
      return json(response, 200, { ok: true, service: 'cubynode-agent', nodeId });
    }

    if (!authorized(request)) return json(response, 401, { error: 'unauthorized' });

    if (request.method === 'GET' && url.pathname === '/v1/capabilities') {
      return json(response, 200, await capabilities());
    }

    if (request.method === 'GET' && url.pathname === '/v1/metrics') {
      return json(response, 200, await collectNodeMetrics(metricsRoot));
    }

    if (request.method === 'GET' && url.pathname === '/v1/node') {
      const [caps, metrics] = await Promise.all([capabilities(), collectNodeMetrics(metricsRoot)]);
      return json(response, 200, { id: nodeId, name: nodeName, capabilities: caps, metrics });
    }

    if (request.method === 'GET' && url.pathname === '/v1/workloads') {
      return json(response, 200, { workloads: await listWorkloads() });
    }

    const logsMatch = url.pathname.match(/^\/v1\/workloads\/docker\/([^/]+)\/logs$/);
    if (request.method === 'GET' && logsMatch) {
      const id = decodeURIComponent(logsMatch[1]);
      const logs = await docker.logs(id, url.searchParams.get('tail') || 200);
      return json(response, 200, { logs });
    }

    const actionMatch = url.pathname.match(/^\/v1\/workloads\/docker\/([^/]+)\/(start|stop|restart)$/);
    if (request.method === 'POST' && actionMatch) {
      const id = decodeURIComponent(actionMatch[1]);
      const action = actionMatch[2];
      const result = await docker.action(id, action);
      return json(response, 202, result);
    }

    return json(response, 404, { error: 'not_found' });
  } catch (error) {
    console.error(error);
    return json(response, Number(error.statusCode) || 500, { error: error.message || 'internal_error' });
  }
});

server.listen(port, '0.0.0.0', () => {
  console.log(`CubyNode Docker agent ${nodeId} listening on :${port}`);
});
