// Downloads Stack: a macOS-style Downloads stack for Ubuntu Dock.
//
// The dock icon shows the newest downloads piled on top of each other, and
// clicking it opens a grid of recent downloads (like the Dock's "Grid" view on
// macOS). The item lives inside Ubuntu Dock's icon row, just before the Trash.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Graphene from 'gi://Graphene';
import Pango from 'gi://Pango';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as BoxPointer from 'resource:///org/gnome/shell/ui/boxpointer.js';
import {BaseIcon} from 'resource:///org/gnome/shell/ui/iconGrid.js';
import {DashItemContainer} from 'resource:///org/gnome/shell/ui/dash.js';
import {EventEmitter} from 'resource:///org/gnome/shell/misc/signals.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

Gio._promisify(Gio.File.prototype, 'enumerate_children_async');
Gio._promisify(Gio.FileEnumerator.prototype, 'next_files_async');

const DOCK_UUID = 'ubuntu-dock@ubuntu.com';
const MAX_ITEMS = 60;
const GRID_COLUMNS = 5;
const TILE_ICON_SIZE = 64;
const PARTIAL_DOWNLOAD = /\.(crdownload|part|partial|download|tmp)$/i;
const QUERY_ATTRS = [
    'standard::name',
    'standard::display-name',
    'standard::type',
    'standard::is-hidden',
    'standard::is-backup',
    'standard::icon',
    'standard::content-type',
    'time::modified',
    'time::changed',
    'time::created',
    'thumbnail::path',
    'thumbnail::is-valid',
].join(',');

/** Watches the Downloads folder and keeps the newest entries sorted. */
class DownloadsModel extends EventEmitter {
    constructor(helperPath) {
        super();
        this._helperPath = helperPath;
        this._entries = [];
        this._total = 0;
        this._thumbAttempted = new Set();
        this._cancellable = new Gio.Cancellable();

        const path = GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) ??
            GLib.build_filenamev([GLib.get_home_dir(), 'Downloads']);
        this.dir = Gio.File.new_for_path(path);

        try {
            this._monitor = this.dir.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
            this._monitor.connect('changed', () => this._queueScan());
        } catch (e) {
            logError(e, 'Downloads Stack: cannot monitor Downloads');
        }

