// Spotlight: a macOS-style search bar for GNOME Shell.
//
// Alt+Space opens a frosted bar in the middle of the screen. Type to find apps,
// open a website or a Google search in Google Chrome, or go to a folder (start
// with ~ or /). An empty bar lists recent picks. The searching itself lives in
// search.js; this file is the bar, the list and what happens on Enter.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Pango from 'gi://Pango';
import Shell from 'gi://Shell';
import Soup from 'gi://Soup?version=3.0';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import * as S from './search.js';

Gio._promisify(Gio.Subprocess.prototype, 'communicate_utf8_async');
Gio._promisify(Gio.File.prototype, 'enumerate_children_async');
Gio._promisify(Gio.FileEnumerator.prototype, 'next_files_async');
Gio._promisify(Gio.File.prototype, 'load_contents_async');
Gio._promisify(Gio.File.prototype, 'replace_contents_bytes_async', 'replace_contents_finish');

const WIDTH = 720;              // logical px, like the mockups
const TOP = 0.2;                // bar's distance from the top, as part of the screen height
const MAX_FOLDERS_IN_INDEX = 60000;
const INDEX_MAX_AGE = 10 * 60;  // seconds before the folder list is read again
const SKIP_DIRS = ['node_modules', '__pycache__', 'site-packages', 'venv', 'snap',
    'miniconda3', 'miniforge3', 'anaconda3', 'go'];
const CHROME_IDS = ['google-chrome.desktop', 'com.google.Chrome.desktop', 'google-chrome-beta.desktop'];
const TERMINALS = ['x-terminal-emulator', 'gnome-terminal', 'terminator', 'ptyxis', 'kgx', 'tilix', 'xfce4-terminal'];

const isTld = label => Soup.tld_domain_is_public_suffix(label);
const esc = s => GLib.markup_escape_text(s, -1);

/** `title` with the part matching `query` in bold, as Pango markup. */
function highlight(title, query) {
    const at = query ? title.toLowerCase().indexOf(query.toLowerCase()) : -1;
    if (at < 0)
        return esc(title);
    const end = at + query.length;
    return `${esc(title.slice(0, at))}<b>${esc(title.slice(at, end))}</b>${esc(title.slice(end))}`;
}

// ---- remembered picks --------------------------------------------------------------

class History {
    constructor(path) {
        this._file = Gio.File.new_for_path(path);
        this.items = [];
        this._saving = Promise.resolve();
        this._load();
    }

    async _load() {
        try {
            const [bytes] = await this._file.load_contents_async(null);
            const items = JSON.parse(new TextDecoder().decode(bytes));
            if (Array.isArray(items))
                this.items = items.filter(i => i && i.kind && i.id);
        } catch (e) {
            if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
                console.warn(`Spotlight: can't read ${this._file.get_path()}: ${e.message}`);
        }
    }

    find(kind, id) {
        return this.items.find(i => i.kind === kind && i.id === id);
    }

    add(item) {
        this.items = S.addToHistory(this.items, item);
        this._save();
    }

    remove(item) {
        this.items = S.removeFromHistory(this.items, item);
        this._save();
    }

    clear() {
        this.items = [];
        this._save();
    }

    _save() {
        const data = new TextEncoder().encode(JSON.stringify(this.items));
        this._saving = this._saving.then(async () => {
            try {
                GLib.mkdir_with_parents(this._file.get_parent().get_path(), 0o700);
                await this._file.replace_contents_bytes_async(new GLib.Bytes(data), null, false,
                    Gio.FileCreateFlags.PRIVATE | Gio.FileCreateFlags.REPLACE_DESTINATION, null);
            } catch (e) {
                console.warn(`Spotlight: can't save history: ${e.message}`);
            }
        });
    }
}

// ---- folders in the home folder, for searching by name -----------------------------

class FolderIndex {
    constructor() {
        this._home = GLib.get_home_dir();
        this._entries = [];
        this._readAt = 0;
        this._cancellable = new Gio.Cancellable();
    }

    refreshIfOld() {
        if (!this._running && GLib.get_monotonic_time() / 1e6 - this._readAt > INDEX_MAX_AGE)
            this._refresh();
    }

