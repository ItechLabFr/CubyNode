import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function cpuSnapshot() {
  let idle = 0;
  let total = 0;
  for (const cpu of os.cpus()) {
    const values = Object.values(cpu.times);
    idle += cpu.times.idle;
    total += values.reduce((sum, value) => sum + value, 0);
  }
  return { idle, total };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function cpuUsagePercent() {
  const first = cpuSnapshot();
  await sleep(180);
  const second = cpuSnapshot();
  const totalDelta = second.total - first.total;
  const idleDelta = second.idle - first.idle;
  if (totalDelta <= 0) return 0;
  return Math.max(0, Math.min(100, ((totalDelta - idleDelta) / totalDelta) * 100));
}

function readMemInfo(root) {
  const candidate = path.join(root, 'proc', 'meminfo');
  if (!fs.existsSync(candidate)) {
    return { total: os.totalmem(), used: os.totalmem() - os.freemem() };
  }

  const values = {};
  const text = fs.readFileSync(candidate, 'utf8');
  for (const line of text.split('\n')) {
    const match = line.match(/^([^:]+):\s+(\d+)\s+kB$/);
    if (match) values[match[1]] = Number(match[2]) * 1024;
  }
  const total = values.MemTotal ?? os.totalmem();
  const available = values.MemAvailable ?? values.MemFree ?? os.freemem();
  return { total, used: Math.max(0, total - available) };
}

function readStorage(root) {
  const stat = fs.statfsSync(root);
  const total = Number(stat.blocks) * Number(stat.bsize);
  const free = Number(stat.bavail) * Number(stat.bsize);
  return { total, used: Math.max(0, total - free) };
}

export async function collectNodeMetrics(metricsRoot = '/') {
  const root = fs.existsSync(metricsRoot) ? metricsRoot : '/';
  const [cpuPercent, memory] = await Promise.all([
    cpuUsagePercent(),
    Promise.resolve(readMemInfo(root)),
  ]);

  let storage = { total: 0, used: 0 };
  try {
    storage = readStorage(root);
  } catch {
    storage = readStorage('/');
  }

  return {
    collectedAt: new Date().toISOString(),
    cpuPercent: Number(cpuPercent.toFixed(2)),
    cpuThreads: os.cpus().length,
    loadAverage: os.loadavg(),
    memoryUsedBytes: memory.used,
    memoryTotalBytes: memory.total,
    storageUsedBytes: storage.used,
    storageTotalBytes: storage.total,
    uptimeSeconds: Math.floor(os.uptime()),
    hostname: os.hostname(),
    platform: os.platform(),
    arch: os.arch(),
  };
}
