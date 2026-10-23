import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,readFileSync,chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';

const root=resolve(process.env.HEADLESSBOB_DIR??'/app');
const {loadConfig}=await import(pathToFileURL(join(root,'dist/config.js')));
const {BobClientRuntime}=await import(pathToFileURL(join(root,'dist/runtime/client.js')));
const binary=fileURLToPath(new URL('./fixtures/opencode-acp.mjs',import.meta.url));
chmodSync(binary,0o755);
function setup(t) {
  const workspace=mkdtempSync(join(tmpdir(),'opencode-backend-'));
  t.after(()=>rmSync(workspace,{recursive:true,force:true}));
  const config=loadConfig({AGENT_BACKEND:'opencode',BOB_BIN:binary,PATH:process.env.PATH,
    HOME:workspace,ANTHROPIC_API_KEY:'fixture-paid-credential',BOB_API_KEY:'fixture-bob-credential',
    AUTH_TOKENS:JSON.stringify({owner:'fixture-ui-token-that-must-stay-private'}),KILL_GRACE_MS:'10',RUN_TIMEOUT_MS:'3000'});
  const runtime=new BobClientRuntime(config);
  const run=(prompt,taskId)=>runtime.run({workspace,mode:config.bobMode,prompt,taskId,
    signal:new AbortController().signal,onText(){}});
  return {workspace,config,runtime,run};
}
test('OpenCode works without API keys and never inherits paid-provider or UI credentials',async t=>{
  const {config,runtime,run}=setup(t);
  assert.equal(config.bobMode,'build');
  for (const key of ['ANTHROPIC_API_KEY','BOB_API_KEY','AUTH_TOKENS']) assert.equal(config.bobEnv[key],undefined);
  assert.equal((await runtime.ready()).ready,true);
  assert.deepEqual(await run('hello'),{text:'hello',taskId:'opencode-fixture'});
});
test('OpenCode resumes through session/load when session/resume is not advertised',async t=>{
  const {workspace,run}=setup(t);
  const first=await run('hello');
  assert.equal((await run('again',first.taskId)).text,'continued');
  const methods=JSON.parse(readFileSync(join(workspace,'opencode-methods.json'),'utf8'));
  assert.ok(methods.includes('session/load'));
  assert.ok(!methods.includes('session/resume'));
});
test('OpenCode tool approval remains scoped to the current invocation',async t=>{
  const {workspace,run}=setup(t);
  assert.equal((await run('permission')).text,'permitted');
  assert.deepEqual(JSON.parse(readFileSync(join(workspace,'opencode-permission.json'),'utf8')),
    {outcome:{outcome:'selected',optionId:'once'}});
});