    async _refresh() {
        this._running = true;
        const prune = ['(', '-name', '.*'];
        for (const d of SKIP_DIRS)
            prune.push('-o', '-name', d);
        prune.push(')', '-prune');
        try {
            const proc = Gio.Subprocess.new(
                ['find', this._home, '-mindepth', '1', '-maxdepth', '6', ...prune, '-o', '-type', 'd', '-print'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
            const [out] = await proc.communicate_utf8_async(null, this._cancellable);
            this._entries = out.split('\n').filter(Boolean).slice(0, MAX_FOLDERS_IN_INDEX).map(path => {
                const name = GLib.path_get_basename(path);
                return {path, name, depth: path.split('/').length};
            });
            this._readAt = GLib.get_monotonic_time() / 1e6;
        } catch (e) {
            if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                console.warn(`Spotlight: can't list folders: ${e.message}`);
        }
        this._running = false;
    }

    /** Best folders for `query`: name matches only (no fuzzy), shallow and used ones first. */
    search(query, history, limit) {
        const found = [];
        for (const e of this._entries) {
            const s = S.matchScore(e.name, query);
            if (s >= 60)
                found.push({...e, score: s - e.depth + S.usageBoost(history.find('folder', e.path))});
        }
        return found.sort((a, b) => b.score - a.score).slice(0, limit);
    }

    destroy() {
        this._cancellable.cancel();
    }
}

// ---- frosted glass ------------------------------------------------------------------

const MASK_DECL = 'uniform vec2 size;\nuniform float radius;\n';
const MASK_CODE = `
vec2 p = cogl_tex_coord_in[0].xy * size;
vec2 q = abs(p - size * 0.5) - (size * 0.5 - vec2(radius));
float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
cogl_color_out *= clamp(0.5 - d, 0.0, 1.0);
`;

/** Cuts an actor's painting to a rounded rectangle. */
const RoundedMask = GObject.registerClass(
class RoundedMask extends Shell.GLSLEffect {
    _init() {
        super._init();
        this._sizeLoc = this.get_uniform_location('size');
        this._radiusLoc = this.get_uniform_location('radius');
    }

    vfunc_build_pipeline() {
        this.add_glsl_snippet(Shell.SnippetHook.FRAGMENT, MASK_DECL, MASK_CODE, false);
    }

    setShape(width, height, radius) {
        this.set_uniform_float(this._sizeLoc, 2, [width, height]);
        this.set_uniform_float(this._radiusLoc, 1, [radius]);
        this.queue_repaint();
    }
});

/**
 * A rounded card that shows the windows behind it blurred. The blur works on a clone
 * of the window group (Shell.BlurEffect's background mode can't be rounded), shifted
 * so the clone lines up with what is really behind the card.
 */
const GlassCard = GObject.registerClass(
class GlassCard extends St.Widget {
    _init(styleClass, radius, content) {
        super._init({layout_manager: new Clutter.BinLayout(), x_expand: true});
        this._radius = radius;

        this._clone = new Clutter.Clone({source: global.window_group});
        this._blurHost = new Clutter.Actor({clip_to_allocation: true, x_expand: true, y_expand: true});
        this._blurHost.add_child(this._clone);
        this._blurHost.add_effect(new Shell.BlurEffect({mode: Shell.BlurMode.ACTOR, radius: 36, brightness: 1}));

        this._glass = new Clutter.Actor({
            layout_manager: new Clutter.BinLayout(), clip_to_allocation: true, x_expand: true, y_expand: true,
        });
        this._glass.add_child(this._blurHost);
        this._mask = new RoundedMask();
        this._glass.add_effect(this._mask);

        this.add_child(this._glass);
        this.add_child(new St.Widget({style_class: `lam-spot-glass ${styleClass}`, x_expand: true, y_expand: true}));
        this.add_child(content);
        this.connect('notify::allocation', () => this.sync());
    }

    /** Lines the clone up again; call after the card moved on screen. */
    sync() {
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const [w, h] = this.get_size();
        this._mask.setShape(w, h, this._radius * scale);
        const [x, y] = this.get_transformed_position();
        this._clone.set_position(-x, -y);
    }
});

// ---- the bar -------------------------------------------------------------------------

const Spotlight = GObject.registerClass(
class Spotlight extends St.Widget {
    _init(extension) {
        super._init({reactive: true, visible: false, style_class: 'lam-spot-backdrop'});
        this._ext = extension;
        this._home = GLib.get_home_dir();
        this._history = new History(GLib.build_filenamev([GLib.get_user_data_dir(), 'like-a-mac', 'spotlight', 'history.json']));
        this._folders = new FolderIndex();
        this._appSys = Shell.AppSystem.get_default();
        this._apps = null;
        this._installedId = this._appSys.connect('installed-changed', () => (this._apps = null));
        this._items = [];
        this._selected = 0;
        this._serial = 0;

        this.add_constraint(new Clutter.BindConstraint({source: global.stage, coordinate: Clutter.BindCoordinate.ALL}));
        this.connect('button-press-event', () => {
            this.close();
            return Clutter.EVENT_STOP;
        });

        this._box = new St.BoxLayout({vertical: true, reactive: true, style_class: 'lam-spot'});
        this._box.connect('button-press-event', () => Clutter.EVENT_STOP);
        this.add_child(this._box);

        // search field
        this._entry = new St.Entry({
            style_class: 'lam-spot-entry', can_focus: true, x_expand: true,
            hint_text: 'Search apps, websites, folders', y_align: Clutter.ActorAlign.CENTER,
        });
        // grey completion, placed right where the typed text ends (see _placeGhost)
        this._ghost = new St.Label({style_class: 'lam-spot-entry lam-spot-ghost'});
        const ghostLayer = new St.Widget({x_expand: true, y_expand: true});
        ghostLayer.add_child(this._ghost);
        const field = new St.Widget({layout_manager: new Clutter.BinLayout(), x_expand: true, clip_to_allocation: true});
        field.add_child(ghostLayer);
        field.add_child(this._entry);
        this._field = field;

        this._topIcon = new St.Icon({style_class: 'lam-spot-top-icon', icon_size: 32, visible: false});
        const bar = new St.BoxLayout({style_class: 'lam-spot-bar', x_expand: true});
        bar.add_child(new St.Icon({style_class: 'lam-spot-search-icon', icon_name: 'edit-find-symbolic', icon_size: 22,
            y_align: Clutter.ActorAlign.CENTER}));
        bar.add_child(field);
        bar.add_child(this._topIcon);
        this._barCard = new GlassCard('lam-spot-bar-glass', 32, bar);
        this._box.add_child(this._barCard);

        // results
        this._crumbs = new St.BoxLayout({style_class: 'lam-spot-crumbs', visible: false});
        this._list = new St.BoxLayout({vertical: true, style_class: 'lam-spot-list'});
        this._footer = new St.BoxLayout({style_class: 'lam-spot-footer'});
        const panel = new St.BoxLayout({vertical: true, style_class: 'lam-spot-panel', x_expand: true});
        panel.add_child(this._crumbs);
        panel.add_child(this._list);
        panel.add_child(this._footer);
        this._panelCard = new GlassCard('lam-spot-panel-glass', 22, panel);
        this._panelCard.add_style_class_name('lam-spot-panel-card');
        this._box.add_child(this._panelCard);

        const text = this._entry.clutter_text;
        text.connect('text-changed', () => this._update());
        text.connect('key-press-event', (_a, event) => this._onKey(event));

        Main.layoutManager.uiGroup.add_child(this);
    }

    get isOpen() {
        return this.visible;
    }

    toggle() {
        if (this.isOpen)
            this.close();
        else
            this.open();
    }

    open() {
        if (Main.overview.visible)
            Main.overview.hide();
        const scale = St.ThemeContext.get_for_stage(global.stage).scale_factor;
        const monitor = Main.layoutManager.monitors[global.display.get_current_monitor()] ??
            Main.layoutManager.primaryMonitor;
        const width = Math.min(WIDTH * scale, monitor.width - 40 * scale);
        this._box.width = width;
        this._box.set_position(Math.round(monitor.x + (monitor.width - width) / 2),
            Math.round(monitor.y + monitor.height * TOP));

        const dark = St.Settings.get().color_scheme === St.SystemColorScheme.PREFER_DARK;
        this._box.remove_style_class_name(dark ? 'lam-spot-light' : 'lam-spot-dark');
        this._box.add_style_class_name(dark ? 'lam-spot-dark' : 'lam-spot-light');

        this.get_parent().set_child_above_sibling(this, null);
        this.show();
        this._grab = Main.pushModal(this, {actionMode: Shell.ActionMode.POPUP});
        if ((this._grab.get_seat_state() & Clutter.GrabState.KEYBOARD) === 0) {
            Main.popModal(this._grab);
            this._grab = null;
            this.hide();
            return;
        }

        this._folders.refreshIfOld();
        this._entry.text = '';
        this._update();
        this._entry.grab_key_focus();

        this._box.opacity = 0;
        this._box.ease({opacity: 255, duration: 120, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            this._barCard.sync();
            this._panelCard.sync();
            return GLib.SOURCE_REMOVE;
        });
    }

    close() {
        if (!this.isOpen)
            return;
        if (this._grab) {
            Main.popModal(this._grab);
            this._grab = null;
        }
        this._serial++;
        this.hide();
    }

    // ---- what to show for the text ----

    _update() {
        const serial = ++this._serial;
        const text = this._entry.text;
        const q = text.trim();
        this._crumbs.visible = false;
        if (!q) {
            this._show(this._recentSections(), 'recent', text);
        } else if (S.isPathQuery(text)) {
            this._pathSections(text, serial).then(sections => {
                if (serial === this._serial)
                    this._show(sections, 'folder', text);
            }).catch(e => console.warn(`Spotlight: ${e.message}`));
        } else {
            this._show(this._searchSections(q), S.looksLikeUrl(q, isTld) ? 'web' : 'search', text);
        }
    }

    _recentSections() {
        const items = [];
        for (const h of this._history.items) {
            const item = this._historyItem(h);
            if (item)
                items.push(item);
            if (items.length === 6)
                break;
        }
        return items.length ? [{title: 'Recent', clear: true, items}] : [];
    }

    /** A remembered pick as a row, or null if it's gone (an uninstalled app). */
    _historyItem(h, query = '') {
        const base = {kind: h.kind, id: h.id, fromHistory: h, markup: highlight(h.title ?? h.id, query)};
        switch (h.kind) {
        case 'app': {
            const app = this._appSys.lookup_app(h.id);
            if (!app)
                return null;
            return {...base, title: app.get_name(), gicon: app.get_icon(), right: 'Application',
                markup: highlight(app.get_name(), query), complete: app.get_name()};
        }
        case 'url':
            return {...base, title: h.title, gicon: this._icon('globe'), right: 'Website · Chrome', complete: h.title};
        case 'search':
            return {...base, title: h.id, gicon: this._icon('google'), right: 'Google Search', complete: h.id};
        case 'folder':
            return this._folderItem(h.id, query, {fromHistory: h});
        }
        return null;
    }

    _searchSections(q) {
        const sections = [];
        const isUrl = S.looksLikeUrl(q, isTld);
        if (isUrl) {
            const url = S.toUrl(q);
            sections.push({title: 'Website', items: [
                {kind: 'url', id: url, title: S.prettyUrl(url), markup: `Open <b>${esc(S.prettyUrl(url))}</b>`,
                    gicon: this._chromeIcon(), right: this._chrome() ? 'Google Chrome' : 'Web Browser', enterHint: true},
                this._googleItem(q),
            ]});
        }

        const apps = this._searchApps(q);
        const folders = this._folders.search(q, this._history, 3).map(f => ({...this._folderItem(f.path, q), score: f.score}));
        const recent = this._history.items
            .filter(h => (h.kind === 'url' || h.kind === 'search') && !(isUrl && h.id === S.toUrl(q)))
            .map(h => ({h, score: S.matchScore(h.kind === 'url' ? h.title : h.id, q)}))
            .filter(r => r.score >= 60)
            .map(r => ({...this._historyItem(r.h, q), score: r.score + S.usageBoost(r.h)}))
            .slice(0, 2);

        if (!isUrl) {
            const best = [apps[0], folders[0], recent[0]].filter(Boolean).sort((a, b) => b.score - a.score)[0];
            if (best) {
                sections.push({title: 'Top Hit', items: [best]});
                for (const list of [apps, folders, recent]) {
                    const i = list.indexOf(best);
                    if (i >= 0)
                        list.splice(i, 1);
                }
            }
        }
        if (apps.length)
            sections.push({title: 'Applications', items: apps.slice(0, 4)});
        if (folders.length)
            sections.push({title: 'Folders', items: folders});
        if (recent.length)
            sections.push({title: 'Recent', items: recent});
        if (!isUrl)
            sections.push({title: 'Web', items: [this._googleItem(q)]});
        return sections;
    }

    _searchApps(q) {
        if (!this._apps) {
            this._apps = this._appSys.get_installed().filter(info => info.should_show()).map(info => ({
                id: info.get_id(),
                info,
                fields: [info.get_name(), info.get_generic_name(), ...(info.get_keywords() ?? []),
                    GLib.path_get_basename(info.get_executable() ?? ''), info.get_id().replace(/\.desktop$/, '')]
                    .filter(Boolean),
            }));
        }
        const found = [];
        for (const a of this._apps) {
            // letters-in-order matches only count for the app's name, not its keywords
            const name = S.matchScore(a.fields[0], q);
            const any = S.bestScore(a.fields, q);
            const s = Math.max(name >= 60 || q.length >= 3 ? name : 0, any >= 60 ? any : 0);
            if (s > 0)
                found.push({a, s: s + S.usageBoost(this._history.find('app', a.id))});
        }
        found.sort((x, y) => y.s - x.s);
        return found.slice(0, 6).map(({a, s}) => ({
            kind: 'app', id: a.id, title: a.info.get_name(), markup: highlight(a.info.get_name(), q),
            gicon: a.info.get_icon(), right: 'Application', complete: a.info.get_name(), score: s,
        }));
    }

    async _pathSections(text, serial) {
        const parts = S.splitPath(text, this._home);
        if (!parts)
            return [];
        this._showCrumbs(parts);
        const dir = Gio.File.new_for_path(parts.dir);
        const names = [];
        try {
            const en = await dir.enumerate_children_async('standard::name,standard::type,standard::is-hidden',
                Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_DEFAULT, null);
            for (;;) {
                // eslint-disable-next-line no-await-in-loop
                const infos = await en.next_files_async(200, GLib.PRIORITY_DEFAULT, null);
                if (!infos.length || serial !== this._serial)
                    break;
                for (const info of infos) {
                    const name = info.get_name();
                    if (info.get_file_type() !== Gio.FileType.DIRECTORY)
                        continue;
                    if (info.get_is_hidden() && !parts.partial.startsWith('.'))
                        continue;
                    if (!parts.partial || name.toLowerCase().includes(parts.partial.toLowerCase()))
                        names.push(name);
                }
            }
        } catch (e) {
            if (!e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND) &&
                !e.matches?.(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_DIRECTORY))
                console.warn(`Spotlight: can't list ${parts.dir}: ${e.message}`);
        }
        const p = parts.partial.toLowerCase();
        names.sort((a, b) => {
            const pa = a.toLowerCase().startsWith(p), pb = b.toLowerCase().startsWith(p);
            return pa !== pb ? (pa ? -1 : 1) : a.localeCompare(b, undefined, {sensitivity: 'base'});
        });

        const sections = [];
        const items = [];
        if (!parts.partial)
            items.push({...this._folderItem(parts.dir, ''), markup: `Open <b>${esc(parts.shownDir)}</b>`, tabHint: false});
        for (const name of names.slice(0, parts.partial ? 7 : 6))
            items.push(this._folderItem(GLib.build_filenamev([parts.dir, name]), parts.partial, {inPath: true}));
        if (items.length)
            sections.push({title: `Folders in ${parts.shownDir}`, items});
        else if (parts.partial)
            sections.push({title: `Nothing called “${parts.partial}” in ${parts.shownDir}`, items: []});

        const recent = this._history.items.filter(h => h.kind === 'folder' && !items.some(i => i.id === h.id))
            .slice(0, 2).map(h => this._folderItem(h.id, '', {fromHistory: h}));
        if (recent.length)
            sections.push({title: 'Recent folders', items: recent});
        return sections;
    }

    _folderItem(path, query, extra = {}) {
        const name = path === '/' ? '/' : GLib.path_get_basename(path);
        const parent = GLib.path_get_dirname(path);
        return {
            kind: 'folder', id: path, title: name, markup: highlight(name, query),
            sub: extra.inPath || path === this._home ? '' : S.tildify(parent, this._home),
            gicon: Gio.ThemedIcon.new(this._folderIconName(path)), right: 'Folder',
            complete: extra.inPath ? name : S.tildify(path, this._home), tabHint: true, ...extra,
        };
    }

    _folderIconName(path) {
        if (path === this._home)
            return 'user-home';
        const special = {
            [GLib.UserDirectory.DIRECTORY_DOWNLOAD]: 'folder-download',
            [GLib.UserDirectory.DIRECTORY_DOCUMENTS]: 'folder-documents',
            [GLib.UserDirectory.DIRECTORY_PICTURES]: 'folder-pictures',
            [GLib.UserDirectory.DIRECTORY_MUSIC]: 'folder-music',
            [GLib.UserDirectory.DIRECTORY_VIDEOS]: 'folder-videos',
            [GLib.UserDirectory.DIRECTORY_DESKTOP]: 'user-desktop',
        };
        for (const [dir, icon] of Object.entries(special)) {
            if (GLib.get_user_special_dir(Number(dir)) === path)
                return icon;
        }
        return 'folder';
    }

    _googleItem(q) {
        return {kind: 'search', id: q, title: q, markup: `Search Google for “${esc(q)}”`,
            gicon: this._icon('google'), right: 'Google Search'};
    }

    _icon(name) {
        return Gio.FileIcon.new(this._ext.dir.get_child('icons').get_child(`${name}.svg`));
    }

    _chrome() {
        for (const id of CHROME_IDS) {
            const info = Gio.DesktopAppInfo.new(id);
            if (info)
                return info;
        }
        return null;
    }

    _chromeIcon() {
        return this._chrome()?.get_icon() ?? this._icon('globe');
    }

    // ---- drawing the list ----

    _show(sections, mode, text) {
        this._list.destroy_all_children();
        this._items = [];
        this._mode = mode;
        for (const sec of sections) {
            const head = new St.BoxLayout({style_class: 'lam-spot-section'});
            head.add_child(new St.Label({text: sec.title, x_expand: true}));
            if (sec.clear) {
                const clear = new St.Button({label: 'Clear', style_class: 'lam-spot-clear'});
                clear.connect('clicked', () => {
                    this._history.clear();
                    this._update();
                    this._entry.grab_key_focus();
                });
                head.add_child(clear);
            }
            this._list.add_child(head);
            for (const item of sec.items) {
                item.index = this._items.length;
                item.row = this._row(item);
                this._items.push(item);
                this._list.add_child(item.row);
            }
        }
        this._panelCard.visible = sections.length > 0;
        this._showFooter(mode);
        this._select(0, text);
    }

    _row(item) {
        const row = new St.BoxLayout({style_class: 'lam-spot-row', reactive: true});
        row.add_child(new St.Icon({gicon: item.gicon, icon_size: 30, style_class: 'lam-spot-row-icon',
            y_align: Clutter.ActorAlign.CENTER}));
        const title = new St.Label({style_class: 'lam-spot-row-title', y_align: Clutter.ActorAlign.CENTER});
        title.clutter_text.set_markup(item.markup ?? esc(item.title));
        title.clutter_text.ellipsize = Pango.EllipsizeMode.END;
        row.add_child(title);
        if (item.sub) {
            row.add_child(new St.Label({text: item.sub, style_class: 'lam-spot-row-sub', y_align: Clutter.ActorAlign.CENTER}));
        }
        row.add_child(new St.Widget({x_expand: true}));
        const right = new St.BoxLayout({style_class: 'lam-spot-row-right', y_align: Clutter.ActorAlign.CENTER});
        item.hintBox = new St.BoxLayout({visible: false, style_class: 'lam-spot-hint'});
        right.add_child(item.hintBox);
        right.add_child(new St.Label({text: item.right ?? '', y_align: Clutter.ActorAlign.CENTER}));
        row.add_child(right);

        row.connect('motion-event', () => {
            if (this._selected !== item.index)
                this._select(item.index);
            return Clutter.EVENT_PROPAGATE;
        });
        row.connect('button-release-event', (_a, event) => {
            this._activate(item, (event.get_state() & Clutter.ModifierType.CONTROL_MASK) !== 0);
            return Clutter.EVENT_STOP;
        });
        return row;
    }

    _select(index, text = this._entry.text) {
        const old = this._items[this._selected];
        if (old) {
            old.row.remove_style_pseudo_class('selected');
            old.hintBox.visible = false;
        }
        this._selected = Math.max(0, Math.min(index, this._items.length - 1));
        const item = this._items[this._selected];
        if (item) {
            item.row.add_style_pseudo_class('selected');
            const hint = this._rowHint(item);
            item.hintBox.destroy_all_children();
            if (hint) {
                item.hintBox.add_child(this._kbd(hint[0]));
                item.hintBox.add_child(new St.Label({text: hint[1], style_class: 'lam-spot-kbd-label', y_align: Clutter.ActorAlign.CENTER}));
                item.hintBox.visible = true;
            }
        }
        this._topIcon.gicon = item?.gicon ?? null;
        this._topIcon.visible = !!item && text.trim() !== '';
        this._updateGhost(text);
    }

    _rowHint(item) {
        if (this._mode === 'folder' && item.inPath)
            return ['⇥', 'go in'];
        if (item.enterHint)
            return ['↵', ''];
        return null;
    }

    _completion() {
        const item = this._items[this._selected];
        const text = this._entry.text;
        if (!item?.complete || !text.trim())
            return null;
        if (this._mode === 'folder') {
            const parts = S.splitPath(text, this._home);
            if (!parts || !item.inPath)
                return null;
            const done = `${text.slice(0, text.length - parts.partial.length)}${item.complete}/`;
            return {ghost: item.complete.toLowerCase().startsWith(parts.partial.toLowerCase())
                ? item.complete.slice(parts.partial.length) : '', text: done};
        }
        if (item.kind === 'folder')
            return {ghost: S.ghostFor(text, item.title), text: `${item.complete}/`};
        if (item.kind === 'app' || item.complete.toLowerCase().startsWith(text.toLowerCase()))
            return {ghost: S.ghostFor(text, item.complete), text: item.complete};
        return null;
    }

    _updateGhost(text) {
        const c = this._mode !== 'recent' && this._selected === 0 || this._mode === 'folder' ? this._completion() : null;
        this._ghostText = c?.ghost ?? '';
        this._ghost.text = this._ghostText;
        this._ghost.visible = false;
        if (this._ghostText && !this._ghostLater) {
            this._ghostLater = global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
                this._ghostLater = 0;
                this._placeGhost();
                return GLib.SOURCE_REMOVE;
            });
        }
    }

