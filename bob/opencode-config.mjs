import {pathToFileURL} from 'node:url';

export function createOpenCodeConfig(model = 'opencode/glm-5.3-flash-free') {
  if (!/^opencode\/[a-z0-9][a-z0-9.-]*-free$/.test(model)) {
    throw new Error('This OpenCode PoC requires an explicit opencode/*-free model');
  }
  return {
    model, small_model:model, enabled_providers:['opencode'],
    provider:{opencode:{whitelist:[model.slice('opencode/'.length)]}}
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(JSON.stringify(createOpenCodeConfig(process.env.OPENCODE_MODEL)));
}
