import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const releasePattern = /^v(\d+\.\d+\.\d+)-(?:native-rolling|rolling)(?:-(\d{8}))?$/;
const wheelPattern = /^1cat_vllm-(\d+\.\d+\.\d+)\.post(\d{8})-cp312-cp312-linux_x86_64\.whl$/;

export function shanghaiDate(now = new Date()) {
  return new Date(now.getTime() + 8 * 60 * 60 * 1000)
    .toISOString().slice(0, 10).replaceAll('-', '');
}

function metadata(release, wheelRepository) {
  const tag = releasePattern.exec(release.tag_name);
  if (!tag || release.draft || !release.prerelease) return null;
  const wheels = (release.assets ?? []).flatMap(asset => {
    const match = wheelPattern.exec(asset.name);
    if (!match || match[1] !== tag[1] || (tag[2] && match[2] !== tag[2]) ||
        asset.state !== 'uploaded' || asset.size <= 0 ||
        !asset.browser_download_url?.startsWith(
          `https://github.com/${wheelRepository}/releases/download/`)) return [];
    return [{ asset, version: match[1], date: match[2] }];
  }).sort((a, b) => b.date.localeCompare(a.date));
  if (!wheels.length) return null;
  const { asset, version, date } = wheels[0];
  return {
    release_tag: release.tag_name,
    image_tag: `v${version}-${date}`,
    wheel_url: asset.browser_download_url,
    wheel_version: `${version}.post${date}`,
    source_sha: /^[a-f0-9]{40}$/.test(release.target_commitish ?? '')
      ? release.target_commitish : '',
    updated_at: release.updated_at ?? release.published_at,
  };
}

export async function resolveRollingRelease({
  api, wheelRepository, imageRepository, eventName,
  requestedTag = '', today = shanghaiDate(), startDate = '20261005',
}) {
  const skip = reason => ({ should_build: 'false', reason });
  const automatic = eventName !== 'workflow_dispatch';
  if (automatic && today < startDate) {
    return skip(`Automatic rolling builds start on ${startDate}; no backfill.`);
  }

  let releases;
  if (requestedTag) {
    const match = releasePattern.exec(requestedTag);
    if (!match) throw new Error(`Invalid rolling release tag: ${requestedTag}`);
    if (automatic && match[2] !== today) {
      return skip('Automatic runs only accept today\'s dated wheel release.');
    }
    const release = await api(`repos/${wheelRepository}/releases/tags/${requestedTag}`);
    if (!release) throw new Error(`Release not found: ${requestedTag}`);
    releases = [release];
  } else {
    releases = [];
    for (let page = 1; ; page++) {
      const batch = await api(`repos/${wheelRepository}/releases?per_page=100&page=${page}`);
      if (!Array.isArray(batch)) throw new Error('Could not list wheel releases.');
      releases.push(...batch);
      if (batch.length < 100) break;
    }
  }

  // Ignore aliases for discovery: they retain older wheel assets and have mutable
  // timestamps. Automatic runs never select yesterday's package or a future date.
  const candidates = releases.filter(release => {
    const date = releasePattern.exec(release.tag_name)?.[2];
    return automatic ? date === today : requestedTag || date;
  }).map(release => metadata(release, wheelRepository)).filter(Boolean)
    .sort((a, b) => b.image_tag.localeCompare(a.image_tag, 'en', { numeric: true }));
  const selected = candidates[0];
  if (!selected) {
    if (eventName === 'workflow_dispatch') {
      throw new Error('No complete compatible rolling wheel was found.');
    }
    return skip(`No uploaded wheel for ${today} yet; the next scheduled run will check again.`);
  }

  // This completion marker is created only after the image has been pushed.
  // Workflow concurrency serializes the hook and schedule, including this check.
  const published = await api(
    `repos/${imageRepository}/releases/tags/rolling-${selected.image_tag}`);
  if (published && !published.draft) {
    return { ...selected, ...skip(`Image ${selected.image_tag} is already published.`) };
  }
  return { ...selected, should_build: 'true', reason: `Build ${selected.image_tag}.` };
}

export async function githubApi(path) {
  const response = await fetch(`https://api.github.com/${path}`, {
    headers: {
      Authorization: `Bearer ${process.env.GH_TOKEN}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
    signal: AbortSignal.timeout(30000),
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`GitHub API ${response.status}: ${path}`);
  return response.json();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await resolveRollingRelease({
    api: githubApi,
    wheelRepository: process.env.ROLLING_WHEEL_REPOSITORY,
    imageRepository: process.env.GITHUB_REPOSITORY,
    eventName: process.env.GITHUB_EVENT_NAME,
    requestedTag: process.env.EVENT_RELEASE_TAG || process.env.INPUT_RELEASE_TAG || '',
    startDate: process.env.ROLLING_AUTO_START_DATE,
  });
  for (const [key, value] of Object.entries(result)) {
    if (/[\r\n]/.test(String(value))) throw new Error(`Invalid output: ${key}`);
    appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
  }
  console.log(result.reason);
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${result.reason}\n`);
}
