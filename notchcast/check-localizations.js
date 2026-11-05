#!/usr/bin/env node
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const script = path.resolve(__dirname, "../Scripts/check-localizations.js");
const source = fs.readFileSync(script, "utf8");
const catalogs = /const CATALOGS = \[[^;]+;/;
if (!catalogs.test(source)) throw new Error("Upstream localization checker changed its catalog declaration");
vm.runInNewContext(source.replace(catalogs,
  'const CATALOGS = ["Tinycast/Resources/Notchcast.xcstrings"];'),
{ require, __dirname: path.dirname(script), console, process }, { filename: script });
