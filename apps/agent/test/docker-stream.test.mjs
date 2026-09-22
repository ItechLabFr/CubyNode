import assert from 'node:assert/strict';
import test from 'node:test';
import { decodeDockerStream, dockerCpuPercent, normalizeDockerStatus } from '../src/drivers/docker.mjs';

function frame(streamType, text) {
  const payload = Buffer.from(text);
  const header = Buffer.alloc(8);
  header[0] = streamType;
  header.writeUInt32BE(payload.length, 4);
  return Buffer.concat([header, payload]);
}

test('decodes Docker multiplexed stdout/stderr frames', () => {
  const data = Buffer.concat([frame(1, 'hello\n'), frame(2, 'warn\n')]);
  assert.equal(decodeDockerStream(data), 'hello\nwarn\n');
});

test('keeps plain TTY log output intact', () => {
  assert.equal(decodeDockerStream(Buffer.from('plain\n')), 'plain\n');
});

test('normalizes Docker states', () => {
  assert.equal(normalizeDockerStatus('exited'), 'stopped');
  assert.equal(normalizeDockerStatus('running'), 'running');
});

test('calculates Docker CPU percentage', () => {
  const stats = {
    cpu_stats: { online_cpus: 2, system_cpu_usage: 1200, cpu_usage: { total_usage: 300 } },
    precpu_stats: { system_cpu_usage: 1000, cpu_usage: { total_usage: 200 } },
  };
  assert.equal(dockerCpuPercent(stats), 100);
});
