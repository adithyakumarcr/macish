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

    def __init__(self, app='', apple=False, layout='', window=''):
        self.app, self.layout, self.window = app, layout, window
        self.t = mk.Translator(app=lambda: self.app, roles=mk.APPLE_ROLES if apple else mk.PC_ROLES,
                               layout=lambda: self.layout, window=lambda: self.window)

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
expect('Right Alt stays AltGr', kb.combo('RIGHTALT', 'Q'), '+RIGHTALT +Q -Q -RIGHTALT')
expect('AltGr+Shift passes', kb.combo('RIGHTALT', 'LEFTSHIFT', '7'),
       '+RIGHTALT +LEFTSHIFT +7 -7 -LEFTSHIFT -RIGHTALT')
expect('AltGr held down repeats like a plain key', kb.press('RIGHTALT') + kb.repeat('RIGHTALT')
       + kb.release('RIGHTALT'), '+RIGHTALT ~RIGHTALT -RIGHTALT')
expect('AltGr+arrow is no Mac shortcut', kb.combo('RIGHTALT', 'LEFT'),
       '+RIGHTALT +LEFT -LEFT -RIGHTALT')
expect_clean('AltGr', kb)
kb = Kb(apple=True)
expect('Apple: right Option is still Option', kb.combo('RIGHTALT', 'F'),
       '+LEFTALT +F -F -LEFTALT')
kb = Kb()
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
       '+LEFTCTRL -LEFTCTRL +LEFTMETA +L -L -LEFTMETA +LEFTCTRL +RIGHTCTRL -RIGHTCTRL -LEFTCTRL')
expect('Ctrl+Cmd+F is full screen (F11)', kb.combo('LEFTCTRL', 'LEFTALT', 'F'),
       '+LEFTCTRL -LEFTCTRL +LEFTMETA +F24 -F24 -LEFTMETA +F11 -F11 +LEFTCTRL +RIGHTCTRL'
       ' -RIGHTCTRL -LEFTCTRL')
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

# Window tiling: Ctrl+Option like macOS's Fn+Ctrl, sent as Tiling Assistant's shortcuts
kb = Kb()
for key, mods, out in (('LEFT', 'super', 'LEFT'), ('RIGHT', 'super', 'RIGHT'),
                       ('F', 'super', 'UP'), ('R', 'super', 'DOWN')):
    expect(f'Ctrl+Option+{key}: Super+{out}', kb.combo('LEFTCTRL', 'LEFTMETA', key),
           f'+LEFTCTRL +LEFTALT -LEFTCTRL -LEFTALT +LEFTMETA +{out} -{out} -LEFTMETA +LEFTCTRL'
           ' +LEFTALT -LEFTALT -LEFTCTRL')
for key in ('UP', 'DOWN', 'C', 'ENTER'):
    expect(f'Ctrl+Option+{key}: Ctrl+Super+{key}', kb.combo('LEFTCTRL', 'LEFTMETA', key),
           f'+LEFTCTRL +LEFTALT -LEFTALT +LEFTMETA +{key} -{key} -LEFTMETA +LEFTALT -LEFTALT'
           ' -LEFTCTRL')
expect('Ctrl+Option+Shift+Left is no tiling key', kb.combo('LEFTCTRL', 'LEFTMETA', 'LEFTSHIFT', 'LEFT'),
       '+LEFTCTRL +LEFTALT +LEFTSHIFT +LEFT -LEFT -LEFTSHIFT -LEFTALT -LEFTCTRL')
expect_clean('tiling', kb)

# A window filling the half of its screen next to another monitor goes on to that monitor:
# GNOME's move-to-monitor (Super+Shift+arrow), then the half on the far side (Tiling Assistant)
for side, back, tile in (('LEFT', 'RIGHT', 'super'), ('RIGHT', 'LEFT', 'super'),
                         ('UP', 'DOWN', 'ctrl'), ('DOWN', 'UP', 'ctrl')):
    kb = Kb(window=f'monitor-{side.lower()}')
    then = ('-LEFTSHIFT' if tile == 'super' else '-LEFTSHIFT +LEFTCTRL') + f' +{back} -{back}'
    after = '-LEFTMETA +LEFTCTRL +LEFTALT' if tile == 'super' else '-LEFTMETA +LEFTALT'
    expect(f'Ctrl+Option+{side} at a monitor edge: to the next monitor',
           kb.combo('LEFTCTRL', 'LEFTMETA', side),
           f'+LEFTCTRL +LEFTALT -LEFTCTRL -LEFTALT +LEFTMETA +LEFTSHIFT +{side} -{side} {then}'
           f' {after} -LEFTALT -LEFTCTRL')
    expect_clean(f'monitor {side}', kb)
