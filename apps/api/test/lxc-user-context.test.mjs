import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

function read(rel) {
  return fs.readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');
}

test('native LXC scripts run node and npm from the repository working directory', () => {
  const bootstrap = read('../../../scripts/lxc-bootstrap.sh');
  const updater = read('../../../scripts/cubynode-update');

  for (const [name, source] of [['bootstrap', bootstrap], ['updater', updater]]) {
    assert.match(
      source,
      /sh -c 'cd "\$1" && shift && exec "\$@"'/,
      `${name} must force a readable repository cwd before dropping privileges`,
    );
    assert.doesNotMatch(
      source,
      /runuser -u cubynode -- npm --prefix/,
      `${name} must not invoke npm from root's inherited cwd`,
    );
    assert.match(source, /run_cubynode_repo npm /);
    assert.match(source, /run_cubynode_repo node -p/);
  }
});
