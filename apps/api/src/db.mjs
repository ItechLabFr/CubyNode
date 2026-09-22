import pg from 'pg';

const { Pool } = pg;

export function createPool(connectionString) {
  return new Pool({
    connectionString,
    max: 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
  });
}

export async function waitForDatabase(pool, { attempts = 30, delayMs = 2_000 } = {}) {
  let lastError;
  for (let i = 0; i < attempts; i += 1) {
    try {
      await pool.query('select 1');
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  throw lastError;
}

export async function initDatabase(pool) {
  await pool.query(`
    create table if not exists nodes (
      id text primary key,
      name text not null,
      agent_url text not null,
      runtimes text[] not null default '{}',
      status text not null default 'unknown',
      last_seen timestamptz,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create table if not exists workloads (
      id text primary key,
      external_id text not null,
      node_id text not null references nodes(id) on delete cascade,
      runtime text not null,
      kind text not null,
      name text not null,
      status text not null,
      status_detail text,
      image text,
      demo boolean not null default false,
      template text,
      cpu_percent double precision,
      memory_used_bytes bigint,
      memory_limit_bytes bigint,
      ports jsonb not null default '[]'::jsonb,
      remote_created_at timestamptz,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create index if not exists workloads_node_idx on workloads(node_id);
    create index if not exists workloads_kind_idx on workloads(kind);

    create table if not exists node_metrics (
      id bigserial primary key,
      node_id text not null references nodes(id) on delete cascade,
      collected_at timestamptz not null,
      cpu_percent double precision not null,
      cpu_threads integer not null,
      memory_used_bytes bigint not null,
      memory_total_bytes bigint not null,
      storage_used_bytes bigint not null,
      storage_total_bytes bigint not null,
      uptime_seconds bigint,
      load_average jsonb not null default '[]'::jsonb
    );

    create index if not exists node_metrics_node_time_idx on node_metrics(node_id, collected_at desc);

    create table if not exists activity (
      id bigserial primary key,
      event_type text not null,
      message text not null,
      workload_id text,
      node_id text references nodes(id) on delete set null,
      details jsonb not null default '{}'::jsonb,
      created_at timestamptz not null default now()
    );

    create index if not exists activity_created_idx on activity(created_at desc);
  `);
}

export async function upsertNode(pool, { id, name, agentUrl, runtimes, status = 'online', lastSeen = new Date() }) {
  await pool.query(`
    insert into nodes (id, name, agent_url, runtimes, status, last_seen, updated_at)
    values ($1, $2, $3, $4, $5, $6, now())
    on conflict (id) do update set
      name = excluded.name,
      agent_url = excluded.agent_url,
      runtimes = excluded.runtimes,
      status = excluded.status,
      last_seen = excluded.last_seen,
      updated_at = now()
  `, [id, name, agentUrl, runtimes, status, lastSeen]);
}

export async function setNodeOffline(pool, nodeId) {
  await pool.query(`update nodes set status = 'offline', updated_at = now() where id = $1`, [nodeId]);
}

export async function insertNodeMetric(pool, nodeId, metric) {
  await pool.query(`
    insert into node_metrics (
      node_id, collected_at, cpu_percent, cpu_threads, memory_used_bytes,
      memory_total_bytes, storage_used_bytes, storage_total_bytes, uptime_seconds, load_average
    ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
  `, [
    nodeId,
    metric.collectedAt,
    metric.cpuPercent,
    metric.cpuThreads,
    metric.memoryUsedBytes,
    metric.memoryTotalBytes,
    metric.storageUsedBytes,
    metric.storageTotalBytes,
    metric.uptimeSeconds,
    JSON.stringify(metric.loadAverage ?? []),
  ]);

  await pool.query(`delete from node_metrics where collected_at < now() - interval '8 days'`);
}

export async function syncWorkloads(pool, nodeId, workloads) {
  const existingResult = await pool.query(`select id, name, status, runtime, external_id from workloads where node_id = $1`, [nodeId]);
  const existing = new Map(existingResult.rows.map((row) => [row.id, row]));
  const seen = new Set();

  for (const workload of workloads) {
    const id = workloadKey(nodeId, workload.runtime, workload.externalId);
    seen.add(id);
    const previous = existing.get(id);

    await pool.query(`
      insert into workloads (
        id, external_id, node_id, runtime, kind, name, status, status_detail,
        image, demo, template, cpu_percent, memory_used_bytes, memory_limit_bytes,
        ports, remote_created_at, updated_at
      ) values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,now())
      on conflict (id) do update set
        kind = excluded.kind,
        name = excluded.name,
        status = excluded.status,
        status_detail = excluded.status_detail,
        image = excluded.image,
        demo = excluded.demo,
        template = excluded.template,
        cpu_percent = excluded.cpu_percent,
        memory_used_bytes = excluded.memory_used_bytes,
        memory_limit_bytes = excluded.memory_limit_bytes,
        ports = excluded.ports,
        remote_created_at = excluded.remote_created_at,
        updated_at = now()
    `, [
      id,
      workload.externalId,
      nodeId,
      workload.runtime,
      workload.kind,
      workload.name,
      workload.status,
      workload.statusDetail,
      workload.image,
      Boolean(workload.demo),
      workload.template,
      workload.cpuPercent,
      workload.memoryUsedBytes,
      workload.memoryLimitBytes,
      JSON.stringify(workload.ports ?? []),
      workload.createdAt,
    ]);

    if (!previous) {
      await addActivity(pool, {
        eventType: 'workload.discovered',
        message: `${workload.name} discovered on ${nodeId}`,
        workloadId: id,
        nodeId,
        details: { runtime: workload.runtime, kind: workload.kind, demo: Boolean(workload.demo) },
      });
    } else if (previous.status !== workload.status) {
      await addActivity(pool, {
        eventType: 'workload.status_changed',
        message: `${workload.name}: ${previous.status} → ${workload.status}`,
        workloadId: id,
        nodeId,
        details: { from: previous.status, to: workload.status },
      });
    }
  }

  for (const previous of existing.values()) {
    if (seen.has(previous.id)) continue;
    await addActivity(pool, {
      eventType: 'workload.removed',
      message: `${previous.name} removed from ${nodeId}`,
      workloadId: null,
      nodeId,
      details: { runtime: previous.runtime, externalId: previous.external_id },
    });
    await pool.query(`delete from workloads where id = $1`, [previous.id]);
  }
}

export async function addActivity(pool, { eventType, message, workloadId = null, nodeId = null, details = {} }) {
  await pool.query(`
    insert into activity (event_type, message, workload_id, node_id, details)
    values ($1,$2,$3,$4,$5)
  `, [eventType, message, workloadId, nodeId, JSON.stringify(details)]);
}

export function workloadKey(nodeId, runtime, externalId) {
  return `${nodeId}:${runtime}:${externalId}`;
}
