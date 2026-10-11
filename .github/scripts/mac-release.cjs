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

module.exports = async function allocate({ github, context, core }) {
  const options = { ...context.repo, per_page: 100 };
  const [tags, releases] = await Promise.all([
    github.paginate(github.rest.repos.listTags, options),
    github.paginate(github.rest.repos.listReleases, options),
  ]);
  const plan = planRelease(tags, releases, context.sha);
  for (const [key, value] of Object.entries(plan)) core.setOutput(key, String(value));
  core.info(`Mac app ${plan.tag}: ${plan.published ? 'already published' : plan.draft ? 'resume draft' : 'new release'}`);
  return plan;
};
module.exports.planRelease = planRelease;
