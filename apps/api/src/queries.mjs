import { aggregateMetricHistory, observedUptimePercent, percent } from './analytics.mjs';

export async function getOverview(pool, syncIntervalMs = 5_000) {
  const [nodesResult, workloadsResult, metricRowsResult, latestMetricResult, activityResult] = await Promise.all([
    pool.query(`select id, name, runtimes, status, last_seen, updated_at from nodes order by name`),
    pool.query(`select * from workloads order by kind, name`),
    pool.query(`select * from node_metrics where collected_at >= now() - interval '24 hours' order by collected_at`),
    pool.query(`
      select distinct on (node_id) * from node_metrics
      order by node_id, collected_at desc
    `),
    pool.query(`select id, event_type, message, workload_id, node_id, details, created_at from activity order by created_at desc limit 12`),
  ]);

  const nodes = nodesResult.rows;
  const workloads = workloadsResult.rows.map(serializeWorkload);
  const latestMetrics = latestMetricResult.rows;
  const running = workloads.filter((workload) => workload.status === 'running').length;
  const total = workloads.length;

  const aggregate = latestMetrics.reduce((acc, metric) => {
    acc.cpu += Number(metric.cpu_percent || 0);
    acc.cpuThreads += Number(metric.cpu_threads || 0);
    acc.memoryUsed += Number(metric.memory_used_bytes || 0);
    acc.memoryTotal += Number(metric.memory_total_bytes || 0);
    acc.storageUsed += Number(metric.storage_used_bytes || 0);
    acc.storageTotal += Number(metric.storage_total_bytes || 0);
    return acc;
  }, { cpu: 0, cpuThreads: 0, memoryUsed: 0, memoryTotal: 0, storageUsed: 0, storageTotal: 0 });

  const nodeCountForCpu = Math.max(1, latestMetrics.length);
  const metricRows = metricRowsResult.rows;

  return {
    generatedAt: new Date().toISOString(),
    summary: {
      totalInstances: total,
      onlineServices: running,
      nodeCount: nodes.length,
      onlineNodes: nodes.filter((node) => node.status === 'online').length,
      observedUptimePercent: observedUptimePercent(metricRows, syncIntervalMs),
    },
    resource: {
      cpuPercent: Number((aggregate.cpu / nodeCountForCpu).toFixed(2)),
      cpuThreads: aggregate.cpuThreads,
      memoryUsedBytes: aggregate.memoryUsed,
      memoryTotalBytes: aggregate.memoryTotal,
      memoryPercent: Number(percent(aggregate.memoryUsed, aggregate.memoryTotal).toFixed(2)),
      storageUsedBytes: aggregate.storageUsed,
      storageTotalBytes: aggregate.storageTotal,
      storagePercent: Number(percent(aggregate.storageUsed, aggregate.storageTotal).toFixed(2)),
      history: aggregateMetricHistory(metricRows),
    },
    nodes: nodes.map((node) => {
      const metric = latestMetrics.find((item) => item.node_id === node.id);
      return {
        id: node.id,
        name: node.name,
        runtimes: node.runtimes,
        status: node.status,
        lastSeen: node.last_seen,
        cpuPercent: metric ? Number(metric.cpu_percent) : null,
        cpuThreads: metric ? Number(metric.cpu_threads) : null,
        memoryUsedBytes: metric ? Number(metric.memory_used_bytes) : null,
        memoryTotalBytes: metric ? Number(metric.memory_total_bytes) : null,
        storageUsedBytes: metric ? Number(metric.storage_used_bytes) : null,
        storageTotalBytes: metric ? Number(metric.storage_total_bytes) : null,
      };
    }),
    workloads,
    activity: activityResult.rows.map((row) => ({
      id: Number(row.id),
      eventType: row.event_type,
      message: row.message,
      workloadId: row.workload_id,
      nodeId: row.node_id,
      details: row.details,
      createdAt: row.created_at,
    })),
  };
}

export async function getWorkload(pool, id) {
  const result = await pool.query(`
    select w.*, n.agent_url
    from workloads w
    join nodes n on n.id = w.node_id
    where w.id = $1
  `, [id]);
  return result.rows[0] ? serializeWorkload(result.rows[0]) : null;
}

export function serializeWorkload(row) {
  return {
    id: row.id,
    externalId: row.external_id,
    nodeId: row.node_id,
    runtime: row.runtime,
    kind: row.kind,
    name: row.name,
    status: row.status,
    statusDetail: row.status_detail,
    image: row.image,
    demo: row.demo,
    template: row.template,
    cpuPercent: row.cpu_percent == null ? null : Number(row.cpu_percent),
    memoryUsedBytes: Number(row.memory_used_bytes || 0),
    memoryLimitBytes: Number(row.memory_limit_bytes || 0),
    ports: row.ports ?? [],
    createdAt: row.remote_created_at,
    updatedAt: row.updated_at,
    agentUrl: row.agent_url || null,
  };
}
