#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');

const root = path.resolve(__dirname, '..');
const englishPath = path.join(root, 'src/Core/Lang/VCLang_EN.mm');

function run(command) {
  return childProcess.execSync(command, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function localizedKeys() {
  const files = run('rg --files src VansonCLI.h')
    .trim()
    .split('\n')
    .filter(Boolean)
    .filter((file) => /\.(h|m|mm|cpp|hpp|xm)$/.test(file));

  const keys = new Set();
  for (const file of files) {
    const content = fs.readFileSync(path.join(root, file), 'utf8');
    for (const match of content.matchAll(/VCTextLiteral\(@"((?:[^"\\]|\\.)*)"\)/g)) {
      keys.add(match[1]);
    }
    for (const match of content.matchAll(/VCTextKey\(@"((?:[^"\\]|\\.)*)"\)/g)) {
      keys.add(match[1]);
    }
  }
  return [...keys].sort((a, b) => a.localeCompare(b));
}

function objcString(sourceLiteralBody) {
  return sourceLiteralBody.replace(/"/g, '\\"');
}

function englishDictionaryFile(keys) {
  const entries = keys.map((key) => `            @"${objcString(key)}": @"${objcString(key)}",`);
  return `/**
 * VCLang_EN -- EN localization dictionary.
 */

#import "VCLang.h"

NSDictionary<NSString *, NSString *> *VCLangENDictionary(void) {
    static NSDictionary<NSString *, NSString *> *dictionary = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dictionary = @{
${entries.join('\n')}
        };
    });
    return dictionary;
}

`;
}

const keys = localizedKeys();
fs.writeFileSync(englishPath, englishDictionaryFile(keys));

console.log(`Synced ${keys.length} English localization keys.`);