kb = Kb(window='monitor-left')
expect('Ctrl+Option+Right with a monitor only on the left: tiles as usual',
       kb.combo('LEFTCTRL', 'LEFTMETA', 'RIGHT'),
       '+LEFTCTRL +LEFTALT -LEFTCTRL -LEFTALT +LEFTMETA +RIGHT -RIGHT -LEFTMETA +LEFTCTRL'
       ' +LEFTALT -LEFTALT -LEFTCTRL')
expect('Option+Left at a monitor edge is still a word left', kb.combo('LEFTMETA', 'LEFT'),
       '+LEFTALT -LEFTALT +LEFTCTRL +LEFT -LEFT -LEFTCTRL +LEFTALT -LEFTALT')
kb = Kb(window='monitor-left monitor-up')
expect('a corner window: Ctrl+Option+Up goes to the monitor above',
       kb.combo('LEFTCTRL', 'LEFTMETA', 'UP'),
       '+LEFTCTRL +LEFTALT -LEFTCTRL -LEFTALT +LEFTMETA +LEFTSHIFT +UP -UP -LEFTSHIFT +LEFTCTRL'
       ' +DOWN -DOWN -LEFTMETA +LEFTALT -LEFTALT -LEFTCTRL')
expect_clean('monitors', kb)

# Ctrl+Cmd+drag: while only Control and Command are held, GNOME gets Super (Super+drag moves
# a window). Letting go taps F24, which types nothing, so Super alone doesn't open the overview.
kb = Kb()
expect('Ctrl+Cmd held is Super', kb.press('LEFTCTRL', 'LEFTALT'), '+LEFTCTRL -LEFTCTRL +LEFTMETA')
expect('...letting go taps F24 first', kb.release('LEFTALT', 'LEFTCTRL'),
       '+F24 -F24 -LEFTMETA +LEFTCTRL -LEFTCTRL')
expect_clean('Ctrl+Cmd drag', kb)
expect('Cmd, then Ctrl, is Super too', kb.press('LEFTALT', 'LEFTCTRL'), '+RIGHTCTRL -RIGHTCTRL +LEFTMETA')
expect('...and back', kb.release('LEFTCTRL', 'LEFTALT'), '+F24 -F24 -LEFTMETA +RIGHTCTRL -RIGHTCTRL')
expect_clean('Cmd+Ctrl drag', kb)
expect('Ctrl+Cmd+Space passes as Ctrl+Space', kb.combo('LEFTCTRL', 'LEFTALT', 'SPACE'),
       '+LEFTCTRL -LEFTCTRL +LEFTMETA +F24 -F24 -LEFTMETA +LEFTCTRL +RIGHTCTRL +SPACE -SPACE'
       ' -RIGHTCTRL -LEFTCTRL')
expect('Ctrl+Cmd+Shift is no drag chord', kb.combo('LEFTCTRL', 'LEFTSHIFT', 'LEFTALT'),
       '+LEFTCTRL +LEFTSHIFT +RIGHTCTRL -RIGHTCTRL -LEFTSHIFT -LEFTCTRL')
expect('Ctrl+Option+Cmd is no drag chord', kb.combo('LEFTCTRL', 'LEFTMETA', 'LEFTALT'),
       '+LEFTCTRL +LEFTALT +RIGHTCTRL -RIGHTCTRL -LEFTALT -LEFTCTRL')
kb.press('LEFTCTRL', 'LEFTALT', 'A')
kb.release('A')
expect('a key used up the chord: Super stays off', kb.release('LEFTALT', 'LEFTCTRL'),
       '-RIGHTCTRL -LEFTCTRL')
expect('...and the next Ctrl+Cmd is Super again', kb.press('LEFTCTRL', 'LEFTALT'),
       '+LEFTCTRL -LEFTCTRL +LEFTMETA')
