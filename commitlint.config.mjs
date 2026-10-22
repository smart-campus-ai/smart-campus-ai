// Commit message rules (AGENTS.md, "Git workflow"): Conventional Commits with a closed list of types and scopes.
//
// No `extends` on purpose: commitlint is installed globally by mise (npm:@commitlint/cli), and a global install
// cannot resolve shared configs such as @commitlint/config-conventional. Every rule is spelled out below.
// Keep `types` and `scopes` in sync with AGENTS.md and the PR title check in CI.

const types = [
  'feat',
  'fix',
  'docs',
  'style',
  'refactor',
  'perf',
  'test',
  'build',
  'ci',
  'chore',
  'revert',
];

const scopes = [
  'bootstrap',
  'edge',
  'identity',
  'api',
  'data',
  'ai',
  'notif',
  'sla',
  'obs',
  'sec',
  'ci',
  'cd',
  'qa',
  'docs',
  'deps',
  'app',
  'front',
  'contracts',
];

export default {
  // Without a preset the default parser would not accept the breaking-change marker (`feat(api)!: ...`).
  parserPreset: {
    parserOpts: {
      headerPattern: /^(\w*)(?:\((.*)\))?!?: (.*)$/,
      headerCorrespondence: ['type', 'scope', 'subject'],
    },
  },
  rules: {
    'type-enum': [2, 'always', types],
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'scope-enum': [2, 'always', scopes],
    'scope-case': [2, 'always', 'lower-case'],
    'subject-empty': [2, 'never'],
    'subject-full-stop': [2, 'never', '.'],
    'header-max-length': [2, 'always', 100],
    'body-leading-blank': [2, 'always'],
    'footer-leading-blank': [2, 'always'],
  },
};
