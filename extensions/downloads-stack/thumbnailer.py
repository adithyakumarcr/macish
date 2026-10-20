#!/usr/bin/env python3
"""Create freedesktop thumbnails for the given paths (used by Downloads Stack).

Runs outside gnome-shell so a slow or crashing thumbnailer can never hang the
desktop. Thumbnails land in ~/.cache/thumbnails like the ones Files makes.
"""
import sys

import gi
gi.require_version('GnomeDesktop', '4.0')
from gi.repository import Gio, GnomeDesktop

factory = GnomeDesktop.DesktopThumbnailFactory.new(
    GnomeDesktop.DesktopThumbnailSize.LARGE)

for path in sys.argv[1:]:
    try:
        f = Gio.File.new_for_path(path)
        info = f.query_info('standard::content-type,time::modified', 0, None)
        uri = f.get_uri()
        mime = info.get_content_type()
        mtime = info.get_attribute_uint64('time::modified')
        if factory.lookup(uri, mtime):
            continue
        # A "failed" marker is retried: stale ones (e.g. left by a thumbnailer
        # that crashed once) would otherwise hide the preview forever.
        # can_thumbnail() refuses files with a valid marker, so ask for the
        # thumbnailer the way it would without one.
        failed = factory.has_valid_failed_thumbnail(uri, mtime)
        if not failed and not factory.can_thumbnail(uri, mime, mtime):
            continue
        try:
            pixbuf = factory.generate_thumbnail(uri, mime, None)
            factory.save_thumbnail(pixbuf, uri, mtime, None)
        except Exception:
            if not failed:
                factory.create_failed_thumbnail(uri, mtime, None)
    except Exception as e:
        print(f'{path}: {e}', file=sys.stderr)