        this._scan();
    }

    get entries() {
        return this._entries;
    }

    get total() {
        return this._total;
    }

    _queueScan() {
        if (this._scanId)
            return;
        this._scanId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 400, () => {
            this._scanId = 0;
            this._scan();
            return GLib.SOURCE_REMOVE;
        });
    }

    async _scan() {
        const infos = [];
        try {
            const enumerator = await this.dir.enumerate_children_async(QUERY_ATTRS,
                Gio.FileQueryInfoFlags.NONE, GLib.PRIORITY_LOW, this._cancellable);
            for (;;) {
                // eslint-disable-next-line no-await-in-loop
                const batch = await enumerator.next_files_async(200, GLib.PRIORITY_LOW,
                    this._cancellable);
                if (!batch.length)
                    break;
                infos.push(...batch);
            }
            enumerator.close_async(GLib.PRIORITY_LOW, null, null);
        } catch (e) {
            if (e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                return;
            if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
                logError(e, 'Downloads Stack: cannot read Downloads');
        }

        const entries = infos
            .filter(info => !info.get_is_hidden() && !info.get_is_backup() &&
                !PARTIAL_DOWNLOAD.test(info.get_name()))
            .map(info => this._makeEntry(info));
        // "Date Added", like the macOS Downloads stack: a file's inode change
        // time moves when it is created in or moved into the folder.
        entries.sort((a, b) => b.added - a.added);

        this._total = entries.length;
        this._entries = entries.slice(0, MAX_ITEMS);
        this.emit('changed');
        this._ensureThumbnails();
    }

    _makeEntry(info) {
        const file = this.dir.get_child(info.get_name());
        const isDir = info.get_file_type() === Gio.FileType.DIRECTORY;
        const thumbPath = info.get_attribute_byte_string('thumbnail::path');
        const hasThumb = !isDir && thumbPath &&
            info.get_attribute_boolean('thumbnail::is-valid');
        const added = Math.max(
            info.get_attribute_uint64('time::changed'),
            info.get_attribute_uint64('time::created'));

        return {
            file,
            name: info.get_display_name(),
            isDir,
            added,
            mtime: info.get_attribute_uint64('time::modified'),
            hasThumb,
            gicon: hasThumb
                ? new Gio.FileIcon({file: Gio.File.new_for_path(thumbPath)})
                : info.get_icon(),
        };
    }

    _ensureThumbnails() {
        if (this._thumbProc)
            return;

        const wanted = this._entries.filter(e => {
            if (e.isDir || e.hasThumb)
                return false;
            const key = `${e.file.get_uri()}:${e.mtime}`;
            if (this._thumbAttempted.has(key))
                return false;
            this._thumbAttempted.add(key);
            return true;
        });
        if (!wanted.length)
            return;

        try {
            this._thumbProc = Gio.Subprocess.new(
                ['python3', this._helperPath, ...wanted.map(e => e.file.get_path())],
                Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch (e) {
            logError(e, 'Downloads Stack: cannot start thumbnailer');
            return;
        }

        this._thumbProc.wait_async(this._cancellable, () => {
            this._thumbProc = null;
            this._queueScan();
        });
    }

    destroy() {
        this._cancellable.cancel();
        this._thumbProc?.force_exit();
        this._monitor?.cancel();
        if (this._scanId)
            GLib.source_remove(this._scanId);
        this._scanId = 0;
    }
}

function launchFile(file) {
    const context = global.create_app_launch_context(0, -1);
    Gio.AppInfo.launch_default_for_uri_async(file.get_uri(), context, null, (_o, res) => {
        try {
            Gio.AppInfo.launch_default_for_uri_finish(res);
        } catch (e) {
            Main.notifyError(`Could not open “${file.get_basename()}”`, e.message);
        }
    });
}

function showInFiles(file) {
    Gio.DBus.session.call(
        'org.freedesktop.FileManager1', '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1', 'ShowItems',
        new GLib.Variant('(ass)', [[file.get_uri()], '']),
        null, Gio.DBusCallFlags.NONE, -1, null, null);
}

/** The grid that pops up from the dock icon. */
class StackMenu extends PopupMenu.PopupMenu {
    constructor(source, side, model) {
        super(source, 0.5, side);
        this._model = model;
        this.blockSourceEvents = true;
        this.actor.add_style_class_name('downloads-stack-menu');

        const content = new St.BoxLayout({vertical: true, style_class: 'downloads-stack-content'});

        const header = new St.BoxLayout({style_class: 'downloads-stack-header'});
        const titles = new St.BoxLayout({vertical: true, x_expand: true});
        titles.add_child(new St.Label({text: 'Downloads', style_class: 'downloads-stack-title'}));
        this._subtitle = new St.Label({style_class: 'downloads-stack-subtitle'});
        titles.add_child(this._subtitle);
        header.add_child(titles);

        const openButton = new St.Button({
            style_class: 'downloads-stack-open',
            can_focus: true,
            y_align: Clutter.ActorAlign.CENTER,
            child: new St.BoxLayout({
                style_class: 'downloads-stack-open-box',
            }),
        });
        openButton.child.add_child(new St.Label({
            text: 'Open in Files',
            y_align: Clutter.ActorAlign.CENTER,
        }));
        openButton.child.add_child(new St.Icon({
            icon_name: 'go-next-symbolic',
            style_class: 'downloads-stack-open-icon',
        }));
        openButton.connect('clicked', () => {
            this.close();
            launchFile(this._model.dir);
        });
        header.add_child(openButton);
        content.add_child(header);

        this._scroll = new St.ScrollView({
            style_class: 'downloads-stack-scroll vfade',
            hscrollbar_policy: St.PolicyType.NEVER,
            vscrollbar_policy: St.PolicyType.AUTOMATIC,
            overlay_scrollbars: true,
        });
        this._gridBox = new St.BoxLayout({vertical: true});
        this._scroll.set_child(this._gridBox);
        content.add_child(this._scroll);

        this._empty = new St.Label({
            text: 'No downloads yet',
            style_class: 'downloads-stack-empty',
            x_align: Clutter.ActorAlign.CENTER,
        });
        content.add_child(this._empty);

        this.box.add_child(content);

        this._modelId = model.connect('changed', () => {
            if (this.isOpen)
                this._rebuild();
        });
        this.connect('open-state-changed', (_m, open) => {
            if (open)
                this._rebuild();
        });
    }

    _rebuild() {
        this._gridBox.destroy_all_children();

        const {entries, total} = this._model;
        this._empty.visible = entries.length === 0;
        this._scroll.visible = entries.length > 0;
        this._subtitle.text = total > entries.length
            ? `${entries.length} most recent of ${total} items`
            : `${total} ${total === 1 ? 'item' : 'items'}`;

        const {scaleFactor} = St.ThemeContext.get_for_stage(global.stage);
        const layout = new Clutter.GridLayout({
            orientation: Clutter.Orientation.HORIZONTAL,
            row_spacing: 4 * scaleFactor,
            column_spacing: 4 * scaleFactor,
        });
        const grid = new St.Widget({layout_manager: layout, style_class: 'downloads-stack-grid'});
        entries.forEach((entry, i) =>
            layout.attach(this._makeTile(entry), i % GRID_COLUMNS, Math.floor(i / GRID_COLUMNS), 1, 1));
        this._gridBox.add_child(grid);

        // Keep the popup clear of the top bar and the dock.
        const monitor = Main.layoutManager.findIndexForActor(this.sourceActor);
        const workArea = Main.layoutManager.getWorkAreaForMonitor(monitor);
        const maxHeight = Math.min(480, (workArea.height / scaleFactor) - 220);
        this._scroll.style = `max-height: ${Math.round(maxHeight)}px;`;
        this._scroll.vadjustment.value = 0;
    }

    _makeTile(entry) {
        const box = new St.BoxLayout({vertical: true, style_class: 'downloads-stack-tile-box'});
        box.add_child(new St.Icon({
            gicon: entry.gicon,
            icon_size: TILE_ICON_SIZE,
            style_class: 'downloads-stack-tile-icon',
            x_align: Clutter.ActorAlign.CENTER,
        }));
        const label = new St.Label({
            text: entry.name,
            style_class: 'downloads-stack-tile-label',
            x_align: Clutter.ActorAlign.CENTER,
        });
        label.clutter_text.ellipsize = Pango.EllipsizeMode.MIDDLE;
        box.add_child(label);

        const tile = new St.Button({
            style_class: 'downloads-stack-tile',
            can_focus: true,
            track_hover: true,
            button_mask: St.ButtonMask.ONE | St.ButtonMask.THREE,
            child: box,
            accessible_name: entry.name,
        });
        tile.connect('clicked', (_b, button) => {
            this.close();
            if (button === Clutter.BUTTON_SECONDARY)
                showInFiles(entry.file);
            else
                launchFile(entry.file);
        });
        return tile;
    }

    destroy() {
        this._model.disconnect(this._modelId);
        super.destroy();
    }
}

/** The dock item: a pile of the newest downloads. */
class StackItem {
    constructor(dash, model, dockModules) {
        this._dash = dash;
        this._model = model;
        this._lastTop = model.entries[0]?.file.get_uri() ?? null;

        this._icon = new BaseIcon('Downloads', {
            createIcon: size => this._createPile(size),
            setSizeManually: true,
            showLabel: false,
        });

        this.button = new St.Button({
            style_class: 'overview-tile downloads-stack-button',
            reactive: true,
            can_focus: true,
            track_hover: true,
            button_mask: St.ButtonMask.ONE | St.ButtonMask.THREE,
            x_expand: false,
            child: this._icon,
            accessible_name: 'Downloads',
        });

        this.item = new DashItemContainer();
        const position = dash._position;
        const {itemShowLabel} = dockModules.appIcons;
        this.item.showLabel = function () {
            itemShowLabel.call(this);
        };
        this.item.label?.add_style_class_name(dockModules.theming.PositionStyleClass[position]);
        this.item.label?.add_style_class_name('shrink');
        this.item.setChild(this.button);
        this.item.setLabelText('Downloads');
        dash._hookUpLabel(this.item, null);

        this._icon.setIconSize(dash.iconSize);
        this._sizeId = dash.connect('icon-size-changed',
            () => this._icon.setIconSize(dash.iconSize));

        this._menuManager = new PopupMenu.PopupMenuManager(this.button);
        this._menu = new StackMenu(this.button, position, model);
        Main.uiGroup.add_child(this._menu.actor);
        this._menu.actor.hide();
        this._menuManager.addMenu(this._menu);
        this._menu.connect('open-state-changed', (_m, open) => {
            this.button.checked = open;
            dash._itemMenuStateChanged(this.item, open);
            // Keep the dock up while the grid is open, even over a window
            // (intellihide would otherwise slide it away under the popup).
            dash.requiresVisibility = open;
        });
        // The dock's own urgent-app timer also clears this flag; re-assert it.
        this._visibilityId = dash.connect('notify::requires-visibility', () => {
            if (this._menu.isOpen && !dash.requiresVisibility)
                dash.requiresVisibility = true;
        });

        this.button.connect('clicked', () => {
            this._menu.toggle(BoxPointer.PopupAnimation.FULL);
        });

        this._modelId = model.connect('changed', () => this._onModelChanged());

        // Sit just before the Trash, like the macOS Dock; the dash inserts its
        // own items by index, so re-check our place whenever it adds one.
        this._childAddedId = dash._box.connect('child-added', () => this._queuePlace());
        dash._box.add_child(this.item);
        this._place();
        this.item.show(false);

        this.item.connect('destroy', () => this._onDestroy());
    }

    _createPile(size) {
        const pile = new St.Widget({
            layout_manager: new Clutter.BinLayout(),
            width: size,
            height: size,
            style_class: 'downloads-stack-pile',
        });

        const top = this._model.entries.slice(0, 3);
        if (!top.length) {
            pile.add_child(new St.Icon({
                gicon: Gio.ThemedIcon.new_from_names(['folder-download', 'folder']),
                icon_size: size,
            }));
            return pile;
        }

        // Back to front: older items peek out, tilted, above the newest one.
        const angles = [[0], [-9, 0], [-13, 8, 0]][top.length - 1];
        const layerSize = Math.round(size * 0.8);
        top.reverse().forEach((entry, i) => {
            const depth = top.length - 1 - i;
            pile.add_child(new St.Icon({
                gicon: entry.gicon,
                icon_size: layerSize,
                style_class: 'downloads-stack-layer',
                x_align: Clutter.ActorAlign.CENTER,
                y_align: Clutter.ActorAlign.END,
                pivot_point: new Graphene.Point({x: 0.5, y: 0.5}),
                rotation_angle_z: angles[i],
                translation_y: -Math.round(depth * size * 0.07),
            }));
        });
        return pile;
    }

    _onModelChanged() {
        // BaseIcon has no public refresh in GNOME 46; this rebuilds the pile.
        this._icon._createIconTexture(this._icon.iconSize);

        const newTop = this._model.entries[0]?.file.get_uri() ?? null;
        if (this._lastTop && newTop && newTop !== this._lastTop)
            this._bounce();
        this._lastTop = newTop;
    }

    // A single hop away from the screen edge when a new download lands.
    _bounce() {
        const side = this._dash._position;
        const distance = Math.round(this._dash.iconSize * 0.35);
        const prop = side === St.Side.LEFT || side === St.Side.RIGHT
            ? 'translation_x' : 'translation_y';
        const sign = side === St.Side.BOTTOM || side === St.Side.RIGHT ? -1 : 1;
        this._icon.remove_all_transitions();
        this._icon.ease({
            [prop]: sign * distance,
            duration: 180,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onComplete: () => this._icon.ease({
                [prop]: 0,
                duration: 320,
                mode: Clutter.AnimationMode.EASE_OUT_BOUNCE,
            }),
        });
    }

    _queuePlace() {
        if (this._placeId)
            return;
        this._placeId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._placeId = 0;
            this._place();
            return GLib.SOURCE_REMOVE;
        });
    }

    _place() {
        const box = this._dash._box;
        const trash = box.get_children().find(c => c.child?._delegate?.app?.isTrash);
        if (trash) {
            if (this.item.get_next_sibling() !== trash)
                box.set_child_below_sibling(this.item, trash);
        } else if (box.get_last_child() !== this.item) {
            box.set_child_above_sibling(this.item, null);
        }
    }

    _onDestroy() {
        if (this._placeId)
            GLib.source_remove(this._placeId);
        this._placeId = 0;
        this._model.disconnect(this._modelId);
        try {
            this._dash.disconnect(this._sizeId);
            this._dash.disconnect(this._visibilityId);
            if (this._menu.isOpen)
                this._dash.requiresVisibility = false;
            this._dash._box.disconnect(this._childAddedId);
        } catch {
            // The whole dock is being torn down.
        }
        this._menu.destroy();
        this.item = null;
    }

    destroy() {
        this.item?.destroy();
    }
}

