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

# An VS Code Dark Modern angelehnt (RGB) -> Delphi-Hexstring ($00BBGGRR).
# Palette v2 (2026-08-08): Chrome von #181818 auf #252526 angehoben -
# das Original-#181818 wirkte auf realen Monitoren schlicht schwarz
# (User-Abnahme v0.9.13); die Hierarchie Chrome > Inhalt bleibt, nur
# eine Stufe heller.
CHROME  = '$00262525'   # #252526 Panels/Toolbar/Caption/BtnFace
CONTENT = '$001F1F1F'   # #1F1F1F Grid/Listen/Menue
WIDGET  = '$00302D2D'   # #2D2D30 Hover/Hint/Disabled/AltRows
INPUT_  = '$00313131'   # #313131 Eingabefelder/Buttons
HOT     = '$003C3C3C'   # #3C3C3C Hover auf Eingaben
BORDER  = '$003C3C3C'   # #3C3C3C Raender (auf #252526 noch sichtbar)
TEXT    = '$00CCCCCC'   # #CCCCCC Standardtext

STYLE_COLORS = {
    # cl3DDkShadow zeichnet u.a. die 1px-Header-Trennlinie des Grids -
    # der Style mappt es im Original auf clBlack (Workflow-Audit
    # 2026-08-08), auf #252526-Chrome soll es der Rand-Ton sein.
    'cl3DDkShadow': BORDER,
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

# 3. BITMAPS: der Form-Hintergrund kommt NICHT aus der Farbtabelle,
#    sondern aus dem bitmap-gezeichneten Window-Client-Objekt der
#    style.png - bei Windows10Dark reines Schwarz. Der Farb-Patch oben
#    erreicht Bitmaps nicht (Workflow-Audit 2026-08-08: 'bg is black'
#    trotz Palette v2). TseBitmap.SaveToStream (Vcl.StyleBitmap.pas)
#    legt jedes Bitmap als [Name][W:Int32][H:Int32][W*H*4 BGRA roh] ab -
#    wir heben in ALLEN Bitmaps jedes OPAKE Reinschwarz auf den
#    Chrome-Ton (Titelleisten-Glyphen sind hell und bleiben unberuehrt;
#    fast-schwarze Antialias-Kanten bleiben bewusst stehen).
BLACK_PX  = b'\x00\x00\x00\xff'                  # BGRA opak #000000
CHROME_PX = bytes((0x26, 0x25, 0x25, 0xff))      # BGRA opak #252526

bm_count = 0
px_total = 0
scan = 0
while True:
    hit = data.find('.png'.encode('utf-16-le'), scan)
    if hit < 0:
        break
    scan = hit + 2
    # Rueckwaerts den String-Anfang suchen: [len:Int32][utf16-Name].
    name_end = hit + len('.png'.encode('utf-16-le'))
    found = False
    for l in range(4, 65):
        s = name_end - 2 * l
        if s >= 4 and data[s - 4:s] == l.to_bytes(4, 'little'):
            found = True
            break
    if not found:
        continue
    w = int.from_bytes(data[name_end:name_end + 4], 'little')
    h = int.from_bytes(data[name_end + 4:name_end + 8], 'little')
    if not (0 < w < 4096 and 0 < h < 4096):
        continue
    p0 = name_end + 8
    p1 = p0 + w * h * 4
    if p1 > len(data):
        continue
    pixels = bytearray(data[p0:p1])
    n = 0
    for i in range(0, len(pixels), 4):
        if pixels[i:i + 4] == BLACK_PX:
            pixels[i:i + 4] = CHROME_PX
            n += 1
    data = data[:p0] + bytes(pixels) + data[p1:]
    bm_count += 1
    px_total += n
    print('Bitmap %dx%d: %d Schwarz-Pixel -> Chrome' % (w, h, n))
    scan = p1
assert bm_count >= 1, 'kein Style-Bitmap gefunden'
assert px_total > 5000, 'verdaechtig wenige Schwarz-Pixel: %d' % px_total
print('Bitmaps gesamt: %d, Pixel gehoben: %d' % (bm_count, px_total))

# 4. Interner Style-Name (erster String im Strom).
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
