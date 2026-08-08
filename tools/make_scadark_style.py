# -*- coding: utf-8 -*-
"""Windows10Dark.vsf -> SCADark.vsf mit VS-Code-Dark-Modern-Palette.

Format (Vcl.StyleAPI.pas): 'VCL_STYLE 2.0' + zlib; Farben/Fonts als
String-Tripel [len]{utf16 name} [1]':' [len]{utf16 wert}; TColor = $00BBGGRR.
"""
import io
import re
import zlib

SRC = ('C:/Program Files (x86)/Embarcadero/Studio/23.0/Redist/styles/vcl/'
       'Windows10Dark.vsf')
DST = 'd:/git-demos/delphi/StaticCodeAnalyser/StaticCodeAnalyserForm/styles/SCADark.vsf'

# VS Code Dark Modern (RGB) -> Delphi-Hexstring ($00BBGGRR)
CHROME  = '$00181818'   # #181818 Title/Side/Activity/Status/Tabs
CONTENT = '$001F1F1F'   # #1F1F1F Editor/Listen/Grid
WIDGET  = '$00262525'   # #252526 Hover/Hint/Widgets
INPUT_  = '$00313131'   # #313131 Eingabefelder/Buttons
HOT     = '$003C3C3C'   # #3C3C3C Hover auf Eingaben
BORDER  = '$002B2B2B'   # #2B2B2B Raender
TEXT    = '$00CCCCCC'   # #CCCCCC Standardtext

STYLE_COLORS = {
    'Border': BORDER,
    'CategoryButtons': CHROME,
    'CategoryPanelGroup': CHROME,
    'ComboBox': INPUT_,
    'ComboBoxDisabled': WIDGET,
    'ButtonNormal': INPUT_,
    'ButtonHot': HOT,
    'ButtonFocused': INPUT_,
    'ButtonDisabled': WIDGET,
    'Edit': INPUT_,
    'EditDisabled': WIDGET,
    'Grid': CONTENT,
    'GenericGradientBase': WIDGET,
    'GenericGradientEnd': CONTENT,
    'HintGradientBase': WIDGET,
    'HintGradientEnd': WIDGET,
    'ListBox': CONTENT,
    'ListBoxDisabled': WIDGET,
    'ListView': CONTENT,
    'Panel': CHROME,
    'PanelDisabled': CHROME,
    'TreeView': CONTENT,
    'Window': CONTENT,
    'Splitter': BORDER,
    'CategoryButtonsGradientBase': CHROME,
    'ToolBarGradientBase': CHROME,
    'ToolBarGradientEnd': CHROME,
    'GenericBackground': CHROME,
    'AlternatingRowBackground': WIDGET,
    'clActiveBorder': BORDER,
    'clActiveCaption': CHROME,
    'clBtnFace': CHROME,
    'clBtnText': TEXT,
    'clCaptionText': TEXT,
    'clInactiveCaption': CONTENT,
    'clInactiveCaptionText': TEXT,
    'clInfoBk': WIDGET,
    'clInfoText': TEXT,
    'clMenu': CONTENT,
    'clMenuText': TEXT,
    'clScrollBar': CONTENT,
    'clWindow': CONTENT,
    'clWindowText': TEXT,
}

NEW_NAME = 'SCA VSDark'


def u16(s):
    return s.encode('utf-16-le')


def entry(name, value):
    return (len(name).to_bytes(4, 'little') + u16(name) +
            (1).to_bytes(4, 'little') + u16(':') +
            len(value).to_bytes(4, 'little') + u16(value))


raw = io.open(SRC, 'rb').read()
assert raw[:13] == b'VCL_STYLE 2.0'
data = zlib.decompress(raw[13:])
orig_len = len(data)

# 1. Farbwerte ersetzen: bestehendes Tripel exakt matchen (Name + ':' +
#    beliebiger Wert), durch neues Tripel ersetzen. Jeder Name muss genau
#    einmal vorkommen - sonst Abbruch statt stillem Teilpatch.
for name, newval in STYLE_COLORS.items():
    pre = (len(name).to_bytes(4, 'little') + u16(name) +
           (1).to_bytes(4, 'little') + u16(':'))
    idx = data.find(pre)
    assert idx >= 0, 'Name fehlt: %s' % name
    assert data.find(pre, idx + 1) < 0, 'Name mehrfach: %s' % name
    vpos = idx + len(pre)
    vlen = int.from_bytes(data[vpos:vpos + 4], 'little')
    assert 0 < vlen <= 64, (name, vlen)
    data = data[:idx] + entry(name, newval) + data[vpos + 4 + 2 * vlen:]

# 2. Font-Farben: weisses 255,255,255 in Fontwert-Strings -> 204,204,204
#    (VS-Code-Text). Nur INNERHALB von Font-Tripeln (Wert enthaelt Kommas).
FONT_VAL = re.compile(
    (',255,255,255').encode('utf-16-le').replace(b'\\', b'\\\\'))
count = 0


def font_sub(m):
    global count
    count += 1
    return u16(',204,204,204')


data = FONT_VAL.sub(font_sub, data)
print('Font-Weiss ersetzt: %d' % count)

# 3. Interner Style-Name (erster String im Strom).
nlen = int.from_bytes(data[0:4], 'little')
old_name = data[4:4 + 2 * nlen].decode('utf-16-le')
print('Interner Name: %r -> %r' % (old_name, NEW_NAME))
data = (len(NEW_NAME).to_bytes(4, 'little') + u16(NEW_NAME) +
        data[4 + 2 * nlen:])

out = b'VCL_STYLE 2.0' + zlib.compress(data, 9)
io.open(DST, 'wb').write(out)
print('geschrieben: %s (%d Bytes, innen %d -> %d)' %
      (DST, len(out), orig_len, len(data)))

# Verifikation: Roundtrip + neue Werte tatsaechlich drin.
chk = zlib.decompress(io.open(DST, 'rb').read()[13:])
for name, newval in STYLE_COLORS.items():
    assert entry(name, newval) in chk, 'Patch fehlt: %s' % name
assert chk[4:4 + 2 * len(NEW_NAME)].decode('utf-16-le') == NEW_NAME
assert FONT_VAL.search(chk) is None
print('VERIFIKATION OK: alle %d Farben + Name + Fonts gepatcht.'
      % len(STYLE_COLORS))
