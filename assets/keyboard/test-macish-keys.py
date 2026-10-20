#!/usr/bin/env python3
"""Tests for macish-keys' translator: python3 assets/keyboard/test-macish-keys.py

No keyboard or root needed: the translator is fed key events and returns the ones it sends.
"""
import importlib.machinery
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
mk = importlib.machinery.SourceFileLoader('mk', os.path.join(HERE, 'macish-keys')).load_module()
K = mk.KEY

failed = 0


def name(code):
    return next((n for n, c in K.items() if c == code), str(code))


def show(events):
    return ' '.join(('+' if v == 1 else '-' if v == 0 else '~') + name(c) for c, v in events)


class Kb:
    """A keyboard in front of the translator: press() and release() return what it sends."""

    def __init__(self, app='', apple=False):
        self.app = app
        self.t = mk.Translator(app=lambda: self.app, roles=mk.APPLE_ROLES if apple else mk.PC_ROLES)

    def press(self, *keys):
        out = []
        for k in keys:
            out += self.t.feed(K[k], 1)
        return out

    def release(self, *keys):
        out = []
        for k in keys:
            out += self.t.feed(K[k], 0)
        return out

    def repeat(self, key):
        return self.t.feed(K[key], 2)

    def combo(self, *keys):
        """Press the keys in order, then let go in reverse: everything sent."""
        return self.press(*keys) + self.release(*reversed(keys))

    def held(self):
        return sorted(name(c) for c in self.t.out_down)


def expect(what, got, want):
    global failed
    got_s, want_s = show(got), want
    if got_s != want_s:
        failed += 1
        print(f'FAIL {what}\n     got  {got_s}\n     want {want_s}')


def expect_clean(what, kb):
    global failed
    if kb.t.out_down:
        failed += 1
        print(f'FAIL {what}: still held afterwards: {kb.held()}')


# ---- the key positions: Ctrl, Win, Alt -> Control, Option, Command --------------------------
kb = Kb()
expect('Command (Alt) acts as Ctrl right away', kb.press('LEFTALT'), '+RIGHTCTRL')
expect('Command+C is Ctrl+C', kb.combo('C'), '+C -C')
expect('letting go of Command', kb.release('LEFTALT'), '-RIGHTCTRL')
expect('Option (Win) is Alt', kb.combo('LEFTMETA', 'F'), '+LEFTALT +F -F -LEFTALT')
expect('Control stays Ctrl', kb.combo('LEFTCTRL', 'C'), '+LEFTCTRL +C -C -LEFTCTRL')
expect('Right Alt is Command too', kb.combo('RIGHTALT', 'V'), '+RIGHTCTRL +V -V -RIGHTCTRL')
expect('plain typing passes', kb.combo('A'), '+A -A')
expect('Shift passes', kb.combo('LEFTSHIFT', 'A'), '+LEFTSHIFT +A -A -LEFTSHIFT')
expect('Cmd+Shift+Z is Ctrl+Shift+Z (redo)', kb.combo('LEFTALT', 'LEFTSHIFT', 'Z'),
       '+RIGHTCTRL +LEFTSHIFT +Z -Z -LEFTSHIFT -RIGHTCTRL')
expect_clean('basics', kb)

# Apple keyboards already have Command and Option where a Mac has them
kb = Kb(apple=True)
expect('Apple keyboard: Cmd key is Command', kb.combo('LEFTMETA', 'C'), '+RIGHTCTRL +C -C -RIGHTCTRL')
expect('Apple keyboard: Option key is Option', kb.combo('LEFTALT', 'F'), '+LEFTALT +F -F -LEFTALT')
expect_clean('apple', kb)

# ---- Terminal: Cmd copies, Control interrupts ------------------------------------------------
kb = Kb(app='gnome-terminal-server')
for key in 'C V X T N W F'.split():
    expect(f'Terminal: Cmd+{key} is Ctrl+Shift+{key}', kb.combo('LEFTALT', key),
           f'+RIGHTCTRL +LEFTSHIFT +{key} -{key} -LEFTSHIFT -RIGHTCTRL')
expect('Terminal: Control+C still interrupts', kb.combo('LEFTCTRL', 'C'), '+LEFTCTRL +C -C -LEFTCTRL')
expect('Terminal: Cmd+L stays Ctrl+L', kb.combo('LEFTALT', 'L'), '+RIGHTCTRL +L -L -RIGHTCTRL')
expect('Terminal: Cmd+Q quits', kb.combo('LEFTALT', 'Q'),
       '+RIGHTCTRL +LEFTSHIFT +Q -Q -LEFTSHIFT -RIGHTCTRL')
