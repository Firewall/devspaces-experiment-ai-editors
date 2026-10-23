import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';

for (const file of ['index.html','app.js','docs.html','acp.html']) {
  const path = join(process.argv[2], file);
  const source = readFileSync(path, 'utf8');
  writeFileSync(path, source.replaceAll('HeadlessBob','OpenCode Console')
    .replace(/\bBob\b/g, 'OpenCode').replaceAll('Powered by OpenCode Shell', 'Powered by OpenCode'));
}