kb.release('LEFTALT', 'LEFTCTRL')
expect_clean('Ctrl+Cmd chord', kb)

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

# ---- Option types on a Mac layout ------------------------------------------------------------
# German (Macintosh) has @ on L's third level, as a German Mac has it on Option+L. Option on its
# own sends LEVEL3 (XKB's third level) there, so the layout picks the Mac's character.
DE = 'xkb:de+mac'
kb = Kb(layout=DE)
expect('Mac layout: Option+L is the third level of L (@)', kb.combo('LEFTMETA', 'L'),
       '+LEVEL3 +L -L -LEVEL3')
expect('Option+Shift+7 is the fourth level (\\)', kb.combo('LEFTMETA', 'LEFTSHIFT', '7'),
       '+LEVEL3 +LEFTSHIFT +7 -7 -LEFTSHIFT -LEVEL3')
expect('Shift, then Option, too', kb.combo('LEFTSHIFT', 'LEFTMETA', '7'),
       '+LEFTSHIFT +LEVEL3 +7 -7 -LEVEL3 -LEFTSHIFT')
for key in ('5', '8', 'E', 'N', 'SPACE', '102ND', 'GRAVE', 'MINUS', 'BACKSLASH', 'SLASH'):
    expect(f'Option+{key} types', kb.combo('LEFTMETA', key), f'+LEVEL3 +{key} -{key} -LEVEL3')
kb.press('LEFTMETA')
expect('several characters with Option held', kb.combo('L') + kb.combo('5'), '+L -L +5 -5')
kb.press('L')
expect('a held Option character repeats', kb.repeat('L'), '~L')
kb.release('L', 'LEFTMETA')
expect('the right Alt passes: the layout gives it the same characters',
       kb.combo('RIGHTALT', 'L'), '+RIGHTALT +L -L -RIGHTALT')
expect('Option+Left still jumps a word', kb.combo('LEFTMETA', 'LEFT'),
       '+LEVEL3 -LEVEL3 +LEFTCTRL +LEFT -LEFT -LEFTCTRL +LEVEL3 -LEVEL3')
expect('Option+Backspace still deletes a word', kb.combo('LEFTMETA', 'BACKSPACE'),
       '+LEVEL3 -LEVEL3 +LEFTCTRL +BACKSPACE -BACKSPACE -LEFTCTRL +LEVEL3 -LEVEL3')
expect('Option with a key that types nothing is Alt (Option+F4)', kb.combo('LEFTMETA', 'F4'),
       '+LEVEL3 -LEVEL3 +LEFTALT +F4 -F4 -LEFTALT +LEVEL3 -LEVEL3')
expect('Cmd+C still copies', kb.combo('LEFTALT', 'C'), '+RIGHTCTRL +C -C -RIGHTCTRL')
expect('Cmd+Shift+Z still redoes', kb.combo('LEFTALT', 'LEFTSHIFT', 'Z'),
       '+RIGHTCTRL +LEFTSHIFT +Z -Z -LEFTSHIFT -RIGHTCTRL')
expect('Option, then Command: a shortcut (Ctrl+Alt), not typing', kb.press('LEFTMETA', 'LEFTALT'),
       '+LEVEL3 -LEVEL3 +RIGHTCTRL +LEFTALT')
expect('...letting go of Command: Option types again', kb.release('LEFTALT'),
       '-RIGHTCTRL -LEFTALT +LEVEL3')
kb.release('LEFTMETA')
expect('Ctrl+Option+Left still tiles', kb.combo('LEFTCTRL', 'LEFTMETA', 'LEFT'),
       '+LEFTCTRL +LEFTALT -LEFTCTRL -LEFTALT +LEFTMETA +LEFT -LEFT -LEFTMETA +LEFTCTRL'
       ' +LEFTALT -LEFTALT -LEFTCTRL')
expect('Ctrl+Option+Enter is still full screen', kb.combo('LEFTCTRL', 'LEFTMETA', 'ENTER'),
       '+LEFTCTRL +LEFTALT -LEFTALT +LEFTMETA +ENTER -ENTER -LEFTMETA +LEFTALT -LEFTALT -LEFTCTRL')
