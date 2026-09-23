import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

test('private bootstrap Git helper supplies temporary PAT without interactive prompting', (t) => {
  const bootstrap=fs.readFileSync(fileURLToPath(new URL('../../../scripts/lxc-bootstrap.sh', import.meta.url)), 'utf8');
  const match=bootstrap.match(/cat >"\$GIT_ASKPASS_FILE" <<'ASKPASS'\n([\s\S]*?)\nASKPASS/);
  assert.ok(match, 'actual bootstrap askpass helper should be available for testing');

  const dir=fs.mkdtempSync(path.join(os.tmpdir(), 'cubynode-auth-test-'));
  t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const helper=path.join(dir,'askpass.sh');
  const tokenFile=path.join(dir,'secret');
  fs.writeFileSync(helper,match[1]+'\n',{mode:0o700});
  fs.writeFileSync(tokenFile,'test-only-secret-token',{mode:0o600});
  const env={
    ...process.env,
    GIT_ASKPASS:helper,
    CUBYNODE_GIT_TOKEN_FILE:tokenFile,
    GIT_TERMINAL_PROMPT:'0',
  };

  const git=spawnSync('git',['-c','credential.helper=','credential','fill'],{
    input:'protocol=https\nhost=github.com\n\n',
    env,
    encoding:'utf8',
  });
  assert.equal(git.status,0,'Git should get both credentials without user input');
  assert.match(git.stdout,/^username=x-access-token$/m);
  assert.match(git.stdout,/^password=test-only-secret-token$/m);
  assert.ok(!bootstrap.includes('git -c "include.path='),'Git must not use the old Bearer header clone path');
});
