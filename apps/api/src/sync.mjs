import { insertNodeMetric, setNodeOffline, syncWorkloads, upsertNode } from './db.mjs';

export class NodeSynchronizer {
  constructor({ pool, agentClient, agentUrl, intervalMs = 5_000 }) {
    this.pool = pool;
    this.agentClient = agentClient;
    this.agentUrl = agentUrl;
    this.intervalMs = intervalMs;
    this.timer = null;
    this.running = false;
    this.nodeId = null;
  }

  async sync() {
    if (this.running) return;
    this.running = true;
    try {
      const [node, workloadResponse] = await Promise.all([
        this.agentClient.node(),
        this.agentClient.workloads(),
      ]);
      this.nodeId = node.id;
      await upsertNode(this.pool, {
        id: node.id,
        name: node.name,
        agentUrl: this.agentUrl,
        runtimes: node.capabilities?.runtimes ?? [],
        status: 'online',
        lastSeen: new Date(),
      });
      await insertNodeMetric(this.pool, node.id, node.metrics);
      await syncWorkloads(this.pool, node.id, workloadResponse.workloads ?? []);
    } catch (error) {
      console.error('Node sync failed:', error.message);
      if (this.nodeId) await setNodeOffline(this.pool, this.nodeId).catch(() => {});
    } finally {
      this.running = false;
    }
  }

  start() {
    if (this.timer) return;
    void this.sync();
    this.timer = setInterval(() => void this.sync(), this.intervalMs);
    this.timer.unref?.();
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }
}