expect_clean('Mac layout', kb)
kb = Kb(app='gnome-terminal-server', layout=DE)
expect('Terminal: Option+L types @ there too', kb.combo('LEFTMETA', 'L'), '+LEVEL3 +L -L -LEVEL3')
expect('Terminal: Option+Delete is still Alt+D', kb.combo('LEFTMETA', 'DELETE'),
       '+LEVEL3 -LEVEL3 +LEFTALT +D -D -LEFTALT +LEVEL3 -LEVEL3')
expect('Terminal: Cmd+V still pastes', kb.combo('LEFTALT', 'V'),
       '+RIGHTCTRL +LEFTSHIFT +V -V -LEFTSHIFT -RIGHTCTRL')
expect_clean('Mac layout, terminal', kb)
kb = Kb(app='firefox', layout=DE)
expect('browser: Cmd+Option+I is still developer tools', kb.combo('LEFTALT', 'LEFTMETA', 'I'),
       '+RIGHTCTRL +LEFTALT -LEFTALT +LEFTSHIFT +I -I -LEFTSHIFT +LEFTALT -LEFTALT -RIGHTCTRL')
expect_clean('Mac layout, browser', kb)
kb = Kb(apple=True, layout=DE)
expect('Apple keyboard: Option+L', kb.combo('LEFTALT', 'L'), '+LEVEL3 +L -L -LEVEL3')
expect('Apple keyboard: right Option+L', kb.combo('RIGHTALT', 'L'), '+LEVEL3 +L -L -LEVEL3')
expect('Apple keyboard: Cmd+C', kb.combo('LEFTMETA', 'C'), '+RIGHTCTRL +C -C -RIGHTCTRL')
expect_clean('Mac layout, Apple keyboard', kb)
kb = Kb(layout=DE)
kb.press('LEFTCTRL', 'LEFTMETA', 'LEFTALT')
expect('Mac layout: Ctrl+Option+Cmd+Esc still switches off', kb.press('ESC'),
       '-LEFTCTRL -RIGHTCTRL -LEFTALT')
if not kb.t.toggled:
    failed += 1
    print('FAIL Ctrl+Option+Cmd+Esc should switch Mac mode off on a Mac layout too')
kb = Kb(layout=DE)
kb.press('LEFTMETA', 'LEFTSHIFT', 'A')
expect('reset lets go of Level 3 too', kb.t.reset(), '-A -LEVEL3 -LEFTSHIFT')
# English (Macintosh): Option types what it types on an English Mac
kb.layout = 'xkb:us+mac'
expect('switching to English (Macintosh): Option+2 is its third level (™)',
       kb.combo('LEFTMETA', '2'), '+LEVEL3 +2 -2 -LEVEL3')
expect('English (Macintosh): Option+Shift+2 (€)', kb.combo('LEFTMETA', 'LEFTSHIFT', '2'),
       '+LEVEL3 +LEFTSHIFT +2 -2 -LEFTSHIFT -LEVEL3')
expect('English (Macintosh): Option+F4 is still Alt+F4', kb.combo('LEFTMETA', 'F4'),
       '+LEVEL3 -LEVEL3 +LEFTALT +F4 -F4 -LEFTALT +LEVEL3 -LEVEL3')
expect_clean('English (Macintosh)', kb)
# English (UK, Macintosh): # is Option+3 there, and numpad Enter would be Level 3: it's Enter
kb = Kb(layout='xkb:gb+mac')
expect('English (UK, Macintosh): Option+3 is its third level (#)', kb.combo('LEFTMETA', '3'),
       '+LEVEL3 +3 -3 -LEVEL3')
expect('English (UK, Macintosh): numpad Enter is Enter', kb.combo('KPENTER'), '+ENTER -ENTER')
kb.press('KPENTER')
expect('...held, it repeats as Enter', kb.repeat('KPENTER'), '~ENTER')
kb.layout = 'xkb:us+mac'
expect('...and goes up as Enter, even after a layout change', kb.release('KPENTER'), '-ENTER')
expect('English (Macintosh): numpad Enter stays itself', kb.combo('KPENTER'), '+KPENTER -KPENTER')
kb.layout = 'xkb:gb+mac'
expect('Cmd+numpad Enter is Ctrl+Enter', kb.combo('LEFTALT', 'KPENTER'),
       '+RIGHTCTRL +ENTER -ENTER -RIGHTCTRL')
