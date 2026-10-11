'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const allocate = require('./mac-release.cjs');
const { planRelease, publicationPlan } = allocate;
const tag = (name, sha = 'old') => ({ name, commit: { sha } });
const release = (tag_name, draft, target_commitish = 'old') => ({ tag_name, draft, target_commitish });

test('first release is v1', () => {
  assert.deepEqual(planRelease([], [], 'new'), { version: '1', tag: 'v1', published: false, draft: false });
});
test('increments the numeric maximum and ignores unrelated tags', () => {
  assert.equal(planRelease([tag('v9'), tag('v10'), tag('v2.0'), tag('v01'), tag('firmware-200')], [], 'new').tag, 'v11');
});
test('drafts reserve numbers even before their tag exists', () => {
  assert.equal(planRelease([tag('v1')], [release('v5', true)], 'new').tag, 'v6');
});
test('a retry resumes its draft even when newer versions exist', () => {
  assert.deepEqual(planRelease([tag('v2', 'same'), tag('v3')], [release('v2', true, 'main')], 'same'), {
    version: '2', tag: 'v2', published: false, draft: true,
  });
});
test('a completed retry does not create or modify another release', () => {
  assert.equal(planRelease([tag('v2', 'same')], [release('v2', false, 'main')], 'same').published, true);
});
test('reuses a draft identified by full commit SHA before tag creation', () => {
  assert.equal(planRelease([], [release('v4', true, 'same')], 'same').tag, 'v4');
});
test('reuses a tag after failure before release creation', () => {
  assert.deepEqual(planRelease([tag('v4', 'same')], [], 'same'), {
    version: '4', tag: 'v4', published: false, draft: false,
  });
});
test('fails on unsafe version numbers rather than publishing duplicates', () => {
  assert.throws(() => planRelease([tag('v9007199254740992')], [], 'new'), /too large/);
  assert.throws(() => planRelease([tag('v9007199254740991')], [], 'new'), /overflow/);
});
test('allocator paginates both endpoints and writes workflow outputs', async () => {
  const calls = [], outputs = {};
  const github = {
    rest: { repos: { listTags: 'tags', listReleases: 'releases' } },
    paginate: async (endpoint, options) => {
      calls.push([endpoint, options]);
      return endpoint === 'tags' ? Array.from({ length: 105 }, (_, i) => tag(`v${i + 1}`)) : [];
    },
  };
  await allocate({ github, context: { repo: { owner: 'owner', repo: 'repo' }, sha: 'new' },
    core: { setOutput: (key, value) => { outputs[key] = value; }, info: () => {} } });
  assert.deepEqual(outputs, { version: '106', tag: 'v106', published: 'false', draft: 'false' });
  assert.deepEqual(calls, ['tags', 'releases'].map(endpoint => [endpoint, { owner: 'owner', repo: 'repo', per_page: 100 }]));
});

test('main allocation reserves a draft against the exact commit before building', async () => {
  const created = [], outputs = {};
  const github = {
    rest: { repos: { listTags: 'tags', listReleases: 'releases', createRelease: async options => { created.push(options); } } },
    paginate: async () => [],
  };
  await allocate({ github, context: { repo: { owner: 'owner', repo: 'repo' }, sha: 'main-sha' }, reserve: true,
    core: { setOutput: (key, value) => { outputs[key] = value; }, info: () => {} } });
  assert.deepEqual(created, [{ owner: 'owner', repo: 'repo', tag_name: 'v1', target_commitish: 'main-sha', name: 'ErgoDash USB Monitor 1', draft: true }]);
  assert.equal(outputs.draft, 'true');
});
test('allocation retries reuse their reserved draft or published release', async () => {
  for (const draft of [true, false]) {
    const github = {
      rest: { repos: { listTags: 'tags', listReleases: 'releases', createRelease: async () => assert.fail('must not create another release') } },
      paginate: async endpoint => endpoint === 'tags' ? [] : [release('v1', draft, 'main-sha')],
    };
    await allocate({ github, context: { repo: { owner: 'owner', repo: 'repo' }, sha: 'main-sha' }, reserve: true,
      core: { setOutput: () => {}, info: () => {} } });
  }
});
test('publication observes a draft or completed upload created by a previous attempt', () => {
  for (const draft of [true, false]) {
    assert.equal(publicationPlan([tag('v1', 'same')], [release('v1', draft, 'main')], 'same', 'v1').state, draft ? 'draft' : 'published');
  }
});
test('recovering an older draft preserves Latest on a newer published release', () => {
  assert.deepEqual(publicationPlan([], [release('v2', true, 'same'), release('v3', false)], 'same', 'v2'), { state: 'draft', makeLatest: false });
  assert.equal(publicationPlan([], [release('v2', true, 'same'), release('v3', true)], 'same', 'v2').makeLatest, true);
});
test('publication refuses a version consumed by a different commit or a missing reservation', () => {
  assert.throws(() => publicationPlan([tag('v1', 'other')], [release('v1', true, 'same')], 'same', 'v1'), /different commit/);
  assert.throws(() => publicationPlan([], [], 'same', 'v1'), /missing/);
});
test('publication can recreate a removed draft when the reserved tag still belongs to this commit', () => {
  assert.deepEqual(publicationPlan([tag('v1', 'same')], [], 'same', 'v1'), { state: 'new', makeLatest: true });
});
test('publication check re-queries both endpoints on every job retry', async () => {
  const outputs = {};
  const github = { rest: { repos: { listTags: 'tags', listReleases: 'releases' } },
    paginate: async endpoint => endpoint === 'tags' ? [] : [release('v1', false, 'same')] };
  await allocate.checkPublication({ github, context: { repo: { owner: 'owner', repo: 'repo' }, sha: 'same' }, expectedTag: 'v1',
    core: { setOutput: (key, value) => { outputs[key] = value; }, info: () => {} } });
  assert.deepEqual(outputs, { state: 'published', makeLatest: 'true' });
});