export default class DownloadsStackExtension extends Extension {
    enable() {
        this._items = new Map();
        this._model = new DownloadsModel(GLib.build_filenamev([this.path, 'thumbnailer.py']));
        this._stateId = Main.extensionManager.connect('extension-state-changed',
            (_m, ext) => {
                if (ext.uuid === DOCK_UUID)
                    this._syncDock();
            });
        this._syncDock();
    }

    async _syncDock() {
        const dock = Main.extensionManager.lookup(DOCK_UUID);
        let manager = null;
        let modules = null;
        try {
            if (dock) {
                const uri = name => dock.dir.get_child(name).get_uri();
                const [ext, appIcons, theming] = await Promise.all([
                    import(uri('extension.js')),
                    import(uri('appIcons.js')),
                    import(uri('theming.js')),
                ]);
                manager = ext.dockManager ?? null;
                modules = {appIcons, theming};
            }
        } catch (e) {
            logError(e, 'Downloads Stack: cannot reach Ubuntu Dock');
        }

        if (!this._model)
            return; // disabled while we were loading

        if (manager !== this._manager) {
            this._disconnectManager();
            this._manager = manager;
            this._dockModules = modules;
            if (manager) {
                this._managerIds = [
                    manager.connect('docks-ready', () => this._attachAll()),
                    manager.connect('docks-destroyed', () => this._detachAll()),
                ];
            }
        }
        this._attachAll();
    }

    _attachAll() {
        if (!this._manager)
            return;
        for (const dock of this._manager._allDocks) {
            const {dash} = dock;
            if (!dash || this._items.has(dash))
                continue;
            try {
                const item = new StackItem(dash, this._model, this._dockModules);
                this._items.set(dash, item);
                item.item.connect('destroy', () => this._items.delete(dash));
            } catch (e) {
                logError(e, 'Downloads Stack: cannot add to dock');
            }
        }
    }

    _detachAll() {
        for (const item of [...this._items.values()])
            item.destroy();
        this._items.clear();
    }

    _disconnectManager() {
        this._managerIds?.forEach(id => this._manager.disconnect(id));
        this._managerIds = null;
        this._manager = null;
    }

    disable() {
        Main.extensionManager.disconnect(this._stateId);
        this._detachAll();
        this._disconnectManager();
        this._model.destroy();
        this._model = null;
        this._items = null;
    }
}
