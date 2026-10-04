import assert from 'node:assert/strict';
import { test } from 'node:test';
import { resolveRollingRelease, shanghaiDate, githubApi } from '../.github/scripts/resolve-rolling-release.mjs';

const wheelRepository = 'DSYZayn/1Cat-vLLM';
const imageRepository = 'DSYZayn/1cat-vllm-v100-docker';
const today = '20261005';
function release(date = today, version = '1.5.1') {
  const tag = `v${version}-native-rolling-${date}`;
  const name = `1cat_vllm-${version}.post${date}-cp312-cp312-linux_x86_64.whl`;
  return {
    tag_name: tag, draft: false, prerelease: true,
    target_commitish: 'a'.repeat(40), updated_at: '2026-10-05T00:54:50Z',
    assets: [{ name, state: 'uploaded', size: 123,
      browser_download_url: `https://github.com/${wheelRepository}/releases/download/${tag}/${name}` }],
  };
}
function setup(releases, published = null, overrides = {}) {
  const calls = [];
  return {
    calls,
    options: {
      wheelRepository, imageRepository, eventName: 'schedule', today,
      api: async path => {
        calls.push(path);
        if (path.startsWith(`repos/${imageRepository}/`)) return published;
        if (path.includes('/releases/tags/')) return releases.find(r => path.endsWith(r.tag_name)) ?? null;
        return releases;
      },
      ...overrides,
    },
  };
}

test('uses the Beijing date at the UTC day boundary', () => {
  assert.equal(shanghaiDate(new Date('2026-10-04T15:59:59Z')), '20261004');
  assert.equal(shanghaiDate(new Date('2026-10-04T16:00:00Z')), today);
});
test('does not build anything before October 5', async () => {
  const { options, calls } = setup([release('20261004')], null, { today: '20261004' });
  assert.equal((await resolveRollingRelease(options)).should_build, 'false');
  assert.deepEqual(calls, []);
});
test('builds tomorrow\'s package without a dispatch event or token', async () => {
  const { options } = setup([release()]);
  const result = await resolveRollingRelease(options);
  assert.equal(result.should_build, 'true');
  assert.equal(result.image_tag, 'v1.5.1-20261005');
  assert.equal(result.wheel_version, '1.5.1.post20261005');
  assert.equal(result.source_sha, 'a'.repeat(40));
});
test('never backfills older dates or selects a future release', async () => {
  const { options } = setup([release('20261004'), release('20261006')]);
  assert.equal((await resolveRollingRelease(options)).should_build, 'false');
});
test('ignores a recently updated alias retaining an old wheel', async () => {
  const alias = { ...release('20260924'), tag_name: 'v1.5.1-native-rolling' };
  const { options } = setup([alias, release()]);
  assert.equal((await resolveRollingRelease(options)).release_tag, release().tag_name);
});
test('waits for an upload to finish instead of using an incomplete asset', async () => {
  for (const assetChange of [{ state: 'starter' }, { size: 0 }]) {
    const pending = release();
    Object.assign(pending.assets[0], assetChange);
    const { options } = setup([pending]);
    assert.equal((await resolveRollingRelease(options)).should_build, 'false');
  }
});
test('rejects a wheel whose version or date disagrees with the release', async () => {
  for (const name of [release('20261004').assets[0].name, release(today, '1.5.0').assets[0].name]) {
    const mismatched = release();
    mismatched.assets[0].name = name;
    assert.equal((await resolveRollingRelease(setup([mismatched]).options)).should_build, 'false');
  }
});
test('skips a completed image when schedule and dispatch both run', async () => {
  for (const eventName of ['schedule', 'repository_dispatch']) {
    const { options } = setup([release()], { draft: false }, {
      eventName, requestedTag: eventName === 'repository_dispatch' ? release().tag_name : '',
    });
    assert.equal((await resolveRollingRelease(options)).should_build, 'false');
  }
});
test('does not treat a draft image release as complete', async () => {
  assert.equal((await resolveRollingRelease(setup([release()], { draft: true }).options)).should_build, 'true');
});
test('ignores an old dispatch without even fetching its release', async () => {
  const { options, calls } = setup([], null, {
    eventName: 'repository_dispatch', requestedTag: release('20260924').tag_name,
  });
  assert.equal((await resolveRollingRelease(options)).should_build, 'false');
  assert.deepEqual(calls, []);
});
test('paginates instead of assuming the first 100 releases contain today', async () => {
  const { options } = setup([]);
  options.api = async path => {
    if (/[?&]page=1$/.test(path)) return Array.from({ length: 100 }, () => release('20260924'));
    if (/[?&]page=2$/.test(path)) return [release()];
    return null;
  };
  assert.equal((await resolveRollingRelease(options)).should_build, 'true');
});
test('handles a new stable version numerically', async () => {
  assert.equal((await resolveRollingRelease(setup([release(today, '1.9.0'), release(today, '1.10.0')]).options)).image_tag,
    'v1.10.0-20261005');
});
test('fails visibly on API authentication errors rather than reporting no update', async () => {
  const { options } = setup([]);
  options.api = async () => { throw new Error('GitHub API 401'); };
  await assert.rejects(resolveRollingRelease(options), /401/);
});
test('keeps explicit manual release selection and rejects invalid tags', async () => {
  const { options } = setup([release()], null, {
    eventName: 'workflow_dispatch', requestedTag: release().tag_name,
  });
  assert.equal((await resolveRollingRelease(options)).should_build, 'true');
  await assert.rejects(resolveRollingRelease({ ...options, requestedTag: '../invalid' }), /Invalid/);
});
test('HTTP adapter only treats 404 as absent; 401 and 500 are failures', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response('{}', { status: 404 }));
  assert.equal(await githubApi('repos/test/repo/releases/tags/missing'), null);
  for (const status of [401, 500]) {
    globalThis.fetch = async () => new Response('{}', { status });
    await assert.rejects(githubApi('repos/test/repo/releases'), new RegExp(String(status)));
  }
});