expect('Terminal: Cmd+Backspace deletes to line start', kb.combo('LEFTALT', 'BACKSPACE'),
       '+RIGHTCTRL +U -U -RIGHTCTRL')
expect('Terminal: Option+Backspace deletes a word', kb.combo('LEFTMETA', 'BACKSPACE'),
       '+LEFTALT -LEFTALT +LEFTCTRL +W -W -LEFTCTRL +LEFTALT -LEFTALT')
expect('Terminal: Option+Delete deletes the next word', kb.combo('LEFTMETA', 'DELETE'),
       '+LEFTALT +D -D -LEFTALT')
expect_clean('terminal', kb)
for app in ('org.gnome.console', 'terminator', 'kitty', 'org.gnome.ptyxis'):
    kb = Kb(app=app)
    expect(f'{app}: Cmd+V pastes', kb.combo('LEFTALT', 'V'),
           '+RIGHTCTRL +LEFTSHIFT +V -V -LEFTSHIFT -RIGHTCTRL')

# ---- apps and windows ------------------------------------------------------------------------
kb = Kb(app='org.gnome.texteditor')
expect('Cmd+Q is Ctrl+Q', kb.combo('LEFTALT', 'Q'), '+RIGHTCTRL +Q -Q -RIGHTCTRL')
expect('Cmd+H minimizes', kb.combo('LEFTALT', 'H'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTMETA +H -H -LEFTMETA +RIGHTCTRL -RIGHTCTRL')
expect('Cmd+M minimizes', kb.combo('LEFTALT', 'M'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTMETA +H -H -LEFTMETA +RIGHTCTRL -RIGHTCTRL')
expect('Cmd+Space is Spotlight (Alt+Space)', kb.combo('LEFTALT', 'SPACE'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTALT +SPACE -SPACE -LEFTALT +RIGHTCTRL -RIGHTCTRL')
expect('Ctrl+Cmd+Q locks the screen', kb.combo('LEFTCTRL', 'LEFTALT', 'Q'),
       '+LEFTCTRL +RIGHTCTRL -LEFTCTRL -RIGHTCTRL +LEFTMETA +L -L -LEFTMETA +LEFTCTRL +RIGHTCTRL'
       ' -RIGHTCTRL -LEFTCTRL')
expect('Ctrl+Cmd+F is full screen (F11)', kb.combo('LEFTCTRL', 'LEFTALT', 'F'),
       '+LEFTCTRL +RIGHTCTRL -LEFTCTRL -RIGHTCTRL +F11 -F11 +LEFTCTRL +RIGHTCTRL -RIGHTCTRL -LEFTCTRL')
kb2 = Kb(app='google-chrome')
expect('Chrome: Cmd+Q is Ctrl+Shift+Q', kb2.combo('LEFTALT', 'Q'),
       '+RIGHTCTRL +LEFTSHIFT +Q -Q -LEFTSHIFT -RIGHTCTRL')
expect_clean('apps', kb)

# Cmd+Tab: Super stays held while Command is, so the switcher stays open
kb = Kb()
out = kb.press('LEFTALT', 'TAB')
expect('Cmd+Tab opens the app switcher', out, '+RIGHTCTRL -RIGHTCTRL +LEFTMETA +TAB -TAB')
expect('Tab release is swallowed', kb.release('TAB'), '')
expect('Tab again moves on', kb.combo('TAB'), '+TAB -TAB')
expect('Shift+Tab goes back', kb.combo('LEFTSHIFT', 'TAB'), '+LEFTSHIFT +TAB -TAB -LEFTSHIFT')
expect('letting go of Command picks the app', kb.release('LEFTALT'), '-LEFTMETA')
expect_clean('switcher', kb)
kb = Kb()
expect('Cmd+Shift+Tab', kb.press('LEFTALT', 'LEFTSHIFT', 'TAB'),
       '+RIGHTCTRL +LEFTSHIFT -RIGHTCTRL +LEFTMETA +TAB -TAB')
expect('...and done', kb.release('TAB', 'LEFTSHIFT', 'LEFTALT'), '-LEFTSHIFT -LEFTMETA')
expect_clean('switcher backwards', kb)
kb = Kb()
expect('Cmd+` cycles windows of the app', kb.press('LEFTALT', 'GRAVE'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTMETA +GRAVE -GRAVE')
expect('...until Command goes up', kb.release('GRAVE', 'LEFTALT'), '-LEFTMETA')
expect_clean('switch group', kb)

# Desktops and the overview
kb = Kb()
expect('Ctrl+Left: desktop to the left', kb.combo('LEFTCTRL', 'LEFT'),
       '+LEFTCTRL -LEFTCTRL +LEFTMETA +PAGEUP -PAGEUP -LEFTMETA +LEFTCTRL -LEFTCTRL')
expect('Ctrl+Right: desktop to the right', kb.combo('LEFTCTRL', 'RIGHT'),
       '+LEFTCTRL -LEFTCTRL +LEFTMETA +PAGEDOWN -PAGEDOWN -LEFTMETA +LEFTCTRL -LEFTCTRL')
expect('Ctrl+Up: Mission Control (Super on its own)', kb.combo('LEFTCTRL', 'UP'),
       '+LEFTCTRL -LEFTCTRL +LEFTMETA -LEFTMETA +LEFTCTRL -LEFTCTRL')
expect('Ctrl+Down passes', kb.combo('LEFTCTRL', 'DOWN'), '+LEFTCTRL +DOWN -DOWN -LEFTCTRL')
expect_clean('desktops', kb)

# Screenshots
kb = Kb()
expect('Cmd+Shift+3: whole screen', kb.combo('LEFTALT', 'LEFTSHIFT', '3'),
       '+RIGHTCTRL +LEFTSHIFT -RIGHTCTRL +SYSRQ -SYSRQ +RIGHTCTRL -LEFTSHIFT -RIGHTCTRL')
expect('Cmd+Shift+4: choose an area', kb.combo('LEFTALT', 'LEFTSHIFT', '4'),
       '+RIGHTCTRL +LEFTSHIFT -RIGHTCTRL -LEFTSHIFT +SYSRQ -SYSRQ +RIGHTCTRL +LEFTSHIFT'
       ' -LEFTSHIFT -RIGHTCTRL')
expect('Cmd+Shift+5: screenshot tool', kb.combo('LEFTALT', 'LEFTSHIFT', '5'),
       '+RIGHTCTRL +LEFTSHIFT -RIGHTCTRL -LEFTSHIFT +SYSRQ -SYSRQ +RIGHTCTRL +LEFTSHIFT'
       ' -LEFTSHIFT -RIGHTCTRL')
expect_clean('screenshots', kb)

# ---- text -----------------------------------------------------------------------------------
kb = Kb(app='org.gnome.texteditor')
expect('Cmd+Left: line start', kb.combo('LEFTALT', 'LEFT'),
       '+RIGHTCTRL -RIGHTCTRL +HOME -HOME +RIGHTCTRL -RIGHTCTRL')
expect('Cmd+Right: line end', kb.combo('LEFTALT', 'RIGHT'),
       '+RIGHTCTRL -RIGHTCTRL +END -END +RIGHTCTRL -RIGHTCTRL')
expect('Cmd+Up: top', kb.combo('LEFTALT', 'UP'), '+RIGHTCTRL +HOME -HOME -RIGHTCTRL')
expect('Cmd+Down: bottom', kb.combo('LEFTALT', 'DOWN'), '+RIGHTCTRL +END -END -RIGHTCTRL')
expect('Cmd+Shift+Left: select to line start', kb.combo('LEFTALT', 'LEFTSHIFT', 'LEFT'),
       '+RIGHTCTRL +LEFTSHIFT -RIGHTCTRL +HOME -HOME +RIGHTCTRL -LEFTSHIFT -RIGHTCTRL')
expect('Option+Left: word left', kb.combo('LEFTMETA', 'LEFT'),
       '+LEFTALT -LEFTALT +LEFTCTRL +LEFT -LEFT -LEFTCTRL +LEFTALT -LEFTALT')
expect('Option+Shift+Right: select a word', kb.combo('LEFTMETA', 'LEFTSHIFT', 'RIGHT'),
       '+LEFTALT +LEFTSHIFT -LEFTALT +LEFTCTRL +RIGHT -RIGHT -LEFTCTRL +LEFTALT -LEFTSHIFT -LEFTALT')
expect('Cmd+Backspace: delete to line start', kb.combo('LEFTALT', 'BACKSPACE'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTSHIFT +HOME -HOME -LEFTSHIFT +BACKSPACE -BACKSPACE +RIGHTCTRL'
       ' -RIGHTCTRL')
expect('Option+Backspace: delete a word', kb.combo('LEFTMETA', 'BACKSPACE'),
       '+LEFTALT -LEFTALT +LEFTCTRL +BACKSPACE -BACKSPACE -LEFTCTRL +LEFTALT -LEFTALT')
expect('Option+Delete: delete the next word', kb.combo('LEFTMETA', 'DELETE'),
       '+LEFTALT -LEFTALT +LEFTCTRL +DELETE -DELETE -LEFTCTRL +LEFTALT -LEFTALT')
expect('Cmd+Shift+[ : previous tab', kb.combo('LEFTALT', 'LEFTSHIFT', 'LEFTBRACE'),
       '+RIGHTCTRL +LEFTSHIFT -LEFTSHIFT +PAGEUP -PAGEUP +LEFTSHIFT -LEFTSHIFT -RIGHTCTRL')
expect('Cmd+[ outside browsers stays Ctrl+[', kb.combo('LEFTALT', 'LEFTBRACE'),
       '+RIGHTCTRL +LEFTBRACE -LEFTBRACE -RIGHTCTRL')
expect_clean('text', kb)

# Held keys repeat the translation
kb = Kb()
kb.press('LEFTMETA', 'LEFT')
expect('holding Option+Left keeps jumping words', kb.repeat('LEFT'),
       '-LEFTALT +LEFTCTRL +LEFT -LEFT -LEFTCTRL +LEFTALT')
expect('...and its release is swallowed', kb.release('LEFT'), '')
kb.release('LEFTMETA')
kb.press('A')
expect('a held letter repeats as itself', kb.repeat('A'), '~A')
kb.release('A')
expect_clean('repeat', kb)

# ---- browsers and Files ----------------------------------------------------------------------
kb = Kb(app='firefox')
expect('browser: Cmd+[ is back', kb.combo('LEFTALT', 'LEFTBRACE'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTALT +LEFT -LEFT -LEFTALT +RIGHTCTRL -RIGHTCTRL')
expect('browser: Cmd+] is forward', kb.combo('LEFTALT', 'RIGHTBRACE'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTALT +RIGHT -RIGHT -LEFTALT +RIGHTCTRL -RIGHTCTRL')
expect('browser: Cmd+Option+I is developer tools', kb.combo('LEFTALT', 'LEFTMETA', 'I'),
       '+RIGHTCTRL +LEFTALT -LEFTALT +LEFTSHIFT +I -I -LEFTSHIFT +LEFTALT -LEFTALT -RIGHTCTRL')
expect_clean('browser', kb)
kb = Kb(app='org.gnome.nautilus')
expect('Files: Cmd+Backspace moves to Trash', kb.combo('LEFTALT', 'BACKSPACE'),
       '+RIGHTCTRL -RIGHTCTRL +DELETE -DELETE +RIGHTCTRL -RIGHTCTRL')
expect('Files: Cmd+Up is the parent folder', kb.combo('LEFTALT', 'UP'),
       '+RIGHTCTRL -RIGHTCTRL +LEFTALT +UP -UP -LEFTALT +RIGHTCTRL -RIGHTCTRL')
expect('Files: Cmd+Down opens', kb.combo('LEFTALT', 'DOWN'),
       '+RIGHTCTRL -RIGHTCTRL +ENTER -ENTER +RIGHTCTRL -RIGHTCTRL')
expect('Files: Cmd+Shift+. shows hidden files', kb.combo('LEFTALT', 'LEFTSHIFT', 'DOT'),
       '+RIGHTCTRL +LEFTSHIFT -LEFTSHIFT +H -H +LEFTSHIFT -LEFTSHIFT -RIGHTCTRL')
expect_clean('files', kb)

# ---- the off switch and safety -----------------------------------------------------------------
kb = Kb()
kb.press('LEFTCTRL', 'LEFTMETA', 'LEFTALT')
out = kb.press('ESC')
expect('Ctrl+Option+Cmd+Esc lets go of everything', out, '-LEFTCTRL -RIGHTCTRL -LEFTALT')
if not kb.t.toggled:
    failed += 1
    print('FAIL Ctrl+Option+Cmd+Esc should ask for Mac mode to be switched off')
kb = Kb()
kb.press('LEFTALT', 'LEFTSHIFT', 'A')
expect('reset lets go of every key it holds', kb.t.reset(), '-A -RIGHTCTRL -LEFTSHIFT')
expect_clean('reset', kb)
kb = Kb()
expect('a stray release is ignored', kb.release('B'), '')

print('all passed' if not failed else f'{failed} failed')
sys.exit(1 if failed else 0)
