import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { URL } from 'node:url';
import { AgentClient } from './agent-client.mjs';
import { addActivity, createPool, initDatabase, waitForDatabase } from './db.mjs';
import { getOverview, getWorkload } from './queries.mjs';
import { NodeSynchronizer } from './sync.mjs';

const __dirname=path.dirname(fileURLToPath(import.meta.url));
const publicDir=path.resolve(__dirname,'../public');
const port=Number(process.env.CUBYNODE_API_PORT||8080);
const version=process.env.CUBYNODE_VERSION||'1.0.0-beta.1';
const databaseUrl=process.env.DATABASE_URL||'';
const panelToken=process.env.CUBYNODE_PANEL_TOKEN||'';
const agentToken=process.env.CUBYNODE_AGENT_TOKEN||'';
const agentUrls=(process.env.CUBYNODE_AGENT_URLS||process.env.CUBYNODE_AGENT_URL||'http://127.0.0.1:8081')
  .split(',').map(v=>v.trim()).filter(Boolean);
const syncIntervalMs=Number(process.env.CUBYNODE_SYNC_INTERVAL_MS||5000);

for(const [name,value] of Object.entries({DATABASE_URL:databaseUrl,CUBYNODE_PANEL_TOKEN:panelToken,CUBYNODE_AGENT_TOKEN:agentToken})){
  if(!value){console.error(name+' is required.');process.exit(1)}
}

const pool=createPool(databaseUrl);
await waitForDatabase(pool);
await initDatabase(pool);

const synchronizers=agentUrls.map(agentUrl=>{
  const s=new NodeSynchronizer({pool,agentClient:new AgentClient(agentUrl,agentToken),agentUrl,intervalMs:syncIntervalMs});
  s.start();
  return s;
});

function secureEqual(candidate,expected){
  const a=Buffer.from(candidate||''); const b=Buffer.from(expected||'');
  return a.length===b.length&&a.length>0&&crypto.timingSafeEqual(a,b);
}
function authorized(req){
  const h=req.headers.authorization||'';
  return h.startsWith('Bearer ')&&secureEqual(h.slice(7),panelToken);
}
function json(res,status,payload){
  const body=JSON.stringify(payload);
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Content-Length':Buffer.byteLength(body),'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(body);
}
function fail(res,error){
  console.error(error);
  json(res,Number(error.statusCode)||500,{error:error.message||'internal_error'});
}
async function routeApi(req,res,url){
  if(req.method==='GET'&&url.pathname==='/api/version') return json(res,200,{version});
  if(req.method==='GET'&&url.pathname==='/api/health') return json(res,200,{ok:true,service:'cubynode-api',version});
  if(!authorized(req)) return json(res,401,{error:'unauthorized'});
  if(req.method==='GET'&&url.pathname==='/api/session') return json(res,200,{ok:true,version});
  if(req.method==='GET'&&url.pathname==='/api/overview') return json(res,200,await getOverview(pool,syncIntervalMs));
  if(req.method==='POST'&&url.pathname==='/api/sync'){
    await Promise.all(synchronizers.map(s=>s.sync()));
    return json(res,202,{accepted:true});
  }
  const m=url.pathname.match(/^\/api\/workloads\/(.+?)\/(logs|start|stop|restart)$/);
  if(m){
    const workloadId=decodeURIComponent(m[1]), operation=m[2];
    const workload=await getWorkload(pool,workloadId);
    if(!workload) return json(res,404,{error:'workload_not_found'});
    const client=new AgentClient(workload.agentUrl,agentToken);
    if(req.method==='GET'&&operation==='logs'){
      const result=await client.logs(workload.runtime,workload.externalId,url.searchParams.get('tail')||200);
      return json(res,200,{workloadId,logs:result.logs});
    }
    if(req.method==='POST'&&['start','stop','restart'].includes(operation)){
      await client.action(workload.runtime,workload.externalId,operation);
      await addActivity(pool,{eventType:'workload.'+operation+'_requested',message:operation+' requested for '+workload.name,workloadId:workload.id,nodeId:workload.nodeId,details:{runtime:workload.runtime}});
      const owner=synchronizers.find(s=>s.agentUrl===workload.agentUrl);
      if(owner) setTimeout(()=>void owner.sync(),500).unref?.();
      return json(res,202,{accepted:true});
    }
  }
  return json(res,404,{error:'not_found'});
}

const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.json':'application/json; charset=utf-8'};
async function staticFile(res,pathname){
  const requested=pathname==='/'?'/index.html':pathname;
  const normalized=path.posix.normalize(requested);
  const file=path.resolve(publicDir,'.'+(normalized.startsWith('/')?normalized:'/'+normalized));
  if(!file.startsWith(publicDir)) return json(res,403,{error:'forbidden'});
  try{
    const data=await fs.readFile(file);
    const ext=path.extname(file);
    res.writeHead(200,{'Content-Type':mime[ext]||'application/octet-stream','Content-Length':data.length,'Cache-Control':ext==='.html'?'no-cache':'public, max-age=3600','X-Content-Type-Options':'nosniff','Referrer-Policy':'same-origin'});
    res.end(data);
  }catch(error){
    if(error.code==='ENOENT'){
      const data=await fs.readFile(path.join(publicDir,'index.html'));
      res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Content-Length':data.length,'Cache-Control':'no-cache'});
      return res.end(data);
    }
    throw error;
  }
}

const server=http.createServer(async(req,res)=>{
  const url=new URL(req.url,'http://'+(req.headers.host||'localhost'));
  try{
    if(url.pathname.startsWith('/api/')) return await routeApi(req,res,url);
    if(!['GET','HEAD'].includes(req.method)) return json(res,405,{error:'method_not_allowed'});
    await staticFile(res,url.pathname);
  }catch(error){fail(res,error)}
});

function shutdown(signal){
  console.log('Received '+signal+', shutting down...');
  synchronizers.forEach(s=>s.stop());
  server.close(async()=>{await pool.end().catch(()=>{});process.exit(0)});
  setTimeout(()=>process.exit(1),10000).unref?.();
}
process.on('SIGTERM',()=>shutdown('SIGTERM'));
process.on('SIGINT',()=>shutdown('SIGINT'));
server.listen(port,'0.0.0.0',()=>console.log('CubyNode API '+version+' listening on :'+port));
