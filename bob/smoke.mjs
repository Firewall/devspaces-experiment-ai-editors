// Executed inside the workspace by test.sh. Credentials never leave the pod.
import assert from 'node:assert/strict';
import { readFileSync, statSync, existsSync, unlinkSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { setTimeout as delay } from 'node:timers/promises';

const phase = process.argv[2] ?? 'check';
const persist = '/projects/.devspaces-bob';
const token = readFileSync(`${persist}/ui-token`, 'utf8').trim();
for (let attempt = 0; ; attempt++) {
  try {
    const response = await fetch('http://127.0.0.1:8000/healthz', {signal:AbortSignal.timeout(2000)});
    if (response.ok) break;
  } catch {}
  if (attempt >= 29) throw new Error('Bob UI did not become healthy');
  await delay(1000);
}
async function api(path, body) {
  const response = await fetch(`http://127.0.0.1:8000${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {Authorization:`Bearer ${token}`, 'Content-Type':'application/json'},
    ...(body === undefined ? {} : {body:JSON.stringify(body)}),
    signal:AbortSignal.timeout(10000)
  });
  if (!response.ok) throw new Error(`Bob ${path}: HTTP ${response.status}`);
  return response.json();
}
async function message(thread, content) {
  const started = await api(`/api/v1/threads/${thread}/messages`, {content});
  const id = started.run_id ?? started.run?.run_id;
  assert.ok(id, 'Message response must include a run ID');
  for (let attempt = 0; attempt < 150; attempt++) {
    const run = await api(`/api/v1/runs/${id}`);
    if (run.status === 'completed') return run;
    assert.ok(!['failed','cancelled'].includes(run.status), `Bob run ${run.status}: ${JSON.stringify(run.error ?? {})}`);
    await delay(2000);
  }
  throw new Error('Bob smoke run did not complete within five minutes');
}

if (phase === 'check') {
  assert.equal((await fetch('http://127.0.0.1:8000/')).status, 200);
  assert.equal((await fetch('http://127.0.0.1:8000/healthz')).status, 200);
  assert.equal((await fetch('http://127.0.0.1:8000/api/v1/threads')).status, 401);
  await api('/api/v1/threads');
  const ready = await fetch('http://127.0.0.1:8000/readyz', {headers:{Authorization:`Bearer ${token}`}});
  const runtimeReady = ready.ok;
  await ready.arrayBuffer();
  assert.equal(statSync('/projects/repo').isDirectory(), true);
  for (const directory of [persist, `${persist}/home`, `${persist}/service`]) {
    assert.equal(statSync(directory).mode & 0o077, 0, `${directory} must be private`);
  }
  assert.equal(statSync(`${persist}/ui-token`).mode & 0o777, 0o600);
  const backend = process.env.AGENT_BACKEND ?? 'bob';
  const version = execFileSync(backend === 'opencode' ? '/injected-tools/bin/opencode' : 'bob', ['--version'], {
    encoding:'utf8', env:{...process.env, HOME:`${persist}/home`}, timeout:30000
  }).trim();
  if (backend === 'opencode') {
    assert.match(version, /^\d+\.\d+\.\d+/);
    assert.match(process.env.OPENCODE_MODEL, /^opencode\/.+-free$/);
    assert.equal(runtimeReady, true, 'OpenCode backend must be ready');
    console.log(`PASS: OpenCode ${version}, free model ${process.env.OPENCODE_MODEL}, UI authentication, repository, and private storage`);
  } else {
    assert.match(version, /^2\.0\.4(?:\s|$)/);
    console.log('PASS: UI, token authentication, Bob Shell 2.0.4, repository, and private storage');
  }
  if (backend !== 'opencode' && existsSync('/injected-tools/bin/opencode')) {
    const opencodeVersion = execFileSync('/injected-tools/bin/opencode', ['--version'], {
      encoding:'utf8', env:{...process.env, HOME:`${persist}/home`}, timeout:30000
    }).trim();
    console.log(`PASS: Dev Spaces OpenCode tool ${opencodeVersion}`);
  }
  console.log(runtimeReady ? 'Agent runtime reports ready. Use --live to verify inference and restart persistence.' : 'Bob runtime needs credentials. UI checks passed; live inference was not tested.');
} else if (phase === 'start') {
  await api('/readyz');
  const marker = `bob-poc-${randomUUID()}.txt`;
  const value = randomUUID();
  const thread = await api('/api/v1/threads', {title:'Dev Spaces persistence smoke test'});
  await message(thread.id, `Create the file ${marker} in the current repository containing exactly ${value}. Do not change any other file. Report completion.`);
  assert.equal(readFileSync(`/projects/repo/${marker}`, 'utf8').trim(), value);
  console.log(JSON.stringify({thread:thread.id, marker, value}));
} else if (phase === 'resume') {
  const state = JSON.parse(process.argv[3]);
  assert.match(state.marker, /^bob-poc-[0-9a-f-]+\.txt$/);
  assert.ok(existsSync(`${persist}/service/runs.sqlite`));
  assert.equal(readFileSync(`/projects/repo/${state.marker}`, 'utf8').trim(), state.value);
  await api(`/api/v1/threads/${state.thread}`);
  const result = await message(state.thread, `Read ${state.marker}. Reply with its exact contents. Do not modify any files.`);
  assert.ok(JSON.stringify(result).includes(state.value), 'Resumed Bob conversation must read the persisted marker');
  unlinkSync(`/projects/repo/${state.marker}`);
  console.log('PASS: live file edit, workspace restart, persisted file and history, and conversation continuation');
} else {
  throw new Error('Unknown smoke phase');
}