expect_clean('English (UK, Macintosh)', kb)
# A layout that isn't a Mac one (a PC layout put back in Settings, one with no Mac version):
# Option is Alt, as before
kb.layout = 'xkb:us'
expect('switching to English (US): Option is Alt again', kb.combo('LEFTMETA', 'L'),
       '+LEFTALT +L -L -LEFTALT')
for layout in ('', 'xkb:us', 'xkb:de', 'xkb:gb', 'ibus:mozc-jp'):
    kb = Kb(layout=layout)
    expect(f'{layout or "no layout known"}: Option+L is Alt+L', kb.combo('LEFTMETA', 'L'),
           '+LEFTALT +L -L -LEFTALT')
    expect(f'{layout or "no layout known"}: Option+F4 is Alt+F4', kb.combo('LEFTMETA', 'F4'),
           '+LEFTALT +F4 -F4 -LEFTALT')
    expect(f'{layout or "no layout known"}: right Alt is AltGr', kb.combo('RIGHTALT', 'Q'),
           '+RIGHTALT +Q -Q -RIGHTALT')
    expect_clean(layout, kb)

# Which layouts are Mac layouts, and which the installer switches
for source in ('xkb:de+mac', 'xkb:de+mac_nodeadkeys', 'xkb:ch+de_mac', 'xkb:gb+mac_intl',
               'xkb:us+dvorak-mac', 'xkb:ara+mac-phonetic', 'xkb:ua+macos', 'XKB:DE+MAC'.lower()):
    if not mk.mac_layout(source):
        failed += 1
        print(f'FAIL {source} is a Mac layout')
for source in ('', 'xkb:de', 'xkb:us', 'xkb:mk', 'xkb:mk+nodeadkeys', 'xkb:de+nodeadkeys',
               'ibus:mac', 'ibus:mozc-jp', 'xkb:us+emacs'):
    if mk.mac_layout(source):
        failed += 1
        print(f'FAIL {source!r} is no Mac layout')
for pc, mac in mk.MAC_LAYOUTS.items():
    if mk.mac_layout('xkb:' + pc) or not mk.mac_layout('xkb:' + mac):
        failed += 1
        print(f'FAIL MAC_LAYOUTS: {pc} -> {mac} should go from a PC layout to a Mac one')
    if mac.split('+')[0] != pc.split('+')[0]:
        failed += 1
        print(f'FAIL MAC_LAYOUTS: {pc} -> {mac} should keep the language')
for pc, mac in (('de', 'de+mac'), ('us', 'us+mac'), ('gb', 'gb+mac')):
    if mk.MAC_LAYOUTS.get(pc) != mac:
        failed += 1
        print(f'FAIL {pc} should become {mac}, its own language\'s Mac layout')

# The login screen's layout, in /etc/default/keyboard
for text, want in (('XKBMODEL="pc105"\nXKBLAYOUT="de"\nXKBVARIANT=""\nXKBOPTIONS=""\n', 'xkb:de'),
                   ('XKBLAYOUT="de"\nXKBVARIANT="mac"\n', 'xkb:de+mac'),
                   ('XKBLAYOUT=us,de\nXKBVARIANT="mac,mac"\n', 'xkb:us+mac'),
                   ('# XKBLAYOUT="fr"\nBACKSPACE="guess"\n', '')):
    if mk.system_layout(text) != want:
        failed += 1
        print(f'FAIL system_layout({text!r}) is {mk.system_layout(text)!r}, not {want!r}')
for args, want in ((('de', ''), ('de', 'mac')), (('us', ''), ('us', 'mac')), (('gb', ''), ('gb', 'mac')),
                   (('de', 'nodeadkeys'), ('de', 'mac_nodeadkeys')),
                   (('us,de', ','), ('us,de', 'mac,mac')), (('fr,de', ''), ('fr,de', ',mac')),
                   (('fr', ''), None), (('de', 'mac'), None), (('us', 'intl'), None), (('', ''), None)):
    if mk.mac_system(*args) != want:
        failed += 1
        print(f'FAIL mac_system{args} is {mk.mac_system(*args)!r}, not {want!r}')


