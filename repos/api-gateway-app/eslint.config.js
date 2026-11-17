// ESLint flat configuration of npm run lint (job lint), on every .js file,
// sources and tests: the recommended rules report coding issues (unused
// variables, unreachable code, a lost error cause...), and sonarjs a cognitive
// complexity above 15 in a function (Sonar S3776). Every file is an ES module
// run by Node.js, hence its globals; the tests import node:test explicitly, so
// they need no test-framework globals. node_modules is ignored by default.
import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import sonarjs from 'eslint-plugin-sonarjs';
import globals from 'globals';

export default defineConfig([
  js.configs.recommended,
  {
    languageOptions: {
      globals: globals.node,
    },
    plugins: { sonarjs },
    rules: {
      'sonarjs/cognitive-complexity': ['error', 15],
    },
  },
]);
