# SCA.LSP — LSP-Server, Inkrement 0 (Diagnostics-only)

Minimaler Language-Server-Protocol-Server als **vierter Consumer** der
SCA-Engine-Facade `uEngineApi` (neben IDE-Plugin, CLI und Form-GUI).
Konzeptgrundlage: `Doku_06_CLI_LSP_Reporting.md`, LSP-Abschnitt
(Konzept_LSP.md / Konzept_LspSchicht.md).

## Was Inkrement 0 kann

| Bereich | Umfang |
|---|---|
| Transport | stdio, Content-Length-Framing (`uLspStdio`) |
| Protokoll | JSON-RPC 2.0 minimal (`uLspProtocol`): `initialize`, `initialized`, `shutdown`, `exit`, `textDocument/didOpen`, `textDocument/didChange` (Full-Sync), `textDocument/didClose`, `textDocument/publishDiagnostics` |
| Analyse | Buffer-Text → `TAnalysisSession.Run` mit `ssSource` (In-Memory-Pfad der Engine, volle Per-File-Pipeline inkl. Suppression), Profil `ide-fast` (`uLspDiagnostics`) |
| Mapping | `TLeakFinding` → LSP-Diagnostic: Zeile 1-basiert → 0-basiert, `severity` (lsError→1, lsWarning→2, lsHint→4), `code` = `ResolvedRuleId` (SCAxxx), `source` = `sca`, `message` = Befundmeldung |

**Bewusst NICHT enthalten** (spätere Phasen laut Doku_06): Debounce für
`didChange`, Cancellation, `workspace/configuration`, CodeActions/QuickFixes,
Hover, Workspace-Scan, Pull-Diagnostics.

## Bekannte Lücke E3 — Spaltenfeld (dokumentiert, nicht gelöst)

`TLeakFinding` hat **kein Spaltenfeld** (`StartCol`/`EndCol`/`EndLine`) —
Engine-Änderung **E3** in Doku_06, dort als größter Einzel-Hebel für die
LSP-Qualität geführt (nützt auch SARIF `region.startColumn` und die
Plugin-Overlays). Bis E3 umgesetzt ist:

* Spalte konstant **1** (LSP `character: 0`),
* Range = **ganze Zeile** (`end.character = 2147483647`, der Client clippt
  ans Zeilenende — übliche LSP-Konvention).

Die Stelle ist in `sources/uLspDiagnostics.pas` mit `TODO E3` markiert.
Achtung bei der späteren Umsetzung: LSP < 3.17 erwartet
UTF-16-Code-Unit-Offsets.

## Bauen (nur in der IDE — kein msbuild/dcc32 auf dieser Maschine)

Das Projekt ist wie `SCA.CLI.Demo` als **Package-Consumer** aufgesetzt
(`DCC_UsePackage SCA.Engine` — keine Engine-Quelltexte im Suchpfad).
Der Architektur-Entscheid Static-Link vs. Package ist laut Doku_06 (Punkt 11)
offen; für die Distribution spricht die Doku für Static-Link — bei Bedarf
das Projekt später umstellen.

1. Delphi 12 öffnen, `StaticCodeAnalyser.d12.groupproj` laden (oder
   `SCA.LSP\SCA.LSP.dproj` einzeln öffnen und der Gruppe hinzufügen).
2. Zuerst **SCA.Engine** (Package) bauen — dieselbe Plattform/Config wie
   SCA.LSP, damit die `SCA.Engine.bpl` gefunden wird (Pfad ggf. in den
   IDE-Package-Suchpfad aufnehmen bzw. bpl neben die Exe legen).
3. Dann **SCA.LSP** bauen → `SCA.LSP\<Platform>\<Config>\SCA.LSP.exe`.

## Test per Pipe (ohne Editor)

Der Server spricht LSP über stdin/stdout. Kleinster Rauchtest mit Python
(schreibt korrekt geframte Requests, liest die Antworten):

```python
# test_lsp.py  --  python test_lsp.py .\Win64\Release\SCA.LSP.exe
import json, subprocess, sys

exe = sys.argv[1]
p = subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE)

def send(msg):
    body = json.dumps(msg).encode("utf-8")
    p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    p.stdin.flush()

def recv():
    length = 0
    while True:
        line = p.stdout.readline().strip()
        if not line: break
        if line.lower().startswith(b"content-length:"):
            length = int(line.split(b":")[1])
    return json.loads(p.stdout.read(length))

src = "unit U1;\ninterface\nimplementation\nprocedure P;\nvar o: TObject;\nbegin\n  o := TObject.Create;\nend;\nend.\n"

send({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}})
print("initialize ->", recv())
send({"jsonrpc":"2.0","method":"initialized","params":{}})
send({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{
    "textDocument":{"uri":"file:///c:/tmp/U1.pas","languageId":"pascal","version":1,"text":src}}})
print("diagnostics ->", json.dumps(recv(), indent=2))
send({"jsonrpc":"2.0","id":2,"method":"shutdown","params":None})
print("shutdown ->", recv())
send({"jsonrpc":"2.0","method":"exit"})
print("exit code:", p.wait())
```

Erwartung: `initialize` liefert `textDocumentSync {openClose, change:1}` +
`serverInfo {name: "sca-lsp"}`; nach `didOpen` kommt eine
`textDocument/publishDiagnostics`-Notification mit mindestens einem
SCA001-Diagnostic (Memory-Leak `o`) auf der `Create`-Zeile, `character 0`
(E3-Lücke, s. o.); `exit` nach `shutdown` beendet mit Exit-Code 0.

Hinweise:

* stdout gehört exklusiv dem Protokoll; Fehler-/Logtexte kommen auf stderr
  (`[sca-lsp] ...`).
* Der Server ist single-threaded und analysiert synchron pro
  `didOpen`/`didChange` (kein Debounce in Inkrement 0) — bei sehr großen
  Dateien entsprechend spürbar.
* Ein `didChange` ohne vorheriges `didOpen` funktioniert ebenfalls
  (der Server hält keinen Dokument-Store; Full-Sync trägt immer den
  kompletten Text).
