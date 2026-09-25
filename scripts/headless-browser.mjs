import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

export function browserExecutable() {
  if (process.env.GALLERY_BROWSER_BIN) return process.env.GALLERY_BROWSER_BIN;
  if (process.platform === 'darwin') return '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  if (process.platform === 'win32') return 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
  return 'google-chrome';
}

export function browserProfile(root, name) {
  const directory = join(root, '.tools');
  mkdirSync(directory, { recursive: true });
  return join(directory, name);
}

export function testSource() {
  const source = process.env.GALLERY_SOURCE || (process.platform === 'win32' ? 'I:\\Photos\\Best of Poe 2' : '');
  if (!source) throw new Error('Set GALLERY_SOURCE to a local photo fixture folder before running this test.');
  return source;
}