    _placeGhost() {
        const text = this._entry.clutter_text;
        if (!this._ghostText || !this.isOpen)
            return;
        const [ok, x, y] = text.position_to_coords(-1);
        if (!ok)
            return;
        const [fx, fy] = this._field.get_transformed_position();
        const [tx, ty] = text.get_transformed_position();
        this._ghost.set_position(Math.round(tx - fx + x), Math.round(ty - fy + y));
        this._ghost.visible = true;
    }

    _acceptCompletion() {
        const c = this._completion();
        if (!c)
            return false;
        this._entry.text = c.text;
        this._entry.clutter_text.set_cursor_position(-1);
        return true;
    }

    _showCrumbs(parts) {
        this._crumbs.destroy_all_children();
        const segs = parts.shownDir === '/' ? ['/'] : parts.shownDir.split('/').map((s, i) => (i === 0 && s === '' ? '/' : s));
        let path = '';
        segs.forEach((seg, i) => {
            path = i === 0 ? seg : `${path === '/' ? '' : path}/${seg}`;
            const target = `${path === '/' ? '' : path}/`;
            if (i > 0)
                this._crumbs.add_child(new St.Label({text: '›', style_class: 'lam-spot-crumb-sep', y_align: Clutter.ActorAlign.CENTER}));
            const b = new St.Button({label: seg, style_class: 'lam-spot-crumb'});
            b.connect('clicked', () => {
                this._entry.text = target;
                this._entry.grab_key_focus();
            });
            this._crumbs.add_child(b);
        });
        if (parts.partial) {
            this._crumbs.add_child(new St.Label({text: '›', style_class: 'lam-spot-crumb-sep', y_align: Clutter.ActorAlign.CENTER}));
            this._crumbs.add_child(new St.Label({text: `${parts.partial}…`, style_class: 'lam-spot-crumb lam-spot-crumb-on'}));
        }
        this._crumbs.visible = true;
    }

