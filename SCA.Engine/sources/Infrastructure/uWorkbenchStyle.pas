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

    // Das ANPINNEN des Kopfes samt seiner zwei Zustaende, OHNE
    // <style>-Klammer - einzubinden NACH BasisCss, und NUR von Seiten,
    // die auch KopfVerhaltenJs einbinden.
    //
    // WARUM NICHT IN BasisCss: BasisCss hat einen Konsumenten mehr als
    // das Kopf-Verhalten - den klassischen CLI-Report (--report-html).
    // Der traegt kein Kopf-Skript und pinnt seine eigenen
    // Spaltenkoepfe mit top:0 ans Fenster. Als das Anpinnen in
    // BasisCss lag, klemmte dort ploetzlich der Kopfbalken permanent
    // oben, und die Spaltenkoepfe verschwanden beim Scrollen dahinter
    // (Chargen-Review 10.09., Blocker). Optik teilen alle vier
    // Konsumenten; VERHALTEN teilen nur die, die es bestellt haben.
    class function KopfAngepinntCss: string; static;

    // Das Verhalten des angepinnten Kopfes, OHNE <script>-Klammer.
    //
    // WARUM VERHALTEN IN EINER STYLE-UNIT: der zusammenfahrende Kopf
    // ist zur Haelfte CSS (die beiden Zustaende, KopfAngepinntCss) und
    // zur Haelfte die Handvoll Zeilen, die zwischen ihnen umschaltet.
    // Die Zustaende stehen hier; die Umschaltung woanders zu haben
    // hiesse, dass ein Aufraeumen an einer Stelle die andere still
    // kaputtmacht. Beide Workbench-Seiten binden denselben Baustein
    // ein - immer PAARIG mit KopfAngepinntCss.
    //
    // Der Aufrufer haengt das Ergebnis in seinen eigenen
    // <script>-Block, nach dem <header class="kopf">.
    class function KopfVerhaltenJs: string; static;
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
    // FLAECHEN-TOKENS (seit 07.09.): die Farben der Badges, Pills,
    // Chips, Codekarten-Titel und Karten standen frueher als feste
    // Hex-Werte in den Regeln - alle fuer HELLE Flaechen gebaut.
    // Im Dark-Theme leuchteten sie als grelle Pastellflecken, weil
    // ein Theme nur die sechs Grund-Tokens drehte. Jetzt ist JEDE
    // Farbflaeche ein Token: ein Theme bleibt EIN Ueberschreibungs-
    // block, und niemand muss die Einzelregeln nachziehen.
    // Die Werte hier sind exakt die bisherigen - der helle Modus
    // sieht unveraendert aus.
    SB.AppendLine(':root{'
      + '--f-err-bg:#fdecea;--f-err-fg:#9c2317;--f-err-br:#f2c4bf;'
      + '--f-warn-bg:#fef4e5;--f-warn-fg:#8a5a00;--f-warn-br:#f1d9ad;'
      + '--f-info-bg:#eaf3fd;--f-info-fg:#1a5da6;--f-info-br:#c4dbf2;'
      + '--f-neutral-bg:#f0f1f4;--f-neutral-fg:#3d4a58;'
      + '--f-lila-bg:#f3ecfb;--f-lila-fg:#5b2d91;--f-lila-br:#dcc9f0;'
      + '--f-gut-bg:#e7f4e8;--f-gut-fg:#1d6b2a;'
      + '--f-aus-bg:#f4e9e8;--f-aus-fg:#8f2d24;'
      + '--f-chip-bg:#eef2f6;'
      + '--f-flaeche:#fbfcfe;'
      + '--f-code-bg:#23272e;--f-code-fg:#e6e6e6;}');
    SB.AppendLine('*{box-sizing:border-box;}');
    SB.AppendLine('body{font-family:Segoe UI,Arial,sans-serif;margin:0;'
      + 'background:var(--grund);color:var(--tinte);}');
    SB.AppendLine('.mono{font-family:Consolas,monospace;}');
    SB.AppendLine('a{color:var(--akzent);}');
    // FORMULARELEMENTE ERBEN NICHT. Ein input, select oder button
    // nimmt weder Schriftfamilie noch Textfarbe vom Elternteil - der
    // Browser setzt seine eigenen Vorgaben, und die sind auf HELLEN
    // Grund gerechnet. Im Dunkel-Thema stand deshalb schwarzer Text
    // auf dunklem Feld: das Suchfeld war praktisch unlesbar (Nicos
    // Befund 09.09.).
    //
    // Die Regel steht hier und nicht bei einer Seite, weil alle drei
    // dieselben Steuerelemente tragen. Sie setzt NUR Schrift und
    // Farbe; Rahmen, Polster und Rundung bleiben Sache der Seite.
    SB.AppendLine('input,select,button,textarea{font:inherit;'
      + 'color:var(--tinte);}');
    // Der Platzhalter gedaempft, aber lesbar - die Browser-Vorgabe
    // ist auf dunklem Grund oft kaum sichtbar.
    SB.AppendLine('::placeholder{color:var(--dezent);opacity:1;}');
    // ---- Dunkler Seitenkopf (bewusst kein Token-Fall, s. Konzept) -----
    // NUR die Optik. Das Anpinnen samt der zwei Zustaende liegt in
    // KopfAngepinntCss - der klassische CLI-Report bindet BasisCss ein,
    // will aber keinen klemmenden Kopf (Begruendung an der Deklaration;
    // Chargen-Review 10.09., Blocker).
    SB.AppendLine('header.kopf{background:#20303f;color:#f2f6fa;'
      + 'padding:14px 20px;}');
    SB.AppendLine('header.kopf h1{font-size:1.35em;margin:0;}');
    SB.AppendLine('header.kopf .sub{color:#b9c6d2;margin-top:2px;'
      + 'font-size:0.92em;max-width:70em;}');
    // ---- Badges / Pills / Chips ---------------------------------------
    SB.AppendLine('.badge{display:inline-block;border-radius:5px;'
      + 'padding:1px 8px;font-size:0.86em;border:1px solid transparent;'
      + 'white-space:nowrap;}');
    SB.AppendLine('.badge.sev-err{background:var(--f-err-bg);'
      + 'color:var(--f-err-fg);border-color:var(--f-err-br);}');
    SB.AppendLine('.badge.sev-warn{background:var(--f-warn-bg);'
      + 'color:var(--f-warn-fg);border-color:var(--f-warn-br);}');
    SB.AppendLine('.badge.sev-hint{background:var(--f-info-bg);'
      + 'color:var(--f-info-fg);border-color:var(--f-info-br);}');
    SB.AppendLine('.badge.typ{background:var(--f-neutral-bg);'
      + 'color:var(--f-neutral-fg);border-color:var(--rand);}');
    SB.AppendLine('.badge.typ.vuln,.badge.typ.hotspot{'
      + 'background:var(--f-lila-bg);color:var(--f-lila-fg);'
      + 'border-color:var(--f-lila-br);}');
    SB.AppendLine('.badge.konf{background:var(--f-neutral-bg);'
      + 'color:var(--f-neutral-fg);border-color:var(--rand);'
      + 'font-size:0.8em;}');
    SB.AppendLine('.pill{display:inline-block;border-radius:999px;'
      + 'padding:1px 10px;font-size:0.84em;}');
    SB.AppendLine('.pill.an{background:var(--f-gut-bg);'
      + 'color:var(--f-gut-fg);}');
    SB.AppendLine('.pill.aus{background:var(--f-aus-bg);'
      + 'color:var(--f-aus-fg);}');
    SB.AppendLine('.chip{display:inline-block;'
      + 'background:var(--f-chip-bg);'
      + 'border-radius:4px;padding:0 6px;margin:1px 3px 1px 0;'
      + 'font-size:0.8em;color:var(--f-neutral-fg);}');
    SB.AppendLine('.chip.cwe{background:var(--f-lila-bg);'
      + 'color:var(--f-lila-fg);}');
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
    SB.AppendLine('pre{background:var(--f-code-bg);'
      + 'color:var(--f-code-fg);margin:0;'
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
    SB.AppendLine('.codekarte.schlecht .karte-titel{'
      + 'background:var(--f-err-bg);color:var(--f-err-fg);}');
    SB.AppendLine('.codekarte.gut .karte-titel{'
      + 'background:var(--f-gut-bg);color:var(--f-gut-fg);}');
    SB.AppendLine('.karte{border:1px solid var(--rand);border-radius:8px;'
      + 'padding:8px 10px;margin-top:10px;'
      + 'background:var(--f-flaeche);}');
    SB.AppendLine('button.copy{border:1px solid var(--rand);'
      + 'background:var(--karte);border-radius:5px;cursor:pointer;'
      + 'font-size:0.8em;padding:1px 8px;}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TWorkbenchStyle.KopfAngepinntCss: string;
// Der Kopf bleibt beim Scrollen oben stehen und schrumpft dabei auf
// die Ueberschrift zusammen (Nutzerauftrag 09.09.). Statt zu
// verschwinden, traegt er die Orientierung ueber den ganzen Bericht -
// bei 20.000 Zeilen weiss man sonst nach dreimal Blaettern nicht
// mehr, was man vor sich hat.
//
// --kopf-h ist die AKTUELLE Kopfhoehe. Die Seiten haengen ihre sticky
// Tabellenkoepfe daran (top:var(--kopf-h)), sonst verschwaende die
// Spaltenzeile unter dem Kopf. Das JS pflegt den Wert bei jedem
// Zustandswechsel; der Rueckfall 0px gilt, solange kein Skript lief.
// z-index 5: UEBER der sticky Spaltenzeile (2) und dem Inhalt, aber
// UNTER dem Drawer (10). Ein hoeherer Wert liesse den Kopf ueber dem
// aufgeklappten Inspector liegen und dessen obere Ecke verdecken -
// die Staffelung der Seiten ist 2 / 5 / 10.
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('header.kopf{position:sticky;top:0;z-index:5;'
      + 'transition:padding 180ms ease;}');
    SB.AppendLine('header.kopf h1{transition:font-size 180ms ease;}');
    // Die Unterzeile faehrt zusammen statt hart zu verschwinden:
    // max-height traegt die Bewegung, opacity nimmt ihr die Haerte.
    SB.AppendLine('header.kopf .sub{max-height:6em;opacity:1;'
      + 'overflow:hidden;'
      + 'transition:max-height 180ms ease,opacity 140ms ease,'
      + 'margin-top 180ms ease;}');
    SB.AppendLine('header.kopf.mini{padding-top:8px;padding-bottom:8px;}');
    SB.AppendLine('header.kopf.mini h1{font-size:1.1em;}');
    SB.AppendLine('header.kopf.mini .sub{max-height:0;opacity:0;'
      + 'margin-top:0;}');
    // Wer Bewegung abgewaehlt hat, bekommt den Zustandswechsel ohne
    // Animation - der Kopf schrumpft trotzdem, er tut es nur sofort.
    SB.AppendLine('@media (prefers-reduced-motion:reduce){'
      + 'header.kopf,header.kopf h1,header.kopf .sub{transition:none;}}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TWorkbenchStyle.KopfVerhaltenJs: string;
// Begruendung an der Deklaration. Zwei Aufgaben:
//   1. ab einer Schwelle die Klasse "mini" setzen bzw. nehmen
//   2. --kopf-h auf die aktuelle Kopfhoehe halten, damit die sticky
//      Tabellenkoepfe der Seiten unter dem Kopf kleben und nicht
//      dahinter verschwinden
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('(function(){');
    SB.AppendLine('  var kopf=document.querySelector("header.kopf");');
    SB.AppendLine('  if(!kopf)return;');
    // Die Schwelle ist bewusst klein: der Kopf soll zusammenfahren,
    // SOBALD gescrollt wird, nicht erst wenn er ohnehin halb weg
    // waere. 24px sind etwa eine Zeile - genug, um ein versehentliches
    // Antippen des Rades nicht als Scrollen zu werten.
    SB.AppendLine('  var SCHWELLE=24;');
    SB.AppendLine('  function hoeheMerken(){');
    SB.AppendLine('    document.documentElement.style.setProperty('
    // getBoundingClientRect().height, NICHT offsetHeight: das eine
    // liefert Bruchteile, das andere rundet auf ganze Pixel. Unter
    // Windows-Skalierung (125 %, 150 %) sind Layouthoehen fast immer
    // gebrochen; wer daraus einen sticky-Versatz rechnet, landet leicht
    // einen Bruchteil zu tief - und durch diesen Spalt sieht man die
    // Zeilen durchlaufen (Nicos Befund 10.09.).
      + '"--kopf-h",kopf.getBoundingClientRect().height+"px");');
    SB.AppendLine('  }');
    SB.AppendLine('  function zustand(){');
    SB.AppendLine('    var runter=(window.scrollY||'
      + 'document.documentElement.scrollTop||0)>SCHWELLE;');
    SB.AppendLine('    if(runter===kopf.classList.contains("mini"))return;');
    SB.AppendLine('    kopf.classList.toggle("mini",runter);');
    SB.AppendLine('    hoeheMerken();');
    SB.AppendLine('  }');
    // Waehrend der Transition aendert sich die Hoehe laufend; erst am
    // Ende steht der Zielwert. Ohne dieses Nachziehen bliebe der
    // Tabellenkopf um die Differenz verschoben stehen.
    SB.AppendLine('  kopf.addEventListener("transitionend",hoeheMerken);');
    // passive: der Handler ruft kein preventDefault, und ohne die
    // Zusage muss der Browser vor jedem Scrollschritt darauf warten.
    SB.AppendLine('  window.addEventListener("scroll",zustand,'
      + '{passive:true});');
    SB.AppendLine('  window.addEventListener("resize",hoeheMerken);');
    SB.AppendLine('  hoeheMerken();zustand();');
    SB.AppendLine('})();');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
