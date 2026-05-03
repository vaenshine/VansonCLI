#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');

const root = path.resolve(__dirname, '..');
const languageDir = path.join(root, 'src/Core/Lang');
const sourceRoots = ['src', 'VansonCLI.h'];

function run(command) {
  return childProcess.execSync(command, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function read(file) {
  return fs.readFileSync(path.join(root, file), 'utf8');
}

function sourceFiles() {
  return run(`rg --files ${sourceRoots.map((item) => JSON.stringify(item)).join(' ')}`)
    .trim()
    .split('\n')
    .filter(Boolean)
    .filter((file) => /\.(h|m|mm|cpp|hpp|xm)$/.test(file));
}

function literalKeys(files) {
  const keys = new Set();
  const patterns = [
    /VCTextLiteral\(@"((?:[^"\\]|\\.)*)"\)/g,
    /VCTextKey\(@"((?:[^"\\]|\\.)*)"\)/g,
  ];
  for (const file of files) {
    const content = read(file);
    for (const pattern of patterns) {
      for (const match of content.matchAll(pattern)) {
        keys.add(match[1]);
      }
    }
  }
  return keys;
}

function languageDictionaries() {
  const names = new Map([
    ['VCLang_EN.mm', 'en'],
    ['VCLang_ZH.mm', 'zh'],
    ['VCLang_ZH_HANT.mm', 'zhHant'],
    ['VCLang_JA.mm', 'ja'],
    ['VCLang_KO.mm', 'ko'],
    ['VCLang_RU.mm', 'ru'],
    ['VCLang_ES.mm', 'es'],
    ['VCLang_VI.mm', 'vi'],
    ['VCLang_TH.mm', 'th'],
    ['VCLang_PT.mm', 'pt'],
    ['VCLang_FR.mm', 'fr'],
    ['VCLang_DE.mm', 'de'],
    ['VCLang_AR.mm', 'ar'],
  ]);
  const dictionaries = new Map();
  for (const [fileName, languageName] of names.entries()) {
    const content = fs.readFileSync(path.join(languageDir, fileName), 'utf8');
    const keys = new Set();
    for (const key of content.matchAll(/@"((?:[^"\\]|\\.)*)"\s*:/g)) {
      keys.add(key[1]);
    }
    dictionaries.set(languageName, keys);
  }
  return dictionaries;
}

function languageValues() {
  const names = [
    ['VCLang_EN.mm', 'en'],
    ['VCLang_ZH.mm', 'zh'],
    ['VCLang_ZH_HANT.mm', 'zhHant'],
    ['VCLang_JA.mm', 'ja'],
    ['VCLang_KO.mm', 'ko'],
    ['VCLang_RU.mm', 'ru'],
    ['VCLang_ES.mm', 'es'],
    ['VCLang_VI.mm', 'vi'],
    ['VCLang_TH.mm', 'th'],
    ['VCLang_PT.mm', 'pt'],
    ['VCLang_FR.mm', 'fr'],
    ['VCLang_DE.mm', 'de'],
    ['VCLang_AR.mm', 'ar'],
  ];
  const dictionaries = new Map();
  for (const [fileName, languageName] of names) {
    const content = fs.readFileSync(path.join(languageDir, fileName), 'utf8');
    const values = new Map();
    for (const match of content.matchAll(/@"((?:[^"\\]|\\.)*)"\s*:\s*@"((?:[^"\\]|\\.)*)"/g)) {
      values.set(match[1], match[2]);
    }
    dictionaries.set(languageName, values);
  }
  return dictionaries;
}

function placeholders(value) {
  return (value.match(/%[0-9.]*[a-zA-Z%@]+/g) || []).sort().join('|');
}

function rawUserFacingStrings(files) {
  const hits = [];
  const rawPattern = /\b(?:text|placeholder)\s*=\s*@"([^"]{2,})"|\bsetTitle:@"([^"]{2,})"|title:@"([^"]{2,})"|subtitle:@"([^"]{2,})"/g;
  const allowed = /^(VC|VansonCLI|\$|filename\.mm|v%@|P50|P95|%@|%lu|modify_value|write_memory_bytes|Sig|Refs|UIViewController|viewDidAppear:|OtherClass otherSelector: \(only for swizzle\)|AuthManager\._token|0x1234 or decimal|https:\/\/api\.example\.com\/path\*|Base URL \(e\.g\. https:\/\/api\.openai\.com\)|[A-Z0-9_./:+# %@-]+)$/;
  for (const file of files.filter((item) => item.startsWith('src/UI/'))) {
    const lines = read(file).split('\n');
    lines.forEach((line, index) => {
      if (line.includes('VCTextLiteral(') || line.includes('VCText(')) return;
      for (const match of line.matchAll(rawPattern)) {
        const value = match[1] || match[2] || match[3] || match[4] || '';
        if (!value || allowed.test(value)) return;
        hits.push(`${file}:${index + 1}: ${value}`);
      }
    });
  }
  return hits;
}

const files = sourceFiles();
const keys = literalKeys(files);
const dictionaries = languageDictionaries();

let failed = false;
console.log(`Localized literal keys: ${keys.size}`);
const enKeys = dictionaries.get('en') || new Set();
const missingEnglish = [...keys].filter((key) => !enKeys.has(key));
console.log(`en: ${enKeys.size} keys, missing ${missingEnglish.length}`);
if (missingEnglish.length > 0) {
  failed = true;
  console.log(missingEnglish.slice(0, 80).map((key) => `  - ${key}`).join('\n'));
  if (missingEnglish.length > 80) console.log(`  ... ${missingEnglish.length - 80} more`);
}
for (const [name, dictKeys] of dictionaries.entries()) {
  if (name === 'en') continue;
  const missing = [...keys].filter((key) => !dictKeys.has(key));
  const pct = keys.size > 0 ? Math.round(((keys.size - missing.length) / keys.size) * 100) : 100;
  console.log(`${name}: ${dictKeys.size} overrides, coverage ${pct}%, English fallback ${missing.length}`);
}

const rawHits = rawUserFacingStrings(files);
console.log(`Raw UI string candidates: ${rawHits.length}`);
if (rawHits.length > 0) {
  failed = true;
  console.log(rawHits.slice(0, 80).join('\n'));
  if (rawHits.length > 80) console.log(`... ${rawHits.length - 80} more`);
}

const valueDictionaries = languageValues();
const englishValues = valueDictionaries.get('en') || new Map();
const placeholderHits = [];
for (const [name, values] of valueDictionaries.entries()) {
  if (name === 'en') continue;
  for (const [key, englishValue] of englishValues.entries()) {
    const value = values.get(key);
    if (value && placeholders(value) !== placeholders(englishValue)) {
      placeholderHits.push(`${name}: ${key}`);
    }
  }
}
console.log(`Placeholder mismatches: ${placeholderHits.length}`);
if (placeholderHits.length > 0) {
  failed = true;
  console.log(placeholderHits.slice(0, 80).join('\n'));
  if (placeholderHits.length > 80) console.log(`... ${placeholderHits.length - 80} more`);
}

process.exit(failed ? 1 : 0);
