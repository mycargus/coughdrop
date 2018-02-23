module.exports = {
  root: true,
  parserOptions: {
    ecmaVersion: 2017,
    sourceType: 'module'
  },
  plugins: [
    'ember'
  ],
  extends: [
    'eslint:recommended',
    'plugin:ember/recommended'
  ],
  env: {
    browser: true
  },
  rules: {
    'no-console': 'off',
    'no-unused-vars': 'off',
    'ember/no-function-prototype-extensions': 'off',
    'no-useless-escape': 'off',
    'no-empty': 'off',
    'no-redeclare': 'off',
    'no-debugger': 'off',
    'ember/closure-actions': 'off', // TODO: fix this
    'ember/avoid-leaking-state-in-ember-objects': 'off' // TODO: fix this
  },
  overrides: [
    // node files
    {
      files: [
        'testem.js',
        'ember-cli-build.js',
        'config/**/*.js',
        'lib/*/index.js'
      ],
      parserOptions: {
        sourceType: 'script',
        ecmaVersion: 2015
      },
      env: {
        browser: false,
        node: true
      }
    },

    // test files
    {
      files: ['tests/**/*.js'],
      excludedFiles: ['tests/dummy/**/*.js'],
      env: {
        embertest: true
      }
    }
  ]
};
