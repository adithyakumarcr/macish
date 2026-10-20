// Tests for search.js. Run: gjs -m extensions/spotlight/test-search.js
import * as S from './search.js';

let failed = 0;
function eq(actual, expected, what) {
    const a = JSON.stringify(actual), e = JSON.stringify(expected);
    if (a !== e) {
        failed++;
        print(`FAIL ${what}\n     got      ${a}\n     expected ${e}`);
    }
}

// web addresses
for (const t of ['github.com', 'github.com/adithyakumarcr/macish', 'https://x.org', 'localhost:8080',
    'localhost', '192.168.1.10:3000/a', 'docs.python.org/3/', 'en.wikipedia.org/wiki/Mac?x=1', 'HTTP://A.B'])
    eq(S.looksLikeUrl(t), true, `url: ${t}`);
for (const t of ['terminal', 'how to install docker', 'file.txt2', 'v1.2', 'a.b c', '~/Downloads', '/usr/bin',
    '', 'e.g', 'foo.-bar.com'])
    eq(S.looksLikeUrl(t), false, `not url: ${t}`);
const realTld = l => ['com', 'io', 'org'].includes(l);
eq(S.looksLikeUrl('node.js', realTld), false, 'node.js is a search when .js is not a domain ending');
eq(S.looksLikeUrl('foo.io', realTld), true, 'foo.io with a real ending');
eq(S.toUrl('github.com'), 'https://github.com', 'toUrl adds https');
eq(S.toUrl('localhost:8080/x'), 'http://localhost:8080/x', 'toUrl local http');
eq(S.toUrl('http://a.com'), 'http://a.com', 'toUrl keeps scheme');
eq(S.prettyUrl('https://github.com/'), 'github.com', 'prettyUrl');
eq(S.googleUrl(' docker & ubuntu '), 'https://www.google.com/search?q=docker%20%26%20ubuntu', 'googleUrl');

// paths
const H = '/home/me';
eq(S.isPathQuery('~/x'), true, 'path ~');
eq(S.isPathQuery('/usr'), true, 'path /');
eq(S.isPathQuery('term'), false, 'not path');
eq(S.splitPath('~/Play', H), {dir: H, partial: 'Play', shownDir: '~'}, 'split ~/Play');
eq(S.splitPath('~', H), {dir: H, partial: '', shownDir: '~'}, 'split ~');
eq(S.splitPath('~/Playground/', H), {dir: `${H}/Playground`, partial: '', shownDir: '~/Playground'}, 'split dir/');
eq(S.splitPath('/us', H), {dir: '/', partial: 'us', shownDir: '/'}, 'split /us');
eq(S.splitPath('/usr/lo', H), {dir: '/usr', partial: 'lo', shownDir: '/usr'}, 'split /usr/lo');
eq(S.splitPath('~bob/x', H), null, 'split ~bob');
eq(S.tildify('/home/me/a', H), '~/a', 'tildify');
eq(S.tildify('/home/meow', H), '/home/meow', 'tildify needs a slash');

// matching
const order = ['Terminal', 'Terminator', 'Gnome Terminal', 'xterm', 'Text Editor'].map(n => [n, S.matchScore(n, 'term')]);
eq(order.map(([, s]) => s > 0), [true, true, true, true, false], 'term matches');
eq(order[0][1] > order[2][1] && order[2][1] > order[3][1], true, 'prefix > word > inside');
eq(S.matchScore('visual studio code', 'vsc') > 0, true, 'letters in order');
eq(S.matchScore('Settings', 'z'), 0, 'no match');
eq(S.matchScore('manageGithubRepos', 'github'), 80, 'camelCase word start');
eq(S.bestScore(['Google Chrome', 'Web Browser'], 'chrome') > S.bestScore(['Firefox', 'Web Browser'], 'browser'), true, 'name beats other fields');

// ghost text
eq(S.ghostFor('term', 'Terminal'), 'inal', 'ghost rest');
eq(S.ghostFor('chrome', 'Google Chrome'), ' — Google Chrome', 'ghost name');
eq(S.ghostFor('', 'X'), '', 'ghost empty');

// history
let h = [];
h = S.addToHistory(h, {kind: 'app', id: 'a.desktop', title: 'A'}, 1);
h = S.addToHistory(h, {kind: 'url', id: 'https://x.org', title: 'x.org'}, 2);
h = S.addToHistory(h, {kind: 'app', id: 'a.desktop', title: 'A'}, 3);
eq(h.map(i => [i.id, i.count, i.time]), [['a.desktop', 2, 3], ['https://x.org', 1, 2]], 'history dedupes, counts, orders');
eq(S.removeFromHistory(h, {kind: 'app', id: 'a.desktop'}).length, 1, 'history remove');
for (let i = 0; i < 60; i++)
    h = S.addToHistory(h, {kind: 'search', id: `q${i}`}, 10 + i);
eq(h.length, S.MAX_HISTORY, 'history capped');
eq(S.usageBoost(null), 0, 'no boost');
eq(S.usageBoost({count: 100, time: 0}, 0), 15, 'boost capped');

print(failed ? `${failed} failed` : 'all passed');
if (failed)
    imports.system.exit(1);