def xkb_typer():
    """typed(source, mods, key): what GNOME's libxkbcommon types for KEY with the modifier keys
    MODS held, or None without libxkbcommon."""
    import ctypes as C
    try:
        x = C.CDLL('libxkbcommon.so.0')
    except OSError:
        return None

    class Names(C.Structure):
        _fields_ = [(n, C.c_char_p) for n in ('rules', 'model', 'layout', 'variant', 'options')]
    x.xkb_context_new.restype = x.xkb_keymap_new_from_names.restype = C.c_void_p
    x.xkb_keymap_new_from_names.argtypes = [C.c_void_p, C.POINTER(Names), C.c_int]
    x.xkb_state_new.restype = C.c_void_p
    x.xkb_state_new.argtypes = x.xkb_state_unref.argtypes = [C.c_void_p]
    x.xkb_keymap_unref.argtypes = [C.c_void_p]
    x.xkb_state_update_key.argtypes = [C.c_void_p, C.c_uint32, C.c_int]
    x.xkb_state_key_get_utf8.argtypes = [C.c_void_p, C.c_uint32, C.c_char_p, C.c_size_t]
    ctx = x.xkb_context_new(0)

    def typed(source, mods, key):
        layout, _, variant = source.partition('+')
        names = Names(b'evdev', b'pc105', layout.encode(), variant.encode(), b'')
        keymap = x.xkb_keymap_new_from_names(ctx, C.byref(names), 0)
        state = x.xkb_state_new(keymap)
        for m in mods:
            x.xkb_state_update_key(state, K[m] + 8, 1)       # XKB keycodes are Linux's + 8
        buf = C.create_string_buffer(16)
        x.xkb_state_key_get_utf8(state, key + 8, buf, 16)
        x.xkb_state_unref(state)
        x.xkb_keymap_unref(keymap)
        return buf.value.decode()
    return typed


# The real layouts, if libxkbcommon is here: each switch keeps every printed key (or moves
# exactly the ones MOVED says), and Option (LEVEL3) gives the Mac's characters, the right Alt
# the same. What a Mac of that language types with Option:
GERMAN_MAC = ((['LEVEL3'], 'L', '@'), (['LEVEL3'], '5', '['), (['LEVEL3'], '6', ']'),
              (['LEVEL3'], '8', '{'), (['LEVEL3'], '9', '}'), (['LEVEL3'], '7', '|'),
              (['LEVEL3', 'LEFTSHIFT'], '7', '\\'), (['LEVEL3'], 'E', '€'),
              (['RIGHTALT'], 'L', '@'))
ENGLISH_MAC = ((['LEVEL3'], '2', '™'), (['LEVEL3'], 'G', '©'), (['LEVEL3'], 'S', 'ß'),
               (['LEVEL3'], '8', '•'), (['LEVEL3'], 'R', '®'), (['LEVEL3', 'LEFTSHIFT'], '2', '€'),
               (['RIGHTALT'], '2', '™'))
UK_MAC = ((['LEVEL3'], '2', '€'), (['LEVEL3'], '3', '#'), (['RIGHTALT'], '3', '#'))
MAC_TYPES = {'de': GERMAN_MAC, 'at': GERMAN_MAC, 'us': ENGLISH_MAC, 'gb': UK_MAC}
# Keys a layout's PC keyboards don't have: US keyboards have none between left Shift and Z
NO_KEY = {'us': {K['102ND']}}
# Keys that move to where a Mac of that language has them ((key, Shift): what it types then)
MOVED = {'gb': {('2', True): '@', ('APOSTROPHE', True): '"', ('GRAVE', False): '§',
                ('GRAVE', True): '±', ('BACKSLASH', False): '\\', ('BACKSLASH', True): '|',
                ('102ND', False): '`', ('102ND', True): '~'}}
typed = xkb_typer()
if typed is None:
    print('skipped the layout checks: no libxkbcommon')
