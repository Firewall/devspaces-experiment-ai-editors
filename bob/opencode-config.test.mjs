import test from 'node:test';
import assert from 'node:assert/strict';
import {createOpenCodeConfig} from './opencode-config.mjs';

test('main and background requests use the same free model and provider allowlist', () => {
  const config = createOpenCodeConfig();
  assert.equal(config.model, 'opencode/glm-5.3-flash-free');
  assert.equal(config.small_model, config.model);
  assert.deepEqual(config.enabled_providers, ['opencode']);
  assert.deepEqual(config.provider.opencode.whitelist, ['glm-5.3-flash-free']);
});
test('rejects paid models and other providers', () => {
  for (const model of ['anthropic/claude-sonnet-4-6', 'opencode/claude-sonnet-4-6', 'opencode/glm-5.3-flash', 'free']) {
    assert.throws(() => createOpenCodeConfig(model), /requires an explicit/);
  }
});
test('allows selecting another explicit free OpenCode model', () => {
  const config = createOpenCodeConfig('opencode/deepseek-v4.1-flash-free');
  assert.equal(config.small_model, 'opencode/deepseek-v4.1-flash-free');
  assert.deepEqual(config.provider.opencode.whitelist, ['deepseek-v4.1-flash-free']);
});
