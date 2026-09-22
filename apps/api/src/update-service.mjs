import fs from 'node:fs/promises';
import { constants as fsConstants } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync=promisify(execFile);

async function run(command,args,options={}){
  const {stdout}=await execFileAsync(command,args,{timeout:options.timeout??8000,maxBuffer:1024*1024,...options});
  return stdout.trim();
}

async function readJson(pathname){
  try{return JSON.parse(await fs.readFile(pathname,'utf8'))}catch{return null}
}
async function tail(pathname,maxBytes=16000){
  try{
    const data=await fs.readFile(pathname);
    return data.subarray(Math.max(0,data.length-maxBytes)).toString('utf8');
  }catch{return ''}
}
async function executable(pathname){
  try{await fs.access(pathname,fsConstants.X_OK);return true}catch{return false}
}

export function validateUpdateMode(mode){
  if(!['simple','full'].includes(mode)){
    const error=new Error('invalid_update_mode'); error.statusCode=400; throw error;
  }
  return mode;
}

export async function getUpdateStatus({
  repoDir=process.env.CUBYNODE_REPO_DIR||'/opt/cubynode',
  helperPath=process.env.CUBYNODE_UPDATE_HELPER||'/usr/local/sbin/cubynode-update-request',
  statusPath=process.env.CUBYNODE_UPDATE_STATUS||'/var/lib/cubynode/update-status.json',
  logPath=process.env.CUBYNODE_UPDATE_LOG||'/var/log/cubynode/update.log',
  channel=process.env.CUBYNODE_UPDATE_CHANNEL||'main',
  installMode=process.env.CUBYNODE_INSTALL_MODE||'container',
  version=process.env.CUBYNODE_VERSION||'unknown',
}={}){
  const available=await executable(helperPath);
  let currentCommit=null,remoteCommit=null,remoteError=null;
  try{currentCommit=await run('git',['-C',repoDir,'rev-parse','HEAD'])}catch{}
  if(currentCommit){
    try{remoteCommit=(await run('git',['-C',repoDir,'ls-remote','origin','refs/heads/'+channel])).split(/\s+/)[0]||null}
    catch(error){remoteError=error.message}
  }
  const operation=await readJson(statusPath);
  return {
    available,
    installMode,
    channel,
    version,
    currentCommit,
    remoteCommit,
    updateAvailable:Boolean(currentCommit&&remoteCommit&&currentCommit!==remoteCommit),
    remoteError,
    operation,
    log:await tail(logPath),
  };
}

export async function triggerUpdate(mode,{
  helperPath=process.env.CUBYNODE_UPDATE_HELPER||'/usr/local/sbin/cubynode-update-request',
}={}){
  validateUpdateMode(mode);
  if(!(await executable(helperPath))){
    const error=new Error('native_updater_not_available'); error.statusCode=409; throw error;
  }
  try{
    await run('sudo',['-n',helperPath,mode],{timeout:5000});
  }catch(error){
    const wrapped=new Error(error.stderr?.trim()||error.stdout?.trim()||error.message);
    wrapped.statusCode=409; throw wrapped;
  }
  return {accepted:true,mode};
}