    _kbd(key) {
        return new St.Label({text: key, style_class: 'lam-spot-kbd', y_align: Clutter.ActorAlign.CENTER});
    }

    _showFooter(mode) {
        const hints = {
            recent: [[['↑', '↓'], 'choose'], [['↵'], 'open'], [['Del'], 'remove from recents']],
            search: [[['↵'], 'open'], [['⇥'], 'complete'], [['Ctrl', '↵'], 'new window']],
            web: [[['↵'], 'open in Chrome'], [['Ctrl', '↵'], 'new window']],
            folder: [[['⇥'], 'go into folder'], [['↵'], 'open in Files'], [['Ctrl', '↵'], 'open terminal here']],
        }[mode];
        this._footer.destroy_all_children();
        for (const [keys, label] of hints) {
            const h = new St.BoxLayout({style_class: 'lam-spot-hint'});
            keys.forEach(k => h.add_child(this._kbd(k)));
            h.add_child(new St.Label({text: label, style_class: 'lam-spot-kbd-label', y_align: Clutter.ActorAlign.CENTER}));
            this._footer.add_child(h);
        }
        this._footer.add_child(new St.Widget({x_expand: true}));
        const esc_ = new St.BoxLayout({style_class: 'lam-spot-hint'});
        esc_.add_child(this._kbd('esc'));
        esc_.add_child(new St.Label({text: 'close', style_class: 'lam-spot-kbd-label', y_align: Clutter.ActorAlign.CENTER}));
        this._footer.add_child(esc_);
    }

