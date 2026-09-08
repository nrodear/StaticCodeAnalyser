unit uFindingsWorkbenchV3;

// V3 des Fundberichts: dieselbe Optik wie V2, aber DATENMODELL statt
// vorgerenderter Tabelle - und die Liste rendert virtualisiert.
//
// WARUM ES DIESE SEITE GIBT (Nico-Auftrag 09.09.; Messung in
// Konzept_V2Performance_2026-09-09.md):
// V2 rendert jeden Fund als fertigen <tbody> mit vier <tr>. An einem
// echten Export gemessen sind das 2.404 Zeichen und 40 DOM-Elemente
// JE FUND. Bei 26.000 Funden ergibt das eine 60-MB-Datei mit ueber
// EINER MILLION DOM-Knoten - und die Million ist das eigentliche
// Problem: Browser werden ab etwa 10.000 Elementen traege, und jeder
// Filterlauf geht ueber alle Knoten. Eine kleinere Datei allein loest
// das NICHT.
//
// V3 dreht das um:
//   * Die Funde stehen als kompaktes JSON im Dokument (drei Tabellen:
//     regeln, pfade, funde). Was je Regel oder je Datei gleich ist,
//     steht EINMAL und wird ueber einen Index referenziert.
//   * Gerendert werden nur die sichtbaren Zeilen. Beim Scrollen
//     tauscht der Renderer den Inhalt derselben Elemente aus.
//   * Der Codeausschnitt wird erst beim Aufklappen gebaut.
//   * Kacheln, Top-Listen und die Health-Ampel rechnet die SEITE aus
//     den Daten - sie muessen nicht mitgeliefert werden.
//
// Erwartung an derselben Datei: rund 78 % weniger Bytes (60 MB ->
// 13 MB) und etwa 2.000 statt 1.041.000 DOM-Elemente.
//
// WAS V3 NICHT ANDERS MACHT: die Optik. Der Style-Block kommt
// unveraendert von V2 (TFindingsWorkbenchExport.SeitenStyle) - beide
// Seiten sollen sich gleich anfuehlen, und das haelt nur EINE
// CSS-Quelle durch. V3 haengt nur die Regeln fuer die virtualisierte
// Liste hinten an.
//
// WARUM DIVS STATT <table>: eine virtualisierte Tabelle muesste
// Zeilenhoehen aus dem Layout zurueckrechnen. Ein Grid mit FESTER
// Zeilenhoehe macht die Rechnung trivial (Index = Scrollposition /
// Hoehe) und traegt dieselbe Optik.
//
// SPRACHE: wie V2 serverseitig gebacken (ALang), Oberflaechentexte aus
// TWorkbenchI18n. Der Such-Blob traegt die Sprache mit.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TFindingsWorkbenchV3 = class
  public
    // Baut die komplette Seite. Parameter wie V2: ABaseDir steuert nur
    // die ANZEIGE der Pfade, AMaxRows deckelt die Zeilenzahl (-1 =
    // Voreinstellung 20.000, 0 = unbegrenzt), ALang ist die Sprache.
    //
    // Der Deckel wirkt hier anders als in V2, und das ist Absicht: dort
    // begrenzt er die DOM-Groesse, hier nur noch die Datenmenge. Der
    // virtualisierte Renderer haette mit 100.000 Zeilen kein Problem -
    // die Datei waere nur gross. Der Deckel bleibt trotzdem, weil eine
    // 200-MB-Datei niemandem hilft; er ist jetzt eine Groessen-, keine
    // Geschwindigkeitsbremse.
    class function BuildHtml(AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string; AMaxRows: Integer = -1;
      const ALang: string = 'de'): string; static;
    // Schreibt BuildHtml als UTF-8 mit BOM (Konvention aller Exporte).
    class procedure Run(AFindings: TObjectList<TLeakFinding>;
      const ABaseDir, AFileName: string; AMaxRows: Integer = -1;
      const ALang: string = 'de'); static;
    // Vorschlag fuer den Save-Dialog.
    class function DefaultFileName: string; static;
  private
    class procedure BauePage(ASB: TStringBuilder;
      AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string; AMaxRows: Integer;
      const ALang: string); static;
  end;

implementation

// noinspection-file DuplicateString, StringConcatInLoop, LongMethod
// Ein HTML-Generator wiederholt Tags bauartbedingt, und die JS-Bloecke
// stehen als zusammenhaengende Texte da, weil sie so lesbar bleiben -
// dieselbe Begruendung wie in V2 und der Katalogseite.

uses
  System.Math, System.IOUtils,
  uExport, uExportHtml, uRuleCatalog, uFixHint,
  uWorkbenchI18n, uFindingsWorkbenchExport;

const
  // Voreinstellung wie V1/V2. Siehe Anmerkung an BuildHtml.
  V3_MAX_ROWS_DEFAULT = 20000;
  // Kontextzeilen ueber und unter der Fundzeile (wie V2).
  SNIPPET_KONTEXT     = 3;
  // Rang eines Lesefehlers in der Severity-Sortierung: hinter Hint.
  SEV_RANG_LESEFEHLER = 3;
  // Hoehe einer Listenzeile in px. MUSS mit der CSS-Regel .v3-zeile
  // uebereinstimmen - die Virtualisierung rechnet den Index daraus.
  // Steht deshalb genau einmal hier und wird ins CSS UND ins JS
  // geschrieben; zwei Zahlen, die auseinanderlaufen koennen, waeren
  // ein springender Scrollbalken.
  V3_ZEILENHOEHE      = 52;

type
  // Ein Fund, so wie er ins JSON geht.
  TV3Fund = record
    Zeile   : Integer;
    Methode : string;
    RegelIx : Integer;          // Index in die regeln-Tabelle
    PfadIx  : Integer;          // Index in die pfade-Tabelle
    SevRang : Integer;
    Konf    : Integer;
    Detail  : string;
    HinwIx  : Integer;          // Index in die hinweise-Tabelle, -1 = keiner
    SnipAb  : Integer;          // erste Zeilennummer des Ausschnitts
    SnipEin : Integer;          // gemeinsamer Einzug
    Snippet : TArray<string>;
  end;

  // Alles, was je REGEL gleich ist - steht einmal statt je Fund.
  //
  // Der FixHint gehoert AUSDRUECKLICH NICHT hierher: TFixHintResolver
  // kennt Varianten je Fund (HintVariant), der Text kann sich also
  // innerhalb derselben Regel unterscheiden. Er steht in einer eigenen
  // Tabelle mit Index je Fund - dedupliziert, aber ohne die Annahme,
  // dass er je Regel konstant waere.
  TV3Regel = record
    ID      : string;
    Name    : string;
    TypCss  : string;
    TypText : string;
    Erkannt : string;
    Warum   : string;
  end;

{ ---- kleine Helfer -------------------------------------------------- }

function H(const S: string): string;
begin
  Result := TExporterHtml.HtmlEscape(S);
end;