else:
    for pc, mac in mk.MAC_LAYOUTS.items():
        for code in sorted(mk.TYPING - NO_KEY.get(pc, set())):
            for mods in ([], ['LEFTSHIFT']):
                was, now = typed(pc, mods, code), typed(mac, mods, code)
                want = MOVED.get(pc, {}).get((name(code), bool(mods)), was)
                if now != want:
                    failed += 1
                    print(f'FAIL {pc} -> {mac}: {"+".join(mods + [name(code)])} types {was!r}, '
                          f'then {now!r}{"" if want == was else f", not {want!r}"}')
        # Numpad Enter: a Level 3 key in the layout, sent as Enter by the service
        if (typed(mac, [], K['KPENTER']) == '') != ('xkb:' + mac in mk.KPENTER_IS_LEVEL3):
            failed += 1
            print(f'FAIL {mac}: numpad Enter is {"not " * (typed(mac, [], K["KPENTER"]) != "")}'
                  'Level 3 there; KPENTER_IS_LEVEL3 should say so')
        lang = pc.split('+')[0]
        if lang not in MAC_TYPES:
            failed += 1
            print(f'FAIL {mac}: add what Option types on a {lang} Mac to MAC_TYPES')
        for mods, key, want in MAC_TYPES.get(lang, ()):
            got = typed(mac, mods, K[key])
            if got != want:
                failed += 1
                print(f'FAIL {mac}: {"+".join(mods + [key])} types {got!r}, a Mac {want!r}')

# ---- the power button: press locks, Ctrl+press powers off -------------------------------------
now = [100.0]
pb = mk.PowerButton(clock=lambda: now[0])
for what, ctrl, want in (('a press locks', False, 'lock'), ('a repeat of it is ignored', False, None),
                         ('Ctrl+press, right after: still the same press', True, None)):
    if pb.press(ctrl) != want:
        failed += 1
        print(f'FAIL power button: {what}')
now[0] += 5
for what, ctrl, want in (('later, Ctrl+press asks to power off', True, 'off'),
                         ('and a press locks again', False, 'lock')):
    now[0] += 5
    if pb.press(ctrl) != want:
        failed += 1
        print(f'FAIL power button: {what}')

import stat
import tempfile
mk.log = lambda *a: None      # the refused writes below are expected
with tempfile.TemporaryDirectory() as run:
    def power_file(uid=1000):
        return os.path.join(run, str(uid), 'macish-keys', 'power')

    def told(uid=1000):
        try:
            with open(power_file(uid)) as f:
                return f.read().split()
        except OSError:
            return None

    mk.tell_session(1000, 'lock', run=run)
    if told() is not None:
        failed += 1
        print('FAIL power button: nothing to tell before the session has its folder')
    os.makedirs(os.path.dirname(power_file()))
    mk.tell_session(1000, 'lock', run=run)
    got = told()
    if not (got and got[0] == 'lock' and got[1].isdigit()):
        failed += 1
        print(f'FAIL power button: tells the session "lock <number>", wrote {got!r}')
    first = got[1] if got else None
    mk.tell_session(1000, 'off', run=run)
    got = told()
    if not (got and got[0] == 'off' and got[1] != first):
        failed += 1
        print(f'FAIL power button: a second press is a new message, wrote {got!r}')

    # The folder is the user's: a link must never make root write somewhere else
    victim = os.path.join(run, 'victim')
    with open(victim, 'w') as f:
        f.write('keep me')
    os.remove(power_file())
    os.symlink(victim, power_file())
    mk.tell_session(1000, 'lock', run=run)
    with open(victim) as f:
        if f.read() != 'keep me':
            failed += 1
            print('FAIL power button: followed a link in place of the file')
    elsewhere = os.path.join(run, 'elsewhere')
    os.makedirs(elsewhere)
    os.makedirs(os.path.join(run, '1001'))
    os.symlink(elsewhere, os.path.join(run, '1001', 'macish-keys'))
    mk.tell_session(1001, 'lock', run=run)
    if os.listdir(elsewhere):
        failed += 1
        print('FAIL power button: followed a link in place of the folder')
    os.makedirs(os.path.join(run, '1002', 'macish-keys'))
    os.mkfifo(power_file(1002))
    mk.tell_session(1002, 'lock', run=run)        # must return, not hang on a pipe
    if not stat.S_ISFIFO(os.stat(power_file(1002)).st_mode):
        failed += 1
        print('FAIL power button: replaced something that is no plain file')

# A key with no name of its own, pressed in the app switcher, doesn't stop the service
kb = Kb()
kb.press('LEFTALT', 'TAB')
expect('app switcher: F1 passes', kb.t.feed(59, 1) + kb.t.feed(59, 0), '+59 -59')
kb.release('TAB', 'LEFTALT')
expect_clean('switcher, F1', kb)

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