    // ---- keys ----

    _onKey(event) {
        const key = event.get_key_symbol();
        const ctrl = (event.get_state() & Clutter.ModifierType.CONTROL_MASK) !== 0;
        const text = this._entry.clutter_text;
        switch (key) {
        case Clutter.KEY_Escape:
            if (this._entry.text)
                this._entry.text = '';
            else
                this.close();
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Down:
        case Clutter.KEY_KP_Down:
            this._select((this._selected + 1) % Math.max(1, this._items.length));
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Up:
        case Clutter.KEY_KP_Up:
            this._select((this._selected - 1 + this._items.length) % Math.max(1, this._items.length));
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Return:
        case Clutter.KEY_KP_Enter:
        case Clutter.KEY_ISO_Enter: {
            const item = this._items[this._selected];
            if (item)
                this._activate(item, ctrl);
            return Clutter.EVENT_STOP;
        }
        case Clutter.KEY_Tab:
        case Clutter.KEY_ISO_Left_Tab:
            this._acceptCompletion();
            return Clutter.EVENT_STOP;
        case Clutter.KEY_Right:
        case Clutter.KEY_KP_Right:
            if (text.get_cursor_position() === -1 && !text.get_selection() && this._ghost.visible && this._acceptCompletion())
                return Clutter.EVENT_STOP;
            return Clutter.EVENT_PROPAGATE;
        case Clutter.KEY_Delete:
        case Clutter.KEY_KP_Delete: {
            const item = this._items[this._selected];
            if (!this._entry.text && item?.fromHistory) {
                this._history.remove(item.fromHistory);
                const keep = this._selected;
                this._update();
                this._select(keep);
                return Clutter.EVENT_STOP;
            }
            return Clutter.EVENT_PROPAGATE;
        }
        }
        return Clutter.EVENT_PROPAGATE;
    }