function Einzeilig(const S: string): string;
// #13#10 zuerst, sonst entstehen zwei Leerzeichen.
begin
  Result := StringReplace(S, #13#10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

function JsonStr(const S: string): string;
// Ein JSON-String MIT Anfuehrungszeichen, sicher fuer den Einbau in
// ein <script type="application/json">.
//
// TExporter.JsonEscape ist RFC-8259-korrekt, escapet aber '<' nicht -
// und muss das auch nicht: in einer .json-DATEI ist '<' harmlos. HIER
// ist es das nicht. Der Browser beendet das Element beim ersten
// '</script>' im Textinhalt, ganz unabhaengig von JSON-Syntax; alles
// danach waere ausfuehrbares Skript. '<' ist gueltiges JSON und
// wird von JSON.parse wieder zu '<' - der INHALT bleibt unveraendert,
// nur seine Textform ist harmlos. Dieselbe Politik wie V2s
// JsonForScript.
begin
  Result := '"' + StringReplace(TExporter.JsonEscape(S), '<',
    '\u003c', [rfReplaceAll]) + '"';
end;

function TypCssV3(T: TFindingType): string;
// Deckungsgleich mit V2s TypCss - die CSS-Klassen kommen aus
// demselben Style-Block, also muessen es dieselben Namen sein.
begin
  case T of
    ftBug             : Result := 'bug';
    ftVulnerability   : Result := 'vuln';
    ftSecurityHotspot : Result := 'hotspot';
    ftCodeDuplication : Result := 'dup';
    ftFileError       : Result := 'ferr';
  else
    Result := 'smell';
  end;
end;

function TypTextV3(T: TFindingType): string;
// Sonar-Typbegriffe bleiben englische Fachbegriffe - wie in V2 und der
// Katalogseite, auch auf einer deutschen Seite.
begin
  case T of
    ftBug             : Result := 'Bug';
    ftVulnerability   : Result := 'Vulnerability';
    ftSecurityHotspot : Result := 'Security Hotspot';
    ftCodeSmell       : Result := 'Code Smell';
    ftCodeDuplication : Result := 'Code Duplication';
    ftFileError       : Result := 'File Error';
  else
    Result := 'Code Smell';
  end;
end;

function AnzeigePfad(const AFileName, ABaseDir: string): string;
// Wie V2: relativ zur Wurzel mit Forward Slashes, sonst der blosse
// Dateiname. Ein absoluter Pfad im Bericht nuetzt niemandem.
begin
  if ABaseDir <> '' then
    Result := TExporter.RelativeDisplayPath(AFileName, ABaseDir)
  else
    Result := ExtractFileName(AFileName);
  if Result = '' then
    Result := ExtractFileName(AFileName);
end;

function SevRangVon(F: TLeakFinding): Integer;
// Lesefehler tragen kein Wort der Skala und sortieren hinter die
// Hinweise (Politik aus V1/V2).
begin
  if F.Kind = fkFileReadError then
    Result := SEV_RANG_LESEFEHLER
  else
    Result := Ord(F.Severity);
end;

function SevTextVon(F: TLeakFinding; const ALang: string): string;
begin
  if F.Kind = fkFileReadError then
    Exit(TWorkbenchI18n.T(wtLesefehler, ALang));
  case F.Severity of
    lsError   : Result := TWorkbenchI18n.T(wtSevFehler, ALang);
    lsWarning : Result := TWorkbenchI18n.T(wtSevWarnung, ALang);
  else
    Result := TWorkbenchI18n.T(wtSevHinweis, ALang);
  end;
end;

function KonfTextVon(C: TFindingConfidence; const ALang: string): string;
begin
  case C of
    fcLow    : Result := TWorkbenchI18n.T(wtKonfNiedrig, ALang);
    fcMedium : Result := TWorkbenchI18n.T(wtKonfMittel, ALang);
  else
    Result := TWorkbenchI18n.T(wtKonfHoch, ALang);
  end;
end;

{ ---- Quelltext-Ausschnitt ------------------------------------------- }

function SnippetZeilen(ACache: TObjectDictionary<string, TStringList>;
  const ADatei: string; AZeile: Integer;
  out AAb, AEinzug: Integer): TArray<string>;
// Die ROHEN Codezeilen um die Fundstelle - V3 liefert Text, kein
// Markup; das Markup baut die Seite beim Aufklappen.
//
// Der Cache haelt jede Datei EINMAL: ein Bericht hat typisch viele
// Funde je Datei, und ohne Cache laese der Export dieselbe Datei
// dutzendfach. Nicht lesbare Dateien werden als nil gemerkt, damit ein
// fehlgeschlagener Zugriff nicht bei jedem Fund erneut versucht wird -
// ein Bericht ueber inzwischen geloeschten Code ist der Normalfall
// (dieselbe Politik wie V2s QuellAusschnitt).
//
// Der gemeinsame Einzug wird abgezogen und als Zahl mitgegeben: bei
// tief verschachteltem Code sind das je Zeile ein Dutzend Leerzeichen,
// die sich sonst ueber alle Funde summieren. Die Seite legt ihn beim
// Rendern wieder an.
var
  Lines   : TStringList;
  Von, Bis, i, E : Integer;
  Roh     : TArray<string>;
begin
  Result  := nil;
  AAb     := 0;
  AEinzug := 0;
  if (ADatei = '') or (AZeile <= 0) then Exit;

  if not ACache.TryGetValue(ADatei, Lines) then
  begin
    Lines := nil;
    if TFile.Exists(ADatei) then
      try
        Lines := TStringList.Create;
        Lines.LoadFromFile(ADatei);
      except
        // Nicht lesbar (Rechte, Kodierung, geloescht): als nil merken
        // und nie wieder versuchen.
        FreeAndNil(Lines);
      end;
    ACache.Add(ADatei, Lines);
  end;
  if Lines = nil then Exit;

  Von := Max(1, AZeile - SNIPPET_KONTEXT);
  Bis := Min(Lines.Count, AZeile + SNIPPET_KONTEXT);
  if Von > Bis then Exit;

  SetLength(Roh, Bis - Von + 1);
  for i := Von to Bis do
    Roh[i - Von] := Lines[i - 1];

  // Gemeinsamer Einzug nur ueber die NICHT leeren Zeilen - eine
  // Leerzeile haette ihn sonst immer auf 0 gezogen.
  AEinzug := MaxInt;
  for i := 0 to High(Roh) do
    if Trim(Roh[i]) <> '' then
    begin
      E := 0;
      while (E < Length(Roh[i])) and (Roh[i][E + 1] = ' ') do
        Inc(E);
      AEinzug := Min(AEinzug, E);
    end;
  if AEinzug = MaxInt then
    AEinzug := 0;

  for i := 0 to High(Roh) do
    if Trim(Roh[i]) = '' then
      Roh[i] := ''
    else
      Roh[i] := TrimRight(Copy(Roh[i], AEinzug + 1, MaxInt));

  AAb    := Von;
  Result := Roh;
end;

{ ---- Das Skript der Seite ------------------------------------------- }

function SeitenJsV3(const ALang: string): string;
// Der komplette Renderer. Er ist laenger als bei V2, und das ist der
// Handel: was hier an JavaScript dazukommt, faellt dort 26.000-mal als
// vorgerendertes Markup weg.
//
// HTML-Attribute im erzeugten Skript stehen in EINFACHEN
// Anfuehrungszeichen (im Pascal-Quelltext also verdoppelt), die
// JS-Strings in doppelten. So kommt kein Backslash-Escape vor - das
// hat sich beim Schreiben dieser Datei schon zweimal geraecht.
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<script>');
    SB.AppendLine('(function(){');
    SB.AppendLine('"use strict";');
    // ---- Modell laden ------------------------------------------------
    SB.AppendLine('var D=JSON.parse(document.getElementById('
      + '"v3daten").textContent);');
    SB.AppendLine('var R=D.regeln,P=D.pfade,HW=D.hinweise,F=D.funde;');
    // Feldindizes des Fund-Arrays - EINMAL benannt statt ueberall
    // Zahlen. Muss zur Schreibreihenfolge in BauePage passen.
    SB.AppendLine('var Z=0,ME=1,RI=2,PI=3,SV=4,KF=5,DT=6,HI=7,'
      + 'SA=8,SE=9,SN=10;');
    SB.AppendLine('var ZH=' + IntToStr(V3_ZEILENHOEHE) + ';');
    // Oberflaechentexte serverseitig gebacken - dieselbe Politik wie
    // die uebrige Seite.
    SB.AppendLine('var TSEV=['
      + JsonStr(TWorkbenchI18n.T(wtSevFehler, ALang)) + ','
      + JsonStr(TWorkbenchI18n.T(wtSevWarnung, ALang)) + ','
      + JsonStr(TWorkbenchI18n.T(wtSevHinweis, ALang)) + ','
      + JsonStr(TWorkbenchI18n.T(wtLesefehler, ALang)) + '];');
    SB.AppendLine('var CSEV=["err","warn","hint","ferr"];');
    SB.AppendLine('var TKONF=['
      + JsonStr(TWorkbenchI18n.T(wtKonfNiedrig, ALang)) + ','
      + JsonStr(TWorkbenchI18n.T(wtKonfMittel, ALang)) + ','
      + JsonStr(TWorkbenchI18n.T(wtKonfHoch, ALang)) + '];');
    SB.AppendLine('var TXT={erkannt:'
      + JsonStr(TWorkbenchI18n.T(wtWasWirdErkannt, ALang)) + ',warum:'
      + JsonStr(TWorkbenchI18n.T(wtWarumRelevant, ALang)) + ',hinweis:'
      + JsonStr(TWorkbenchI18n.T(wtHinweisZuFund, ALang)) + ',treffer:'
      + JsonStr(TWorkbenchI18n.T(wtZaehlerFunde, ALang)) + ',typ:'
      + JsonStr(TWorkbenchI18n.T(wtGruppeTyp, ALang)) + ',sev:'
      + JsonStr(TWorkbenchI18n.T(wtGruppeSchweregrad, ALang)) + ',konf:'
      + JsonStr(TWorkbenchI18n.T(wtGruppeKonfidenz, ALang)) + ',fehler:'
      + JsonStr(TWorkbenchI18n.T(wtKaFehler, ALang)) + ',warnungen:'
      + JsonStr(TWorkbenchI18n.T(wtKaWarnungen, ALang)) + ',hinweise:'
      + JsonStr(TWorkbenchI18n.T(wtKaHinweise, ALang)) + ',funde:'
      + JsonStr(TWorkbenchI18n.T(wtKaFunde, ALang)) + ',dateien:'
      + JsonStr(TWorkbenchI18n.T(wtKaDateien, ALang)) + ',regeln:'
      + JsonStr(TWorkbenchI18n.T(wtKaRegeln, ALang)) + ',hGruen:'
      + JsonStr(TWorkbenchI18n.T(wtHealthGruen, ALang)) + ',hGelb:'
      + JsonStr(TWorkbenchI18n.T(wtHealthGelb, ALang)) + ',hRot:'
      + JsonStr(TWorkbenchI18n.T(wtHealthRot, ALang)) + ',hFormel:'
      + JsonStr(TWorkbenchI18n.T(wtHealthFormel, ALang)) + ',secTitel:'
      + JsonStr(TWorkbenchI18n.T(wtSecurityTitel, ALang)) + ',secText:'
      + JsonStr(TWorkbenchI18n.T(wtSecurityText, ALang)) + ',topRegeln:'
      + JsonStr(TWorkbenchI18n.T(wtTopRegeln, ALang)) + ',topDateien:'
      + JsonStr(TWorkbenchI18n.T(wtTopDateien, ALang)) + '};');

    // ---- Helfer ------------------------------------------------------
    SB.AppendLine('function esc(s){return String(s).replace(/&/g,"&amp;")'
      + '.replace(/</g,"&lt;").replace(/>/g,"&gt;")'
      + '.replace(/"/g,"&quot;");}');
    // String.fromCharCode(92) IST der Backslash - bewusst so und nicht
    // als Literal: ein Backslash im Pascal-Quelltext dieser Datei ist
    // beim Schreiben schon zweimal verlorengegangen, und ein stummer
    // Verlust faellt hier erst beim Betrachten eines Windows-Pfads auf.
    SB.AppendLine('function basis(p){var i=Math.max(p.lastIndexOf("/"),'
      + 'p.lastIndexOf(String.fromCharCode(92)));'
      + 'return i>=0?p.substring(i+1):p;}');
    // Delphis Format-Platzhalter im Browser fuellen: wtHealthFormel
    // traegt DREI %d (Fehler, Warnungen, Hinweise), wtSecurityTitel
    // eines. Ohne diese Funktion stuende woertlich "%d" auf der Seite -
    // die Texte kommen aus derselben i18n-Quelle wie in V2, und dort
    // fuellt sie Format() serverseitig.
    SB.AppendLine('function fmt(t,a){var i=0;'
      + 'return String(t).replace(/%[ds]/g,function(){'
      + 'return a[i++];});}');

    // ---- Suchindex: erst bei Bedarf, dann gemerkt ---------------------
    // V2 liefert je Fund einen fertigen data-search-Blob mit - allein
    // 12,4 % der Datei. Hier entsteht er im Browser, und zwar NUR fuer
    // Funde, die tatsaechlich durch eine Suche laufen.
    SB.AppendLine('var BLOBS=new Array(F.length);');
    SB.AppendLine('function blob(i){');
    SB.AppendLine('  var b=BLOBS[i];');
    SB.AppendLine('  if(b===undefined){');
    SB.AppendLine('    var f=F[i],r=R[f[RI]];');
    SB.AppendLine('    b=(P[f[PI]]+" "+f[Z]+" "+f[ME]+" "+f[DT]+" "'
      + '+r[0]+" "+r[1]+" "+r[3]+" "+TSEV[f[SV]]+" "+TKONF[f[KF]])'
      + '.toLowerCase();');
    SB.AppendLine('    BLOBS[i]=b;');
    SB.AppendLine('  }');
    SB.AppendLine('  return b;');
    SB.AppendLine('}');

    // ---- Filterzustand -----------------------------------------------
    SB.AppendLine('var fTyp={},fSev={},fKonf={},sortSp=4,sortAuf=true;');
    SB.AppendLine('var sicht=[];');
    SB.AppendLine('var wrap=document.getElementById("v3wrap");');
    SB.AppendLine('var rows=document.getElementById("v3rows");');
    SB.AppendLine('var spacer=document.getElementById("v3spacer");');
    SB.AppendLine('var leer=document.getElementById("v3leer");');
    SB.AppendLine('var suche=document.getElementById("suche");');
    SB.AppendLine('var zaehler=document.getElementById("zaehler");');

    SB.AppendLine('function leerAuswahl(o){for(var k in o)'
      + 'if(o[k])return false;return true;}');

    SB.AppendLine('function passt(i){');
    SB.AppendLine('  var f=F[i],r=R[f[RI]];');
    SB.AppendLine('  if(!leerAuswahl(fTyp)&&!fTyp[r[2]])return false;');
    SB.AppendLine('  if(!leerAuswahl(fSev)&&!fSev[f[SV]])return false;');
    SB.AppendLine('  if(!leerAuswahl(fKonf)&&!fKonf[f[KF]])return false;');
    SB.AppendLine('  return true;');
    SB.AppendLine('}');

    // ---- Sortierung ---------------------------------------------------
    // Sortiert wird die INDEXLISTE, nicht das DOM - das ist der zweite
    // Grund, warum die Seite bei 26.000 Funden nicht mehr einbricht.
    SB.AppendLine('function schluessel(i,sp){');
    SB.AppendLine('  var f=F[i],r=R[f[RI]];');
    SB.AppendLine('  if(sp===0)return f[Z];');
    SB.AppendLine('  if(sp===1)return f[ME].toLowerCase();');
    SB.AppendLine('  if(sp===2)return r[0].toLowerCase();');
    SB.AppendLine('  if(sp===3)return r[1].toLowerCase();');
    SB.AppendLine('  if(sp===4)return r[3].toLowerCase();');
    SB.AppendLine('  if(sp===5)return f[SV];');
    SB.AppendLine('  return f[KF];');
    SB.AppendLine('}');
    SB.AppendLine('function sortieren(){');
    SB.AppendLine('  var vz=sortAuf?1:-1;');
    SB.AppendLine('  sicht.sort(function(a,b){');
    SB.AppendLine('    var x=schluessel(a,sortSp),y=schluessel(b,sortSp);');
    SB.AppendLine('    if(x<y)return -vz;');
    SB.AppendLine('    if(x>y)return vz;');
    // Zweitschluessel Severity, dann Zeile: gleiche Werte sollen nicht
    // je nach Sortierlauf springen (V1-Gewohnheit).
    SB.AppendLine('    if(F[a][SV]!==F[b][SV])return F[a][SV]-F[b][SV];');
    SB.AppendLine('    return F[a][Z]-F[b][Z];');
    SB.AppendLine('  });');
    SB.AppendLine('}');

    // ---- Filtern und zeichnen ------------------------------------------
    SB.AppendLine('function filtern(){');
    SB.AppendLine('  var q=suche.value.toLowerCase().trim();');
    SB.AppendLine('  sicht=[];');
    SB.AppendLine('  for(var i=0;i<F.length;i++){');
    SB.AppendLine('    if(!passt(i))continue;');
    SB.AppendLine('    if(q&&blob(i).indexOf(q)<0)continue;');
    SB.AppendLine('    sicht.push(i);');
    SB.AppendLine('  }');
    SB.AppendLine('  sortieren();');
    SB.AppendLine('  wrap.scrollTop=0;');
    SB.AppendLine('  zeichnen();');
    SB.AppendLine('  zaehler.textContent=sicht.length+" "+TXT.treffer;');
    SB.AppendLine('  leer.hidden=sicht.length>0;');
    SB.AppendLine('}');

    // DAS HERZ: nur die sichtbaren Zeilen im DOM. Ein Puffer von fuenf
    // Zeilen oben und unten haelt das Scrollen ruhig, ohne dass beim
    // schnellen Ziehen Luecken aufblitzen.
    SB.AppendLine('function zeichnen(){');
    SB.AppendLine('  spacer.style.height=(sicht.length*ZH)+"px";');
    SB.AppendLine('  var von=Math.max(0,Math.floor(wrap.scrollTop/ZH)-5);');
    SB.AppendLine('  var anz=Math.ceil(wrap.clientHeight/ZH)+10;');
    SB.AppendLine('  var bis=Math.min(sicht.length,von+anz);');
    SB.AppendLine('  rows.style.transform="translateY("+(von*ZH)+"px)";');
    SB.AppendLine('  var h="";');
    SB.AppendLine('  for(var i=von;i<bis;i++)h+=zeile(sicht[i]);');
    SB.AppendLine('  rows.innerHTML=h;');
    SB.AppendLine('}');
    SB.AppendLine('wrap.addEventListener("scroll",zeichnen);');
    SB.AppendLine('window.addEventListener("resize",zeichnen);');

    // ---- Eine Zeile ----------------------------------------------------
    // Die Optik ist die von V2: Zeile, Methode mit Datei darunter,
    // SCA-ID, Regelname, Typ-, Severity- und Konfidenz-Badge.
    SB.AppendLine('function zeile(i){');
    SB.AppendLine('  var f=F[i],r=R[f[RI]],p=P[f[PI]];');
    SB.AppendLine('  var dz=esc(basis(p));');
    SB.AppendLine('  if(basis(p)!==p)dz+="; "+esc(p);');
    SB.AppendLine('  return "<div class=''v3-zeile'' data-i=''"+i'
      + '+"'' tabindex=''0''>"');
    SB.AppendLine('    +"<div class=''v3-num''>"+f[Z]+"</div>"');
    SB.AppendLine('    +"<div><div class=''v3-haupt''>"+esc(f[ME])'
      + '+"</div><div class=''v3-datei'' title=''"+esc(p)+"''>"+dz'
      + '+"</div></div>"');
    SB.AppendLine('    +"<div>"+esc(r[0])+"</div>"');
    SB.AppendLine('    +"<div class=''v3-haupt''>"+esc(r[1])+"</div>"');
    SB.AppendLine('    +"<div><span class=''badge typ "+r[2]+"''>"'
      + '+esc(r[3])+"</span></div>"');
    SB.AppendLine('    +"<div><span class=''badge sev-"+CSEV[f[SV]]'
      + '+"''>"+esc(TSEV[f[SV]])+"</span></div>"');
    SB.AppendLine('    +"<div><span class=''badge konf''>"'
      + '+esc(TKONF[f[KF]])+"</span></div>"');
    SB.AppendLine('    +"</div>";');
    SB.AppendLine('}');

    // ---- Drawer ---------------------------------------------------------
    // Der Codeausschnitt entsteht ERST HIER. In V2 steht er bei jedem
    // Fund im DOM, obwohl ihn nur der aufgeklappte braucht - allein
    // 44,7 % der Datei.
    SB.AppendLine('var drawer=document.getElementById("drawer");');
    SB.AppendLine('var dinhalt=document.getElementById("drawer-inhalt");');
    SB.AppendLine('function schnipsel(f){');
    SB.AppendLine('  var s=f[SN];');
    SB.AppendLine('  if(!s||!s.length)return "";');
    SB.AppendLine('  var ein=new Array(f[SE]+1).join(" ");');
    SB.AppendLine('  var h="<div class=''src-snippet''>";');
    SB.AppendLine('  for(var k=0;k<s.length;k++){');
    SB.AppendLine('    var nr=f[SA]+k;');
    SB.AppendLine('    var akt=(nr===f[Z]);');
    SB.AppendLine('    h+="<div class=''src-line"+(akt?" src-line-active"'
      + ':"")+"''><span class=''src-line-num''>"+nr'
      + '+"</span> <span class=''src-line-bar''>"'
      + '+(akt?"&#9658;":"&nbsp;")+"</span>"'
      + '+esc(ein+s[k])+"</div>";');
    SB.AppendLine('  }');
    SB.AppendLine('  return h+"</div>";');
    SB.AppendLine('}');
    SB.AppendLine('function oeffne(i){');
    SB.AppendLine('  var f=F[i],r=R[f[RI]];');
    // Aufbau wie V2s Inspector: Kopf mit Badges und Fundort, dann der
    // Ausschnitt, dann der Fix-Block, dann das Sekundaere (Regel-Doku).
    // Klassen insp-block / insp-fix / insp-sekundaer / metarow sind die
    // von V2 - der geteilte Style-Block kennt nur diese.
    SB.AppendLine('  var h="<span class=''badge sev-"+CSEV[f[SV]]'
      + '+"''>"+esc(TSEV[f[SV]])+"</span> <span class=''badge typ "'
      + '+r[2]+"''>"+esc(r[3])+"</span>"');
    SB.AppendLine('    +"<h2>"+esc(r[0])+" "+esc(r[1])+"</h2>"');
    SB.AppendLine('    +"<div class=''metarow''>"+esc(P[f[PI]])+":"+f[Z]'
      + '+" "+esc(f[ME])+"</div>";');
    SB.AppendLine('  if(f[DT])h+="<div class=''insp-block''><p>"'
      + '+esc(f[DT])+"</p></div>";');
    SB.AppendLine('  h+=schnipsel(f);');
    SB.AppendLine('  if(f[HI]>=0)h+="<div class=''insp-fix''><h3>"'
      + '+esc(TXT.hinweis)+"</h3><p>"+esc(HW[f[HI]])+"</p></div>";');
    SB.AppendLine('  if(r[4]||r[5]){');
    SB.AppendLine('    h+="<div class=''insp-sekundaer''>";');
    SB.AppendLine('    if(r[4])h+="<h3>"+esc(TXT.erkannt)+"</h3><p>"'
      + '+esc(r[4])+"</p>";');
    SB.AppendLine('    if(r[5])h+="<h3>"+esc(TXT.warum)+"</h3><p>"'
      + '+esc(r[5])+"</p>";');
    SB.AppendLine('    h+="</div>";');
    SB.AppendLine('  }');
    SB.AppendLine('  dinhalt.innerHTML=h;');
    SB.AppendLine('  drawer.hidden=false;');
    SB.AppendLine('}');
    SB.AppendLine('rows.addEventListener("click",function(ev){');
    SB.AppendLine('  var z=ev.target.closest(".v3-zeile");');
    SB.AppendLine('  if(!z)return;');
    SB.AppendLine('  var vor=rows.querySelector(".v3-zeile.gewaehlt");');
    SB.AppendLine('  if(vor)vor.classList.remove("gewaehlt");');
    SB.AppendLine('  z.classList.add("gewaehlt");');
    SB.AppendLine('  oeffne(parseInt(z.getAttribute("data-i"),10));');
    SB.AppendLine('});');
    SB.AppendLine('rows.addEventListener("keydown",function(ev){');
    SB.AppendLine('  if(ev.key!=="Enter"&&ev.key!==" ")return;');
    SB.AppendLine('  var z=ev.target.closest(".v3-zeile");');
    SB.AppendLine('  if(!z)return;');
    SB.AppendLine('  ev.preventDefault();');
    SB.AppendLine('  oeffne(parseInt(z.getAttribute("data-i"),10));');
    SB.AppendLine('});');
    SB.AppendLine('document.getElementById("drawer-schliessen")'
      + '.addEventListener("click",function(){drawer.hidden=true;});');
    SB.AppendLine('document.addEventListener("keydown",function(ev){');
    SB.AppendLine('  if(ev.key==="Escape"){drawer.hidden=true;return;}');
    // Ctrl+K in die Suche - die cmdbar zeigt die Taste an, also muss
    // sie auch etwas tun. In V2 fehlte der Handler auf der V2-Seite
    // (Feature-Abgleich, offener Punkt "Report: Ctrl+K zusaetzlich zu
    // /"); hier ist er von Anfang an drin.
    SB.AppendLine('  if((ev.ctrlKey||ev.metaKey)&&'
      + '(ev.key==="k"||ev.key==="K")){');
    SB.AppendLine('    ev.preventDefault();suche.focus();suche.select();');
    SB.AppendLine('  }');
    SB.AppendLine('});');

    // ---- Chips ----------------------------------------------------------
    SB.AppendLine('var chips=document.getElementById("v3chips");');
    SB.AppendLine('function baueChips(){');
    SB.AppendLine('  var typen={},h="";');
    SB.AppendLine('  for(var i=0;i<R.length;i++)typen[R[i][2]]=R[i][3];');
    // Klasse fchip und data-gruppe/data-wert wie V2, Zustand ueber
    // aria-pressed - dort haengt auch die CSS-Regel fuer den aktiven
    // Chip dran, eine eigene Klasse waere unsichtbar geblieben.
    SB.AppendLine('  function cp(g,v,t){return "<button class=''fchip'' '
      + 'data-gruppe=''"+g+"'' data-wert=''"+v+"'' '
      + 'aria-pressed=''false''>"+esc(t)+"</button>";}');
    SB.AppendLine('  h+="<span class=''gruppe''>"+esc(TXT.typ)+"</span>";');
    SB.AppendLine('  for(var t in typen)h+=cp("typ",t,typen[t]);');
    SB.AppendLine('  h+="<span class=''gruppe''>"+esc(TXT.sev)+"</span>";');
    // Nur drei Schweregrade als Chips; der Lesefehler-Rang (3) bekommt
    // seinen Chip nur, wenn es ihn im Lauf ueberhaupt gibt - wie V2.
    SB.AppendLine('  var maxSev=3;');
    SB.AppendLine('  for(var i2=0;i2<F.length;i2++)'
      + 'if(F[i2][SV]===3){maxSev=4;break;}');
    SB.AppendLine('  for(var s=0;s<maxSev;s++)h+=cp("sev",s,TSEV[s]);');
    SB.AppendLine('  h+="<span class=''gruppe''>"+esc(TXT.konf)+"</span>";');
    SB.AppendLine('  for(var k=2;k>=0;k--)h+=cp("konf",k,TKONF[k]);');
    SB.AppendLine('  chips.innerHTML=h;');
    SB.AppendLine('}');
    SB.AppendLine('chips.addEventListener("click",function(ev){');
    SB.AppendLine('  var b=ev.target.closest(".fchip");');
    SB.AppendLine('  if(!b)return;');
    SB.AppendLine('  var g=b.getAttribute("data-gruppe");');
    SB.AppendLine('  var v=b.getAttribute("data-wert");');
    SB.AppendLine('  var o=(g==="typ")?fTyp:((g==="sev")?fSev:fKonf);');
    SB.AppendLine('  o[v]=!o[v];');
    SB.AppendLine('  b.setAttribute("aria-pressed",o[v]?"true":"false");');
    SB.AppendLine('  filtern();');
    SB.AppendLine('});');

    // ---- Kacheln --------------------------------------------------------
    // Aus den Daten gerechnet, nicht mitgeliefert.
    SB.AppendLine('function baueKacheln(){');
    SB.AppendLine('  var n=[0,0,0,0],dat={},reg={};');
    SB.AppendLine('  for(var i=0;i<F.length;i++){');
    SB.AppendLine('    n[F[i][SV]]++;dat[F[i][PI]]=1;reg[F[i][RI]]=1;');
    SB.AppendLine('  }');
    // Klassen exakt wie V2: kachel / zahl / wofuer.
    SB.AppendLine('  function ka(w,t){return "<div class=''kachel''>'
      + '<div class=''zahl''>"+w+"</div><div class=''wofuer''>"'
      + '+esc(t)+"</div></div>";}');
    SB.AppendLine('  document.getElementById("v3kacheln").innerHTML='
      + 'ka(F.length,TXT.funde)+ka(n[0],TXT.fehler)+ka(n[1],TXT.warnungen)'
      + '+ka(n[2],TXT.hinweise)+ka(Object.keys(dat).length,TXT.dateien)'
      + '+ka(Object.keys(reg).length,TXT.regeln);');
    SB.AppendLine('}');

    // ---- Health-Ampel, Security, Top-Listen -----------------------------
    // Alles aus den Daten gerechnet. Formel und Schwellen sind die von
    // V1/V2 (Fehler 100, Warnung 10, Hinweis 1; gruen bis 49, gelb bis
    // 499) - eine zweite Rechnung mit anderem Ergebnis waere schlimmer
    // als keine.
    SB.AppendLine('function bauePanels(){');
    SB.AppendLine('  var n=[0,0,0,0],sec=0;');
    SB.AppendLine('  for(var i=0;i<F.length;i++){');
    SB.AppendLine('    n[F[i][SV]]++;');
    SB.AppendLine('    var tc=R[F[i][RI]][2];');
    SB.AppendLine('    if(tc==="vuln"||tc==="hotspot")sec++;');
    SB.AppendLine('  }');
    SB.AppendLine('  var score=n[0]*100+n[1]*10+n[2];');
    SB.AppendLine('  var cls=(score<=49)?"gruen":((score<=499)?"gelb"'
      + ':"rot");');
    SB.AppendLine('  var wort=(score<=49)?TXT.hGruen:((score<=499)?'
      + 'TXT.hGelb:TXT.hRot);');
    SB.AppendLine('  var h="<div class=''health health-"+cls+"''>"');
    SB.AppendLine('    +"<div class=''health-zahl''>"+score+"</div>"');
    SB.AppendLine('    +"<div><b>"+esc(wort)+"</b><div '
      + 'class=''health-txt''>"+esc(fmt(TXT.hFormel,[n[0],n[1],n[2]]))'
      + '+"</div></div></div>";');
    SB.AppendLine('  if(sec>0){');
    // Die Zahl steckt IM formatierten Text (wtSecurityTitel traegt ein
    // %d) - sie davor noch einmal auszugeben ergaebe "25 25 security
    // findings".
    SB.AppendLine('    h+="<div class=''secpanel''><div><b>"'
      + '+esc(fmt(TXT.secTitel,[sec]))+"</b><div class=''health-txt''>"'
      + '+esc(TXT.secText)+"</div></div></div>";');
    SB.AppendLine('  }');
    SB.AppendLine('  document.getElementById("v3panels").innerHTML=h;');
    SB.AppendLine('}');

    // Top-Listen: klickbar, sie setzen den Suchtext. Das ist der
    // einfachste Weg, der mit dem Datenmodell zusammenpasst - V2
    // schaltet dort ein Dropdown, das es hier nicht gibt.
    SB.AppendLine('function baueTop(id,paare,titel){');
    SB.AppendLine('  paare.sort(function(a,b){return b[1]-a[1];});');
    SB.AppendLine('  var top=paare.slice(0,10);');
    SB.AppendLine('  if(!top.length){document.getElementById(id)'
      + '.innerHTML="";return;}');
    SB.AppendLine('  var max=top[0][1]||1;');
    SB.AppendLine('  var h="<h2>"+esc(titel)+"</h2><ul>";');
    SB.AppendLine('  for(var i=0;i<top.length;i++){');
    SB.AppendLine('    var pz=Math.round(100*top[i][1]/max);');
    SB.AppendLine('    h+="<li tabindex=''0'' role=''button'' '
      + 'data-wert=''"+esc(top[i][0])+"''>"');
    SB.AppendLine('      +"<span class=''tl-name''>"+esc(top[i][0])'
      + '+"</span>"');
    SB.AppendLine('      +"<span class=''tl-bar''><span class=''tl-fill'' '
      + 'style=''width:"+pz+"%''></span></span>"');
    SB.AppendLine('      +"<span class=''tl-zahl''>"+top[i][1]'
      + '+"</span></li>";');
    SB.AppendLine('  }');
    SB.AppendLine('  document.getElementById(id).innerHTML=h+"</ul>";');
    SB.AppendLine('}');
    SB.AppendLine('function baueToplisten(){');
    SB.AppendLine('  var reg={},dat={};');
    SB.AppendLine('  for(var i=0;i<F.length;i++){');
    SB.AppendLine('    var rid=R[F[i][RI]][0];');
    SB.AppendLine('    reg[rid]=(reg[rid]||0)+1;');
    SB.AppendLine('    var p=P[F[i][PI]];');
    SB.AppendLine('    dat[p]=(dat[p]||0)+1;');
    SB.AppendLine('  }');
    SB.AppendLine('  function paare(o){var a=[];for(var k in o)'
      + 'a.push([k,o[k]]);return a;}');
    SB.AppendLine('  baueTop("topRegeln",paare(reg),TXT.topRegeln);');
    SB.AppendLine('  baueTop("topDateien",paare(dat),TXT.topDateien);');
    SB.AppendLine('}');
    // Klick auf einen Eintrag filtert ueber die Suche.
    SB.AppendLine('function topKlick(ev){');
    SB.AppendLine('  var li=ev.target.closest("li[data-wert]");');
    SB.AppendLine('  if(!li)return;');
    SB.AppendLine('  suche.value=li.getAttribute("data-wert");');
    SB.AppendLine('  filtern();');
    SB.AppendLine('  suche.focus();');
    SB.AppendLine('}');
    SB.AppendLine('document.getElementById("topRegeln")'
      + '.addEventListener("click",topKlick);');
    SB.AppendLine('document.getElementById("topDateien")'
      + '.addEventListener("click",topKlick);');

    // ---- Kopfzeile: Sortierung + aria-sort -------------------------------
    SB.AppendLine('var kopf=document.getElementById("v3kopf");');
    SB.AppendLine('kopf.addEventListener("click",function(ev){');
    SB.AppendLine('  var s=ev.target.closest("[data-s]");');
    SB.AppendLine('  if(!s)return;');
    SB.AppendLine('  var sp=parseInt(s.getAttribute("data-s"),10);');
    SB.AppendLine('  if(sp===sortSp)sortAuf=!sortAuf;'
      + 'else{sortSp=sp;sortAuf=true;}');
    SB.AppendLine('  var alle=kopf.querySelectorAll("[data-s]");');
    SB.AppendLine('  for(var i=0;i<alle.length;i++)'
      + 'alle[i].removeAttribute("aria-sort");');
    SB.AppendLine('  s.setAttribute("aria-sort",sortAuf?"ascending"'
      + ':"descending");');
    SB.AppendLine('  sortieren();zeichnen();');
    SB.AppendLine('});');

    // ---- Suche, Reset, Theme ---------------------------------------------
    // Debounce: bei 26.000 Funden laeuft die Suche ueber alle Blobs.
    // 120 ms sind die Zahl, die V1 dafuer gefunden hat.
    SB.AppendLine('var tmr=null;');
    SB.AppendLine('suche.addEventListener("input",function(){');
    SB.AppendLine('  if(tmr)clearTimeout(tmr);');
    SB.AppendLine('  tmr=setTimeout(filtern,120);');
    SB.AppendLine('});');
    SB.AppendLine('document.getElementById("reset")'
      + '.addEventListener("click",function(){');
    SB.AppendLine('  suche.value="";fTyp={};fSev={};fKonf={};');
    SB.AppendLine('  var an=chips.querySelectorAll(".chip.an");');
    SB.AppendLine('  for(var i=0;i<an.length;i++)an[i].classList'
      + '.remove("an");');
    SB.AppendLine('  filtern();');
    SB.AppendLine('});');
    SB.AppendLine('(function(){');
    SB.AppendLine('  var KEY="sca-v3-theme",TH=["light","dark","sepia"];');
    SB.AppendLine('  var bt=document.getElementById("btnTheme");');
    SB.AppendLine('  if(bt)bt.addEventListener("click",function(){');
    SB.AppendLine('    var j=document.documentElement'
      + '.getAttribute("data-theme");');
    SB.AppendLine('    var n=TH[(TH.indexOf(j)+1)%TH.length];');
    SB.AppendLine('    document.documentElement.setAttribute('
      + '"data-theme",n);');
    SB.AppendLine('    try{localStorage.setItem(KEY,n);}catch(e){}');
    SB.AppendLine('  });');
    SB.AppendLine('})();');

    // ---- Start -----------------------------------------------------------
    SB.AppendLine('baueChips();baueKacheln();bauePanels();'
      + 'baueToplisten();filtern();');
    SB.AppendLine('})();');
    SB.AppendLine('</script>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ---- Seitenbau ------------------------------------------------------ }

class function TFindingsWorkbenchV3.DefaultFileName: string;
begin
  Result := 'sca-funde-v3.html';
end;

class function TFindingsWorkbenchV3.BuildHtml(
  AFindings: TObjectList<TLeakFinding>; const ABaseDir: string;
  AMaxRows: Integer; const ALang: string): string;
var
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    BauePage(SB, AFindings, ABaseDir, AMaxRows, ALang);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class procedure TFindingsWorkbenchV3.Run(
  AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, AFileName: string; AMaxRows: Integer;
  const ALang: string);
var
  SB : TStringBuilder;
begin
  // Direkt aus dem Builder auf Platte - der TStringList-Umweg hielt den
  // Bericht dreifach im Speicher (V1-OOM-Lehre).
  SB := TStringBuilder.Create;
  try
    BauePage(SB, AFindings, ABaseDir, AMaxRows, ALang);
    TExporterHtml.SaveBuilderUtf8WithBom(SB, AFileName);
  finally
    SB.Free;
  end;
end;

class procedure TFindingsWorkbenchV3.BauePage(ASB: TStringBuilder;
  AFindings: TObjectList<TLeakFinding>; const ABaseDir: string;
  AMaxRows: Integer; const ALang: string);
var
  SB          : TStringBuilder;
  MaxRows     : Integer;
  Gesamt      : Integer;
  Gekuerzt    : Integer;
  Regeln      : TList<TV3Regel>;
  RegelIx     : TDictionary<string, Integer>;
  Pfade       : TList<string>;
  PfadIx      : TDictionary<string, Integer>;
  Hinweise    : TList<string>;
  HinweisIx   : TDictionary<string, Integer>;
  Funde       : TList<TV3Fund>;
  QuellCache  : TObjectDictionary<string, TStringList>;
  F           : TLeakFinding;
  Meta        : TRuleMeta;
  R           : TV3Regel;
  V           : TV3Fund;
  Pfad        : string;
  i, k        : Integer;
  Erst        : Boolean;

  // Legt eine Regel einmalig an und liefert ihren Index.
  function HoleRegelIx(AF: TLeakFinding; const AMeta: TRuleMeta): Integer;
  var
    Neu : TV3Regel;
    Sch : string;
  begin
    // Schluessel ist die WIRKSAME Regel-ID: eine Custom-Rule-ID gewinnt
    // gegen den Katalog, sonst gilt die eingebaute.
    if AF.RuleID <> '' then
      Sch := AF.RuleID
    else
      Sch := AMeta.ID;
    if RegelIx.TryGetValue(Sch, Result) then Exit;

    Neu.ID      := Sch;
    Neu.Name    := AMeta.Name;
    Neu.TypCss  := TypCssV3(AMeta.FindingType);
    Neu.TypText := TypTextV3(AMeta.FindingType);
    Neu.Erkannt := Einzeilig(AMeta.ShortDescription);
    Neu.Warum   := Einzeilig(AMeta.FullDescription);
    Result := Regeln.Add(Neu);
    RegelIx.Add(Sch, Result);
  end;

  function HolePfadIx(const APfad: string): Integer;
  begin
    if PfadIx.TryGetValue(APfad, Result) then Exit;
    Result := Pfade.Add(APfad);
    PfadIx.Add(APfad, Result);
  end;

  // -1 = kein Hinweis. Sonst der Index in die hinweise-Tabelle; der
  // Text steht dort EINMAL, egal wie viele Funde ihn tragen.
  function HoleHinweisIx(const AText: string): Integer;
  begin
    if AText = '' then Exit(-1);
    if HinweisIx.TryGetValue(AText, Result) then Exit;
    Result := Hinweise.Add(AText);
    HinweisIx.Add(AText, Result);
  end;

begin
  if AMaxRows < 0 then
    MaxRows := V3_MAX_ROWS_DEFAULT
  else
    MaxRows := AMaxRows;

  Regeln     := TList<TV3Regel>.Create;
  RegelIx    := TDictionary<string, Integer>.Create;
  Pfade      := TList<string>.Create;
  PfadIx     := TDictionary<string, Integer>.Create;
  Hinweise   := TList<string>.Create;
  HinweisIx  := TDictionary<string, Integer>.Create;
  Funde      := TList<TV3Fund>.Create;
  QuellCache := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  try
    Gesamt := 0;
    if Assigned(AFindings) then
      Gesamt := AFindings.Count;
    Gekuerzt := 0;
    if (MaxRows > 0) and (Gesamt > MaxRows) then
      Gekuerzt := Gesamt - MaxRows;

    if Assigned(AFindings) then
      for F in AFindings do
      begin
        if (MaxRows > 0) and (Funde.Count >= MaxRows) then Break;
        // KANONISCH: die Anzeige-Sprache steuert ALang, nicht eine
        // globale Variable - dieselbe Politik wie in V2 und SARIF.
        Meta := TRuleCatalog.GetRule(F.Kind, ALang);
        Pfad := AnzeigePfad(F.FileName, ABaseDir);

        V.Zeile   := StrToIntDef(F.LineNumber, 0);
        V.Methode := Einzeilig(F.MethodName);
        V.RegelIx := HoleRegelIx(F, Meta);
        V.PfadIx  := HolePfadIx(Pfad);
        V.SevRang := SevRangVon(F);
        V.Konf    := Ord(F.Confidence);
        V.Detail  := Einzeilig(F.MissingVar);
        V.HinwIx  := HoleHinweisIx(
                       Einzeilig(TFixHintResolver.FixHint(F).Description));
        V.Snippet := SnippetZeilen(QuellCache, F.FileName, V.Zeile,
                                   V.SnipAb, V.SnipEin);
        Funde.Add(V);
      end;

    SB := ASB;
    SB.AppendLine('<!DOCTYPE html>');
    SB.AppendLine('<html lang="' + LowerCase(Copy(ALang, 1, 2)) + '">');
    SB.AppendLine('<head>');
    SB.AppendLine('<meta charset="utf-8">');
    SB.AppendLine('<meta name="viewport" content="width=device-width, '
      + 'initial-scale=1">');
    SB.AppendLine('<title>' + H(TWorkbenchI18n.T(wtTitelFunde, ALang))
      + '</title>');
    // Optik unveraendert von V2 - EINE CSS-Quelle fuer beide Seiten.
    SB.Append(TFindingsWorkbenchExport.SeitenStyle);
    // Nur die Regeln, die V2 nicht hat: die virtualisierte Liste.
    SB.AppendLine('<style>');
    SB.AppendLine('#v3wrap{position:relative;overflow-y:auto;'
      + 'max-height:62vh;border:1px solid var(--rand);'
      + 'border-radius:8px;background:var(--karte);}');
    // Der Spacer traegt die volle Hoehe aller Treffer und erzeugt damit
    // den Scrollbalken; die Zeilen liegen absolut darueber.
    SB.AppendLine('#v3spacer{position:relative;width:100%;}');
    SB.AppendLine('#v3rows{position:absolute;top:0;left:0;right:0;}');
    SB.AppendLine('.v3-zeile{height:' + IntToStr(V3_ZEILENHOEHE)
      + 'px;box-sizing:border-box;display:grid;'
      + 'grid-template-columns:64px 1fr 92px 1fr 132px 104px 96px;'
      + 'align-items:center;gap:10px;padding:0 12px;'
      + 'border-bottom:1px solid var(--rand);cursor:pointer;'
      + 'transition:background 150ms ease;}');
    SB.AppendLine('.v3-zeile:hover{background:var(--f-chip-bg);}');
    SB.AppendLine('.v3-zeile.gewaehlt{background:var(--f-chip-bg);'
      + 'border-left:3px solid var(--akzent);padding-left:9px;}');
    SB.AppendLine('.v3-zeile:focus-visible{outline:2px solid '
      + 'var(--akzent);outline-offset:-2px;}');
    // Zwei Textzeilen je Eintrag: oben Methode, darunter Dateiname und
    // voller Pfad mit Ellipse (Nutzerwunsch 07.09., wie V2).
    SB.AppendLine('.v3-haupt{overflow:hidden;text-overflow:ellipsis;'
      + 'white-space:nowrap;}');
    SB.AppendLine('.v3-datei{font-size:11px;color:var(--dezent);'
      + 'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}');
    SB.AppendLine('.v3-num{text-align:right;font-variant-numeric:'
      + 'tabular-nums;color:var(--dezent);}');
    SB.AppendLine('#v3kopf{display:grid;'
      + 'grid-template-columns:64px 1fr 92px 1fr 132px 104px 96px;'
      + 'gap:10px;padding:8px 12px;font-weight:600;font-size:12px;'
      + 'background:var(--f-flaeche);border:1px solid var(--rand);'
      + 'border-bottom:0;border-radius:8px 8px 0 0;'
      + 'position:sticky;top:0;z-index:2;}');
    SB.AppendLine('#v3kopf span{cursor:pointer;user-select:none;}');
    SB.AppendLine('#v3leer{padding:28px;text-align:center;'
      + 'color:var(--dezent);}');
    SB.AppendLine('</style>');
    // Anti-Blitz: die gespeicherte Theme-Wahl muss VOR dem ersten Paint
    // stehen, sonst malt der Browser erst im Systemthema und kippt
    // sichtbar um. Bei einer grossen Seite sind das Sekunden - genau der
    // Befund, der V2 am 09.09. denselben Block eingebracht hat.
    SB.AppendLine('<script>try{var t=localStorage.getItem('
      + '"sca-v3-theme");');
    SB.AppendLine('if(["light","dark","sepia"].indexOf(t)>=0)');
    SB.AppendLine('document.documentElement.setAttribute('
      + '"data-theme",t);}catch(e){}</script>');
    SB.AppendLine('</head>');
    SB.AppendLine('<body>');

    // ---- Kopf --------------------------------------------------------
    SB.AppendLine('<header class="kopf">');
    SB.AppendLine('<h1>' + H(TWorkbenchI18n.T(wtTitelFunde, ALang))
      + '</h1>');
    SB.AppendLine('<div class="sub">'
      + H(TWorkbenchI18n.T(wtUntertitelFunde, ALang)) + '</div>');
    SB.AppendLine('</header>');
    SB.AppendLine('<main>');

    // Kacheln fuellt die Seite selbst - sie stehen als leere Huelle da
    // und werden aus den Daten gerechnet. Klassennamen sind die von V2
    // (dash / kachel / zahl / wofuer): dieselbe Optik heisst dieselben
    // Klassen, sonst greift der geteilte Style-Block nicht.
    SB.AppendLine('<div id="v3kacheln" class="dash"></div>');
    SB.AppendLine('<div id="v3panels" class="panels"></div>');
    SB.AppendLine('<div class="toplisten">');
    SB.AppendLine('<div class="topliste" id="topRegeln"></div>');
    SB.AppendLine('<div class="topliste" id="topDateien"></div>');
    SB.AppendLine('</div>');
    if Gekuerzt > 0 then
      SB.AppendLine(Format('<div id="gekuerzt">'
        + TWorkbenchI18n.T(wtKuerzungsbanner, ALang) + '</div>',
        [MaxRows, Gekuerzt]));

    // ---- Suche und Chips --------------------------------------------
    SB.AppendLine('<div class="cmdbar">');
    SB.AppendLine('<input id="suche" type="search" placeholder="'
      + H(TWorkbenchI18n.T(wtSuchePlatzhalterFunde, ALang))
      + '" aria-label="' + H(TWorkbenchI18n.T(wtSucheAria, ALang))
      + '">');
    SB.AppendLine('<span><span class="kbd">Ctrl</span>+'
      + '<span class="kbd">K</span></span>');
    SB.AppendLine('<span id="zaehler"></span>');
    SB.AppendLine('<button id="reset" type="button">'
      + H(TWorkbenchI18n.T(wtFilterReset, ALang)) + '</button>');
    SB.AppendLine('<button id="btnTheme" type="button" title="'
      + H(TWorkbenchI18n.T(wtThemaWechseln, ALang)) + '">'
      + H(TWorkbenchI18n.T(wtThema, ALang)) + '</button>');
    SB.AppendLine('</div>');
    SB.AppendLine('<div id="v3chips" class="chips"></div>');

    // ---- Liste -------------------------------------------------------
    SB.AppendLine('<div id="v3kopf">');
    SB.AppendLine('<span data-s="0" class="v3-num">'
      + H(TWorkbenchI18n.T(wtSpZeile, ALang)) + '</span>');
    SB.AppendLine('<span data-s="1">'
      + H(TWorkbenchI18n.T(wtSpMethode, ALang)) + '</span>');
    SB.AppendLine('<span data-s="2">'
      + H(TWorkbenchI18n.T(wtSpScaId, ALang)) + '</span>');
    SB.AppendLine('<span data-s="3">'
      + H(TWorkbenchI18n.T(wtSpRegel, ALang)) + '</span>');
    SB.AppendLine('<span data-s="4">'
      + H(TWorkbenchI18n.T(wtSpTyp, ALang)) + '</span>');
    SB.AppendLine('<span data-s="5">'
      + H(TWorkbenchI18n.T(wtSpSchweregrad, ALang)) + '</span>');
    SB.AppendLine('<span data-s="6">'
      + H(TWorkbenchI18n.T(wtSpKonfidenz, ALang)) + '</span>');
    SB.AppendLine('</div>');
    SB.AppendLine('<div id="v3wrap" tabindex="0">');
    SB.AppendLine('<div id="v3spacer"><div id="v3rows"></div></div>');
    SB.AppendLine('<div id="v3leer" hidden>'
      + H(TWorkbenchI18n.T(wtKeineTreffer, ALang)) + '</div>');
    SB.AppendLine('</div>');

    // ---- Drawer ------------------------------------------------------
    SB.AppendLine('<aside id="drawer" class="drawer" hidden '
      + 'aria-label="' + H(TWorkbenchI18n.T(wtDrawerAriaFunde, ALang))
      + '">');
    SB.AppendLine('<button id="drawer-schliessen" type="button" '
      + 'title="' + H(TWorkbenchI18n.T(wtDrawerSchliessen, ALang))
      + '">&times;</button>');
    SB.AppendLine('<div id="drawer-inhalt"></div>');
    SB.AppendLine('</aside>');
    SB.AppendLine('</main>');

    // ---- Datenmodell -------------------------------------------------
    // Der Grund, warum es diese Seite gibt: statt 2.404 Zeichen HTML je
    // Fund stehen hier nur die Werte, und alles je Regel oder je Datei
    // Gleiche steht EINMAL.
    SB.AppendLine('<script type="application/json" id="v3daten">');
    SB.Append('{"regeln":[');
    for i := 0 to Regeln.Count - 1 do
    begin
      R := Regeln[i];
      if i > 0 then SB.Append(',');
      SB.Append('[' + JsonStr(R.ID) + ',' + JsonStr(R.Name) + ','
        + JsonStr(R.TypCss) + ',' + JsonStr(R.TypText) + ','
        + JsonStr(R.Erkannt) + ',' + JsonStr(R.Warum) + ']');
    end;
    SB.Append('],"pfade":[');
    for i := 0 to Pfade.Count - 1 do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(JsonStr(Pfade[i]));
    end;
    SB.Append('],"hinweise":[');
    for i := 0 to Hinweise.Count - 1 do
    begin
      if i > 0 then SB.Append(',');
      SB.Append(JsonStr(Hinweise[i]));
    end;
    SB.Append('],"funde":[');
    for i := 0 to Funde.Count - 1 do
    begin
      V := Funde[i];
      if i > 0 then SB.Append(',');
      SB.Append('[' + IntToStr(V.Zeile) + ',' + JsonStr(V.Methode) + ','
        + IntToStr(V.RegelIx) + ',' + IntToStr(V.PfadIx) + ','
        + IntToStr(V.SevRang) + ',' + IntToStr(V.Konf) + ','
        + JsonStr(V.Detail) + ',' + IntToStr(V.HinwIx) + ','
        + IntToStr(V.SnipAb) + ',' + IntToStr(V.SnipEin) + ',[');
      Erst := True;
      for k := 0 to High(V.Snippet) do
      begin
        if not Erst then SB.Append(',');
        Erst := False;
        SB.Append(JsonStr(V.Snippet[k]));
      end;
      SB.Append(']]');
    end;
    SB.AppendLine(']}');
    SB.AppendLine('</script>');

    SB.Append(SeitenJsV3(ALang));
    SB.AppendLine('</body>');
    SB.AppendLine('</html>');
  finally
    QuellCache.Free;
    Funde.Free;
    HinweisIx.Free;
    Hinweise.Free;
    PfadIx.Free;
    Pfade.Free;
    RegelIx.Free;
    Regeln.Free;
  end;
end;

end.
