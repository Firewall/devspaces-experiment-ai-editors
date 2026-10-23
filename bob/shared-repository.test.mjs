import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, realpathSync, writeFileSync, readFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const source = resolve(process.env.HEADLESSBOB_DIR ?? '/app');
const {loadConfig} = await import(pathToFileURL(join(source, 'dist/config.js')));
const {createApp} = await import(pathToFileURL(join(source, 'dist/app.js')));
const {Store} = await import(pathToFileURL(join(source, 'dist/storage.js')));
const token = 'devspaces-fixture-token-for-tests-only';
function directory(t) {
  const path = realpathSync(mkdtempSync(join(tmpdir(), 'bob-shared-')));
  t.after(() => rmSync(path, {recursive:true, force:true}));
  return path;
}
function configuration(root, extra = {}) {
  return loadConfig({HOST:'127.0.0.1', PORT:'0', DATA_DIR:join(root, 'data'),
    BOB_WORKSPACE_DIR:join(root, 'repo'), AUTH_TOKENS:JSON.stringify({owner:token}),
    MAX_CONCURRENT:'1', BOB_ENABLE_CONTINUATION:'true', ...extra});
}
test('shared repository requires one owner and serialized runs', t => {
  const root = directory(t);
  for (const extra of [{MAX_CONCURRENT:'2'}, {AUTH_TOKENS:'{}'},
    {AUTH_TOKENS:JSON.stringify({owner:token, other:token+'-other'})}]) {
    assert.throws(() => configuration(root, extra), /Shared repository requires/);
  }
});
test('shared repository rejects symlinks and a changed session path', t => {
  const root = directory(t), repo = join(root, 'repo');
  mkdirSync(repo);
  const link = join(root, 'link');
  symlinkSync(repo, link);
  assert.throws(() => new Store(join(root, 'data'), link), /canonical/);
  const store = new Store(join(root, 'data'), repo);
  t.after(() => store.close());
  assert.equal(store.newWorkspace('one'), repo);
  assert.throws(() => store.checkWorkspace({workspace:root}), /validation/);
  rmSync(repo, {recursive:true});
  symlinkSync(root, repo);
  assert.throws(() => store.checkWorkspace({workspace:repo}), /validation/);
});
test('default upstream storage still creates separate session directories', t => {
  const root = directory(t), store = new Store(join(root, 'data'));
  t.after(() => store.close());
  assert.notEqual(store.newWorkspace('one'), store.newWorkspace('two'));
});
test('API edits the existing repository, serializes threads, and resumes after restart', async t => {
  const root = directory(t), config = configuration(root), repo = config.workspaceDir;
  mkdirSync(repo);
  writeFileSync(join(repo, 'existing.txt'), 'existing checkout');
  let active = 0, maximum = 0, resumed = false;
  const runtime = {
    async ready() { return {ready:true}; },
    async run(execution) {
      active++; maximum = Math.max(maximum, active);
      try {
        assert.equal(execution.workspace, repo);
        assert.equal(readFileSync(join(repo, 'existing.txt'), 'utf8'), 'existing checkout');
        resumed ||= execution.taskId === 'saved-task';
        writeFileSync(join(repo, 'edited.txt'), 'edit survived');
        await delay(30);
        execution.onText('completed');
        return {text:'completed', taskId:'saved-task'};
      } finally { active--; }
    }
  };
  let app = await createApp(config, runtime);
  await app.listen();
  t.after(() => app.close());
  async function api(path, body) {
    const address = app.server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/api/v1${path}`, {
      headers:{Authorization:`Bearer ${token}`, 'Content-Type':'application/json'},
      method:body === undefined ? 'GET' : 'POST',
      ...(body === undefined ? {} : {body:JSON.stringify(body)})
    });
    assert.ok(response.ok, `HTTP ${response.status} ${path}`);
    return response.json();
  }
  async function done(id) {
    for (let attempt = 0; attempt < 100; attempt++) {
      const run = await api(`/runs/${id}`);
      if (run.status === 'completed') return;
      assert.ok(!['failed','cancelled'].includes(run.status));
      await delay(20);
    }
    throw new Error('Fixture timed out');
  }
  const one = await api('/threads', {title:'One'}), two = await api('/threads', {title:'Two'});
  const first = await api(`/threads/${one.id}/messages`, {content:'edit existing repo'});
  const second = await api(`/threads/${two.id}/messages`, {content:'another edit'});
  await Promise.all([done(first.run.run_id), done(second.run.run_id)]);
  assert.equal(maximum, 1);
  assert.ok((await api(`/threads/${one.id}/files`)).items.some(file => file.name === 'edited.txt'));
  await app.close();
  app = await createApp(config, runtime);
  await app.listen();
  assert.equal((await api(`/threads/${one.id}/messages`)).items.length, 2);
  assert.equal(readFileSync(join(repo, 'edited.txt'), 'utf8'), 'edit survived');
  const followup = await api(`/threads/${one.id}/messages`, {content:'resume'});
  await done(followup.run.run_id);
  assert.equal(resumed, true);
});