    // ---- doing it ----

    _activate(item, ctrl) {
        try {
            switch (item.kind) {
            case 'app': {
                const app = this._appSys.lookup_app(item.id);
                if (ctrl && app.can_open_new_window())
                    app.open_new_window(-1);
                else
                    app.activate();
                this._history.add({kind: 'app', id: item.id, title: item.title});
                break;
            }
            case 'url':
                this._openWeb(item.id, ctrl);
                this._history.add({kind: 'url', id: item.id, title: item.title});
                break;
            case 'search':
                this._openWeb(S.googleUrl(item.id), ctrl);
                this._history.add({kind: 'search', id: item.id, title: item.id});
                break;
            case 'folder':
                if (ctrl)
                    this._openTerminal(item.id);
                else
                    Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(item.id).get_uri(), this._launchContext());
                this._history.add({kind: 'folder', id: item.id, title: item.title});
                break;
            }
        } catch (e) {
            Main.notifyError('Spotlight couldn’t open it', e.message);
        }
        this.close();
    }

    _launchContext() {
        return global.create_app_launch_context(0, -1);
    }

    _openWeb(url, newWindow) {
        const chrome = this._chrome();
        if (!chrome) {
            Gio.AppInfo.launch_default_for_uri(url, this._launchContext());
        } else if (newWindow) {
            const exe = chrome.get_executable();
            Gio.AppInfo.create_from_commandline(`${GLib.shell_quote(exe)} --new-window`, null,
                Gio.AppInfoCreateFlags.SUPPORTS_URIS).launch_uris([url], this._launchContext());
        } else {
            chrome.launch_uris([url], this._launchContext());
        }
    }

    _openTerminal(path) {
        for (const name of TERMINALS) {
            const exe = GLib.find_program_in_path(name);
            if (!exe)
                continue;
            const launcher = new Gio.SubprocessLauncher({flags: Gio.SubprocessFlags.NONE});
            launcher.set_cwd(path);
            launcher.spawnv([exe, `--working-directory=${path}`]);
            return;
        }
        throw new Error('No terminal program found');
    }

    destroy() {
        this.close();
        this._appSys.disconnect(this._installedId);
        this._folders.destroy();
        super.destroy();
    }
});

export default class SpotlightExtension extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._spotlight = new Spotlight(this);
        Main.wm.addKeybinding('toggle-spotlight', this._settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW | Shell.ActionMode.POPUP,
            () => this._spotlight.toggle());
        // read the folders once the desktop has settled after login
        this._warmId = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, 20, () => {
            this._spotlight._folders.refreshIfOld();
            this._warmId = 0;
            return GLib.SOURCE_REMOVE;
        });
    }

    disable() {
        if (this._warmId)
            GLib.source_remove(this._warmId);
        this._warmId = 0;
        Main.wm.removeKeybinding('toggle-spotlight');
        this._spotlight?.destroy();
        this._spotlight = null;
        this._settings = null;
    }
}
