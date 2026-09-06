unit uWorkbenchStyle;

// Das WORKBENCH-Designsystem beider HTML-Exporte als EINE CSS-Quelle
// (Nutzerauftrag 2026-09-07: "alles soll sich gleich anfuehlen").
// Extrahiert aus der Detector-Info-Seite; Vertrag und Farbwelten:
// Konzept_WorkbenchDesignsystem_2026-09-07.md (lokal).
//
// INHALT: nur die GETEILTEN Bausteine - Design-Tokens (:root),
// Grundtypografie, dunkler Seitenkopf, Karten-/Badge-/Pill-/Chip-/
// Kachel-Optik, Codekarten (untereinander, mit Copy-Titelzeile) und
// der Focus-Ring. SEITENSPEZIFISCHES (IDs wie #suche/#drawer, Tabellen-
// Layouts, Chips-Leisten, Media-Queries) bleibt beim jeweiligen
// Generator - diese Unit kennt keine Seitenstruktur.
//
// THEME-VERTRAG: die Komponenten-Regeln haengen an den :root-Tokens.
// Ein Konsument mit Themes (der Findings-Report: data-theme dark/sepia)
// ueberschreibt ZUERST die Tokens je Theme und behaelt Spezialregeln
// nur, wo Tokens nicht reichen.

interface

type
  TWorkbenchStyle = class
  public
    // Der geteilte CSS-Kern OHNE <style>-Klammer - der Aufrufer bettet
    // ihn in seinen Style-Block ein (Reihenfolge: Basis ZUERST, dann
    // seitenspezifische Regeln, damit die Seite gezielt verfeinern kann).
    class function BasisCss: string; static;
  end;

implementation

uses
  System.SysUtils;

class function TWorkbenchStyle.BasisCss: string;
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    // ---- Design-Tokens ------------------------------------------------
    SB.AppendLine(':root{--akzent:#1a5da6;--rand:#dfe5ec;--karte:#fff;'
      + '--grund:#f5f7fa;--tinte:#1c2733;--dezent:#5c6b7a;}');
    SB.AppendLine('*{box-sizing:border-box;}');
    SB.AppendLine('body{font-family:Segoe UI,Arial,sans-serif;margin:0;'
      + 'background:var(--grund);color:var(--tinte);}');
    SB.AppendLine('.mono{font-family:Consolas,monospace;}');
    SB.AppendLine('a{color:var(--akzent);}');
    // ---- Dunkler Seitenkopf (bewusst kein Token-Fall, s. Konzept) -----
    SB.AppendLine('header.kopf{background:#20303f;color:#f2f6fa;'
      + 'padding:14px 20px;}');
    SB.AppendLine('header.kopf h1{font-size:1.35em;margin:0;}');
    SB.AppendLine('header.kopf .sub{color:#b9c6d2;margin-top:2px;'
      + 'font-size:0.92em;max-width:70em;}');
    // ---- Badges / Pills / Chips ---------------------------------------
    SB.AppendLine('.badge{display:inline-block;border-radius:5px;'
      + 'padding:1px 8px;font-size:0.86em;border:1px solid transparent;'
      + 'white-space:nowrap;}');
    SB.AppendLine('.badge.sev-err{background:#fdecea;color:#9c2317;'
      + 'border-color:#f2c4bf;}');
    SB.AppendLine('.badge.sev-warn{background:#fef4e5;color:#8a5a00;'
      + 'border-color:#f1d9ad;}');
    SB.AppendLine('.badge.sev-hint{background:#eaf3fd;color:#1a5da6;'
      + 'border-color:#c4dbf2;}');
    SB.AppendLine('.badge.typ{background:#f0f1f4;color:#3d4a58;'
      + 'border-color:var(--rand);}');
    SB.AppendLine('.badge.typ.vuln,.badge.typ.hotspot{background:#f3ecfb;'
      + 'color:#5b2d91;border-color:#dcc9f0;}');
    SB.AppendLine('.badge.konf{background:#f0f1f4;color:#3d4a58;'
      + 'border-color:var(--rand);font-size:0.8em;}');
    SB.AppendLine('.pill{display:inline-block;border-radius:999px;'
      + 'padding:1px 10px;font-size:0.84em;}');
    SB.AppendLine('.pill.an{background:#e7f4e8;color:#1d6b2a;}');
    SB.AppendLine('.pill.aus{background:#f4e9e8;color:#8f2d24;}');
    SB.AppendLine('.chip{display:inline-block;background:#eef2f6;'
      + 'border-radius:4px;padding:0 6px;margin:1px 3px 1px 0;'
      + 'font-size:0.8em;color:#3d4a58;}');
    SB.AppendLine('.chip.cwe{background:#f3ecfb;color:#5b2d91;}');
    // ---- Kachel-Dashboard ---------------------------------------------
    SB.AppendLine('.dash{display:flex;gap:10px;flex-wrap:wrap;'
      + 'margin:0 0 12px 0;}');
    SB.AppendLine('.kachel{background:var(--karte);border:1px solid '
      + 'var(--rand);border-radius:8px;padding:8px 14px;min-width:104px;'
      + 'box-shadow:0 1px 2px rgba(16,32,48,0.06);}');
    SB.AppendLine('.kachel .zahl{font-size:1.35em;font-weight:600;}');
    SB.AppendLine('.kachel .wofuer{color:var(--dezent);'
      + 'font-size:0.85em;}');
    // ---- Code ---------------------------------------------------------
    SB.AppendLine('pre{background:#23272e;color:#e6e6e6;margin:0;'
      + 'padding:8px;overflow-x:auto;font-size:0.88em;'
      + 'font-family:Consolas,monospace;}');
    // Codekarten UNTEREINANDER (Nutzerentscheid 07.09., beide Seiten):
    // erst die schlechte, darunter die gute Karte.
    SB.AppendLine('.codekarten{display:flex;flex-direction:column;'
      + 'gap:10px;}');
    SB.AppendLine('.codekarte{border:1px solid '
      + 'var(--rand);border-radius:8px;overflow:hidden;}');
    SB.AppendLine('.codekarte .karte-titel{display:flex;'
      + 'justify-content:space-between;align-items:center;'
      + 'padding:4px 8px;font-size:0.86em;}');
    SB.AppendLine('.codekarte.schlecht .karte-titel{background:#fdecea;'
      + 'color:#9c2317;}');
    SB.AppendLine('.codekarte.gut .karte-titel{background:#e7f4e8;'
      + 'color:#1d6b2a;}');
    SB.AppendLine('.karte{border:1px solid var(--rand);border-radius:8px;'
      + 'padding:8px 10px;margin-top:10px;background:#fbfcfe;}');
    SB.AppendLine('button.copy{border:1px solid var(--rand);'
      + 'background:var(--karte);border-radius:5px;cursor:pointer;'
      + 'font-size:0.8em;padding:1px 8px;}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
