import assert from 'node:assert/strict';
import test from 'node:test';
import { validateUpdateMode } from '../src/update-service.mjs';

test('accepts supported update modes',()=>{
  assert.equal(validateUpdateMode('simple'),'simple');
  assert.equal(validateUpdateMode('full'),'full');
});
test('rejects unsupported update modes',()=>{
  assert.throws(()=>validateUpdateMode('shell'),/invalid_update_mode/);
});
