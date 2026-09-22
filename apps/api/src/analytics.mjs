export function percent(part, total) {
  if (!Number(total)) return 0;
  return Math.max(0, Math.min(100, (Number(part) / Number(total)) * 100));
}

export function aggregateMetricHistory(rows, maxPoints = 96) {
  if (!rows?.length) return [];
  const sorted = [...rows].sort((a, b) => new Date(a.collected_at) - new Date(b.collected_at));
  const buckets = new Map();
  const bucketMs = Math.max(1, Math.ceil((new Date(sorted.at(-1).collected_at) - new Date(sorted[0].collected_at) || 1) / maxPoints));

  for (const row of sorted) {
    const timestamp = new Date(row.collected_at).getTime();
    const key = Math.floor(timestamp / bucketMs) * bucketMs;
    const bucket = buckets.get(key) || { ts: key, count: 0, cpu: 0, memory: 0, storage: 0 };
    bucket.count += 1;
    bucket.cpu += Number(row.cpu_percent || 0);
    bucket.memory += percent(row.memory_used_bytes, row.memory_total_bytes);
    bucket.storage += percent(row.storage_used_bytes, row.storage_total_bytes);
    buckets.set(key, bucket);
  }

  return [...buckets.values()].map((bucket) => ({
    timestamp: new Date(bucket.ts).toISOString(),
    cpuPercent: Number((bucket.cpu / bucket.count).toFixed(2)),
    memoryPercent: Number((bucket.memory / bucket.count).toFixed(2)),
    storagePercent: Number((bucket.storage / bucket.count).toFixed(2)),
  }));
}

function observedSingleSeries(rows, expectedIntervalMs) {
  if (!rows || rows.length < 3) return null;
  const times = rows.map((row) => new Date(row.collected_at).getTime()).sort((a, b) => a - b);
  const span = times.at(-1) - times[0];
  if (span < expectedIntervalMs * 2) return null;
  const expectedSamples = Math.floor(span / expectedIntervalMs) + 1;
  return Math.min(100, (times.length / expectedSamples) * 100);
}

export function observedUptimePercent(rows, expectedIntervalMs = 5_000) {
  if (!rows || rows.length < 3) return null;
  const hasNodeIds = rows.some((row) => row.node_id != null);
  if (!hasNodeIds) {
    const value = observedSingleSeries(rows, expectedIntervalMs);
    return value == null ? null : Number(value.toFixed(2));
  }

  const groups = new Map();
  for (const row of rows) {
    const key = row.node_id || '__unknown__';
    const group = groups.get(key) || [];
    group.push(row);
    groups.set(key, group);
  }
  const values = [...groups.values()]
    .map((group) => observedSingleSeries(group, expectedIntervalMs))
    .filter((value) => value != null);
  if (!values.length) return null;
  return Number((values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(2));
}
