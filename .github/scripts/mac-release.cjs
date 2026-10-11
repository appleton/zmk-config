'use strict';

function majorVersion(tag) {
  if (!/^v[1-9][0-9]*$/.test(tag)) return null;
  const version = Number(tag.slice(1));
  if (!Number.isSafeInteger(version)) throw new Error(`Release version is too large: ${tag}`);
  return version;
}

// Only integer tags belong to the Mac app. Both tags and draft releases reserve
// numbers. Reuse this commit's number after an interrupted or completed run.
function planRelease(tags, releases, sha) {
  const versions = new Map();
  for (const tag of tags) {
    const version = majorVersion(tag.name);
    if (version !== null) versions.set(version, { sha: tag.commit.sha });
  }
  for (const release of releases) {
    const version = majorVersion(release.tag_name);
    if (version !== null) {
      const existing = versions.get(version);
      versions.set(version, {
        sha: existing?.sha || release.target_commitish,
        release,
      });
    }
  }
  const matching = [...versions].filter(([, entry]) => entry.sha === sha);
  const previous = matching.sort(([a], [b]) => b - a)[0];
  const version = previous ? previous[0] : Math.max(0, ...versions.keys()) + 1;
  if (!Number.isSafeInteger(version)) throw new Error('Release version overflow');
  return {
    version: String(version),
    tag: `v${version}`,
    published: !!previous?.[1].release && !previous[1].release.draft,
    draft: !!previous?.[1].release?.draft,
  };
}

async function inventory(github, context) {
  const options = { ...context.repo, per_page: 100 };
  return Promise.all([
    github.paginate(github.rest.repos.listTags, options),
    github.paginate(github.rest.repos.listReleases, options),
  ]);
}

module.exports = async function allocate({ github, context, core, reserve = false }) {
  const [tags, releases] = await inventory(github, context);
  const plan = planRelease(tags, releases, context.sha);
  // Reserve before building: a failed build/publish must not let a later commit
  // consume this version. This option is only used by the main-only write job.
  if (reserve && !plan.published && !plan.draft) {
    await github.rest.repos.createRelease({
      ...context.repo, tag_name: plan.tag, target_commitish: context.sha,
      name: `ErgoDash USB Monitor ${plan.version}`, draft: true,
    });
    plan.draft = true;
  }
  for (const [key, value] of Object.entries(plan)) core.setOutput(key, String(value));
  core.info(`Mac app ${plan.tag}: ${plan.published ? 'already published' : plan.draft ? 'resume draft' : 'new release'}`);
  return plan;
};
module.exports.planRelease = planRelease;

function publicationPlan(tags, releases, sha, expectedTag) {
  const version = majorVersion(expectedTag);
  if (version === null) throw new Error(`Invalid expected release tag: ${expectedTag}`);
  const tag = tags.find(tag => tag.name === expectedTag);
  const release = releases.find(release => release.tag_name === expectedTag);
  const target = tag?.commit.sha || release?.target_commitish;
  if (!target) throw new Error(`Reserved release ${expectedTag} is missing`);
  if (target !== sha) throw new Error(`Release ${expectedTag} belongs to a different commit`);
  return {
    state: release ? (release.draft ? 'draft' : 'published') : 'new',
    makeLatest: !releases.some(release => !release.draft && majorVersion(release.tag_name) > version),
  };
}

module.exports.publicationPlan = publicationPlan;
module.exports.checkPublication = async function ({ github, context, core, expectedTag }) {
  const [tags, releases] = await inventory(github, context);
  const plan = publicationPlan(tags, releases, context.sha, expectedTag);
  for (const [key, value] of Object.entries(plan)) core.setOutput(key, String(value));
  core.info(`${expectedTag}: ${plan.state}, latest=${plan.makeLatest}`);
};
