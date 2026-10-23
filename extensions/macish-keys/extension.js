// Tells the macish-keys service which app is in front, so Mac shortcuts can depend on it
// (Cmd+C copies in a terminal with Ctrl+Shift+C, Cmd+[ goes back in a browser, ...), which
// keyboard layout is in use, so Option types on a Mac layout (Option+L is @ on German), and
// where the window in front meets another monitor, so Ctrl+Option+arrows go on to it.
// It writes the window's class to $XDG_RUNTIME_DIR/macish-keys/focus, the input source
// ('xkb:de+mac') to .../layout and those sides ('monitor-left') to .../window, nothing else.
// It stays on at the lock screen, so a password types there as it does everywhere else.
// It also carries out what the power button asks for: the service writes 'lock' (a press) or
// 'off' (Ctrl+press, as on a Mac) to .../power, and this locks the screen or shows GNOME's
// Power Off dialog. Not while the screen is locked.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as Keyboard from 'resource:///org/gnome/shell/ui/status/keyboard.js';

const SIDES = [
    ['monitor-left', Meta.DisplayDirection.LEFT],
    ['monitor-right', Meta.DisplayDirection.RIGHT],
    ['monitor-up', Meta.DisplayDirection.UP],
    ['monitor-down', Meta.DisplayDirection.DOWN],
];
const SLACK = 4;   // pixels a tiled window may be off its screen's edge

// The sides where WIN fills that half of its screen (flush against the edge, the full height
// or width, but not the whole screen) and another monitor is next to it
function monitorSides(win) {
    const mon = win.get_monitor();
    if (mon < 0 || win.minimized || win.is_fullscreen())
        return [];
    const r = win.get_frame_rect(), a = win.get_work_area_current_monitor();
    const near = (x, y) => Math.abs(x - y) <= SLACK;
    const left = near(r.x, a.x), right = near(r.x + r.width, a.x + a.width);
    const top = near(r.y, a.y), bottom = near(r.y + r.height, a.y + a.height);
    const half = {
        'monitor-left': left && !right && top && bottom,
        'monitor-right': right && !left && top && bottom,
        'monitor-up': top && !bottom && left && right,
        'monitor-down': bottom && !top && left && right,
    };
    return SIDES.filter(([side, dir]) =>
        half[side] && global.display.get_monitor_neighbor_index(mon, dir) !== -1)
        .map(([side]) => side);
}

export default class MacishKeys extends Extension {
    enable() {
        const dir = GLib.build_filenamev([GLib.get_user_runtime_dir(), 'macish-keys']);
        GLib.mkdir_with_parents(dir, 0o755);
        this._focusFile = GLib.build_filenamev([dir, 'focus']);
        this._layoutFile = GLib.build_filenamev([dir, 'layout']);
        this._windowFile = GLib.build_filenamev([dir, 'window']);
        this._powerFile = Gio.File.new_for_path(GLib.build_filenamev([dir, 'power']));
        this._last = {};
        this._win = null;
        this._winIds = [];
        this._focusId = global.display.connect('notify::focus-window', () => this._writeFocus());
        this._monitorsId = Main.layoutManager.connect('monitors-changed', () => this._writeWindow());
        this._sources = Keyboard.getInputSourceManager();
        this._sourceId = this._sources.connect('current-source-changed', () => this._writeLayout());
        this._powerMonitor = this._powerFile.monitor_file(Gio.FileMonitorFlags.NONE, null);
        this._powerId = this._powerMonitor.connect('changed', (_monitor, _file, _other, event) => {
            if (event === Gio.FileMonitorEvent.CHANGES_DONE_HINT)
                this._power();
        });
        this._writeFocus();
        this._writeLayout();
    }

    _power() {
        if (Main.sessionMode.isLocked)
            return;
        let action;
        try {
            const [, bytes] = this._powerFile.load_contents(null);
            action = new TextDecoder().decode(bytes).split(' ')[0];
        } catch (e) {
            return;
        }
        if (action === 'lock') {
            Main.screenShield.lock(true);
        } else if (action === 'off') {
            Gio.DBus.session.call('org.gnome.SessionManager', '/org/gnome/SessionManager',
                'org.gnome.SessionManager', 'Shutdown', null, null, Gio.DBusCallFlags.NONE, -1,
                null, null);
        }
    }

    _writeFocus() {
        const win = global.display.focus_window;
        const app = win ? (win.get_wm_class() || win.get_gtk_application_id() || '') : '';
        this._write(this._focusFile, app.toLowerCase());
        this._watch(win);
        this._writeWindow();
    }

    // Follows the window in front as it's moved, tiled and resized
    _watch(win) {
        if (win === this._win)
            return;
        this._winIds.forEach(id => this._win.disconnect(id));
        this._win = win;
        this._winIds = win ? ['position-changed', 'size-changed', 'notify::minimized']
            .map(signal => win.connect(signal, () => this._writeWindow())) : [];
    }

    _writeWindow() {
        this._write(this._windowFile, this._win ? monitorSides(this._win).join(' ') : '');
    }

    _writeLayout() {
        const src = this._sources.currentSource;
        this._write(this._layoutFile, src ? `${src.type}:${src.id}` : '');
    }

    _write(file, text) {
        if (this._last[file] === text)
            return;
        this._last[file] = text;
        try {
            GLib.file_set_contents(file, new TextEncoder().encode(text));
        } catch (e) {
            console.warn(`macish-keys: can't write ${file}: ${e.message}`);
        }
    }

    disable() {
        this._watch(null);
        global.display.disconnect(this._focusId);
        Main.layoutManager.disconnect(this._monitorsId);
        this._sources.disconnect(this._sourceId);
        this._powerMonitor.disconnect(this._powerId);
        this._powerMonitor.cancel();
        this._powerMonitor = null;
        this._focusId = this._monitorsId = this._sourceId = this._powerId = 0;
        this._sources = null;
        GLib.unlink(this._focusFile);
        GLib.unlink(this._layoutFile);
        GLib.unlink(this._windowFile);
        GLib.unlink(this._powerFile.get_path());
        this._powerFile = null;
        this._focusFile = this._layoutFile = this._windowFile = null;
    }
}
