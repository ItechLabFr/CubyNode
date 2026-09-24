import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const publicDir=new URL('../public/',import.meta.url);
const read=rel=>fs.readFileSync(fileURLToPath(new URL(rel,publicDir)),'utf8');

test('PWA manifest and official brand assets are wired into the panel',()=>{
  const manifest=JSON.parse(read('manifest.webmanifest'));
  assert.equal(manifest.name,'CubyNode');
  assert.equal(manifest.short_name,'CubyNode');
  assert.equal(manifest.display,'standalone');
  assert.ok(manifest.icons.some(icon=>icon.purpose==='maskable'));

  for(const icon of manifest.icons){
    const file=fileURLToPath(new URL(icon.src.replace(/^\//,''),publicDir));
    assert.ok(fs.statSync(file).size>0,`missing/empty PWA icon: ${icon.src}`);
  }

  for(const file of [
    'icons/apple-touch-icon.png',
    'icons/android-chrome-192x192.png',
    'icons/android-chrome-512x512.png',
    'icons/favicon-32x32.png',
    'brand/icon-light.svg',
    'brand/icon-dark.svg',
    'brand/logo-light.svg',
    'brand/logo-dark.svg',
    'favicon.ico'
  ]){
    assert.ok(fs.statSync(fileURLToPath(new URL(file,publicDir))).size>0,`missing/empty brand asset: ${file}`);
  }

  const html=read('index.html');
  assert.match(html,/manifest\.webmanifest/);
  assert.match(html,/apple-touch-icon/);
  assert.match(html,/brand\/icon-light\.svg/);
  assert.match(html,/brand\/icon-dark\.svg/);

  const app=read('app.js');
  assert.match(app,/serviceWorker\.register\("\/service-worker\.js"\)/);
});
