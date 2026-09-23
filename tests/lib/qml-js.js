'use strict';

// Loads a QML JavaScript resource (".pragma library" plus ".import" lines)
// into a node vm context, so the tests exercise the exact files the shell
// loads.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

function load(file, cache = new Map()) {
  const absolute = path.resolve(file);
  if (cache.has(absolute)) return cache.get(absolute);

  const context = vm.createContext({});
  cache.set(absolute, context);

  const source = fs.readFileSync(absolute, 'utf8')
    .split('\n')
    .map((line) => {
      if (/^\s*\.pragma\s+library\s*;?\s*$/.test(line)) return '';
      const match = line.match(/^\s*\.import\s+"([^"]+)"\s+as\s+(\w+)\s*;?\s*$/);
      if (match) {
        context[match[2]] = load(path.join(path.dirname(absolute), match[1]), cache);
        return '';
      }
      if (/^\s*\./.test(line)) throw new Error(`unsupported QML JS directive in ${absolute}: ${line}`);
      return line;
    })
    .join('\n');

  vm.runInContext(source, context, { filename: absolute });
  return context;
}

module.exports = { load };
