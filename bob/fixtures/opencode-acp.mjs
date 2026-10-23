#!/usr/bin/env node
import {createInterface} from 'node:readline';
import {writeFileSync,existsSync} from 'node:fs';
if (process.env.ANTHROPIC_API_KEY || process.env.BOB_API_KEY || process.env.AUTH_TOKENS) process.exit(77);
if (process.argv.includes('--version')) { console.log('1.18.14'); process.exit(0); }
if (!process.argv.includes('acp') || !process.argv.includes('--pure') || process.argv.includes('--trust')) process.exit(78);
const send = message => process.stdout.write(JSON.stringify({jsonrpc:'2.0',...message})+'\n');
let resumed=false, promptId;
const methods=[];
function finish(text) {
  send({method:'session/update',params:{sessionId:'opencode-fixture',update:{sessionUpdate:'agent_message_chunk',content:{type:'text',text}}}});
  send({id:promptId,result:{stopReason:'end_turn'}});
}
createInterface({input:process.stdin}).on('line', line => {
  const message=JSON.parse(line);
  if (message.method) methods.push(message.method);
  if (message.method==='initialize') send({id:message.id,result:{protocolVersion:1,agentCapabilities:{loadSession:true,sessionCapabilities:{close:{}}}}});
  else if (message.method==='session/new') {
    writeFileSync('opencode-task.txt','saved');
    send({id:message.id,result:{sessionId:'opencode-fixture',modes:{currentModeId:'build'}}});
  } else if (message.method==='session/load') {
    if (!existsSync('opencode-task.txt')) process.exit(79);
    resumed=true; send({id:message.id,result:{modes:{currentModeId:'build'}}});
  } else if (message.method==='session/prompt') {
    promptId=message.id;
    if (message.params.prompt[0].text==='permission') {
      send({id:99,method:'session/request_permission',params:{sessionId:'opencode-fixture',options:[{kind:'allow_once',optionId:'once'}]}});
    } else finish(resumed?'continued':'hello');
  } else if (message.id===99) {
    writeFileSync('opencode-permission.json',JSON.stringify(message.result));finish('permitted');
  } else if (message.method==='session/close') {
    writeFileSync('opencode-methods.json',JSON.stringify(methods));send({id:message.id,result:{}});
  }
});
