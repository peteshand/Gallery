import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const { version } = JSON.parse(readFileSync('package.json', 'utf8'));
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Gallery version must use major.minor.patch');
mkdirSync('haxe/generated/gallery', { recursive: true });
writeFileSync('haxe/generated/gallery/BuildInfo.hx', `package gallery;\n\nclass BuildInfo {\n  public static inline var VERSION:String = ${JSON.stringify(version)};\n}\n`);
