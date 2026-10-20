// Tells the macish-keys service which app is in front, so Mac shortcuts can depend on it
// (Cmd+C copies in a terminal with Ctrl+Shift+C, Cmd+[ goes back in a browser, ...).
// It writes the window's class, nothing else, to $XDG_RUNTIME_DIR/macish-keys/focus.
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

export default class MacishKeys extends Extension {
    enable() {
        const dir = GLib.build_filenamev([GLib.get_user_runtime_dir(), 'macish-keys']);
        GLib.mkdir_with_parents(dir, 0o755);
        this._file = GLib.build_filenamev([dir, 'focus']);
        this._last = null;
        this._focusId = global.display.connect('notify::focus-window', () => this._write());
        this._write();
    }

    _write() {
        const win = global.display.focus_window;
        const app = win ? (win.get_wm_class() || win.get_gtk_application_id() || '') : '';
        if (app === this._last)
            return;
        this._last = app;
        try {
            GLib.file_set_contents(this._file, new TextEncoder().encode(app.toLowerCase()));
        } catch (e) {
            console.warn(`macish-keys: can't write ${this._file}: ${e.message}`);
        }
    }

    disable() {
        global.display.disconnect(this._focusId);
        this._focusId = 0;
        GLib.unlink(this._file);
        this._file = null;
    }
}
