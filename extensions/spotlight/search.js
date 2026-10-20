// Spotlight: the parts of searching that don't touch GNOME Shell, so they can be
// tested on their own with `gjs -m extensions/spotlight/test-search.js`.

export const MAX_HISTORY = 50;

const TLD = /^[a-z]{2,24}$/i;
const IPV4 = /^\d{1,3}(\.\d{1,3}){3}$/;

/**
 * Does the text look like a web address the user wants to open?
 * `isTld(label)` says whether the last part (com, org, io...) is a real domain ending.
 */
export function looksLikeUrl(text, isTld = l => TLD.test(l)) {
    const t = text.trim();
    if (!t || /\s/.test(t))
        return false;
    if (/^(https?|ftp|file):\/\//i.test(t))
        return true;
    const m = /^([^/:?#]+)(:\d{1,5})?([/?#].*)?$/.exec(t);
    if (!m)
        return false;
    const host = m[1].toLowerCase();
    if (host === 'localhost' || IPV4.test(host))
        return true;
    const labels = host.split('.');
    if (labels.length < 2 || labels.some(l => !/^[a-z0-9-]+$/.test(l) || l.startsWith('-')))
        return false;
    const last = labels[labels.length - 1];
    return TLD.test(last) && isTld(last);
}

/** Adds a scheme when it's missing: https for sites, http for this computer. */
export function toUrl(text) {
    const t = text.trim();
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(t))
        return t;
    const host = t.split(/[/:?#]/)[0].toLowerCase();
    const local = host === 'localhost' || IPV4.test(host);
    return `${local ? 'http' : 'https'}://${t}`;
}

/** The address without https:// and a trailing slash, as shown in the list. */
export function prettyUrl(url) {
    return url.replace(/^https?:\/\//i, '').replace(/\/$/, '');
}

export function googleUrl(query) {
    return `https://www.google.com/search?q=${encodeURIComponent(query.trim())}`;
}

export function isPathQuery(text) {
    return text.startsWith('~') || text.startsWith('/');
}

/**
 * Splits a typed path into the folder to list and the part of a name typed so far.
 * '~/Play' -> {dir: '/home/me', partial: 'Play', shownDir: '~'}
 */
export function splitPath(text, home) {
    let full = text;
    if (full === '~')
        full = '~/';
    if (full.startsWith('~/'))
        full = home + full.slice(1);
    else if (full.startsWith('~'))
        return null;   // ~otheruser isn't supported
    const cut = full.lastIndexOf('/');
    const dir = cut === 0 ? '/' : full.slice(0, cut);
    return {dir, partial: full.slice(cut + 1), shownDir: tildify(dir, home)};
}

export function tildify(path, home) {
    if (path === home)
        return '~';
    return path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

/**
 * How well `query` matches `text` (0 = not at all). The start of the text beats the
 * start of a word, which beats anywhere inside, which beats letters in order.
 */
export function matchScore(text, query) {
    if (!text || !query)
        return 0;
    const t = text.toLowerCase();
    const q = query.toLowerCase();
    if (t === q)
        return 120;
    if (t.startsWith(q))
        return 100 - Math.min(20, t.length - q.length) / 2;
    const at = t.indexOf(q);
    if (at > 0) {
        const wordStart = /[\s\-_.()]/.test(t[at - 1]) ||
            (text[at] !== t[at] && text[at - 1] === t[at - 1]);   // camelCase
        return wordStart ? 80 : 60;
    }
    if (q.length < 2)
        return 0;
    let i = 0;
    for (const c of t) {
        if (c === q[i])
            i++;
        if (i === q.length)
            return 30;
    }
    return 0;
}

/** The best score over several fields; later fields count a little less. */
export function bestScore(fields, query) {
    let best = 0;
    fields.forEach((f, i) => {
        const s = matchScore(f, query) - (i ? 5 + i : 0);
        if (s > best)
            best = s;
    });
    return best;
}

/** Grey text to show after what was typed: the rest of the name, or " — Name". */
export function ghostFor(typed, name) {
    if (!typed || !name)
        return '';
    if (name.toLowerCase().startsWith(typed.toLowerCase()))
        return name.slice(typed.length);
    return ` — ${name}`;
}

export function historyKey(item) {
    return `${item.kind}:${item.id}`;
}

/** Puts `item` first (once), keeps at most MAX_HISTORY. Returns a new list. */
export function addToHistory(list, item, now = Date.now()) {
    const key = historyKey(item);
    const old = list.find(i => historyKey(i) === key);
    const entry = {...item, time: now, count: (old?.count ?? 0) + 1};
    return [entry, ...list.filter(i => historyKey(i) !== key)].slice(0, MAX_HISTORY);
}

export function removeFromHistory(list, item) {
    const key = historyKey(item);
    return list.filter(i => historyKey(i) !== key);
}

/** Extra points for things used often and lately, at most 15. */
export function usageBoost(entry, now = Date.now()) {
    if (!entry)
        return 0;
    const days = (now - entry.time) / 86400000;
    return Math.min(15, Math.log2(1 + entry.count) * 4 + (days < 1 ? 5 : days < 7 ? 2 : 0));
}
