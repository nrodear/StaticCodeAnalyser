unit uInterfaceGuid;

// SCA197 InterfaceWithoutGuid + SCA198 DuplicateInterfaceGuid.
//
// SCA197 - Interface ohne GUID
//   Ein Interface ohne GUID laesst sich nicht zur Laufzeit erfragen.
//   `Supports(Obj, IFoo, X)` und `Obj.QueryInterface(IFoo, X)` brauchen
//   beide die GUID; ohne sie ist der Typ nur zur Uebersetzungszeit da.
//   Der Compiler sagt dazu nichts - man merkt es erst, wenn jemand das
//   Interface abfragen will und der Aufruf nicht uebersetzt.
//
//   In der IDE: Cursor in die Interface-Deklaration, Strg+Umschalt+G.
//
// SCA198 - dieselbe GUID an zwei Interfaces
//   Der teurere Fall, und der Grund, warum dieses Regelpaar zusammen
//   gehoert: wer ein Interface durch Kopieren des vorigen anlegt und die
//   GUID stehen laesst, bekommt KEINEN Fehler. Er bekommt ein Programm,
//   in dem `Supports(Obj, IZweites, X)` das ERSTE Interface liefert.
//   Gefunden wird das ueblicherweise Wochen spaeter und woanders.
//
//   Die Meldung nennt deshalb die anderen Fundstellen mit Datei und
//   Zeile - eine Meldung "GUID doppelt" ohne den zweiten Ort waere hier
//   fast wertlos, weil die Suche danach die eigentliche Arbeit ist.
//
// SCOPE
//   "Doppelt" ist eine Aussage ueber den gescannten Umfang. Der Index
//   (uInterfaceGuidIndex) wird aus derselben Datei-Liste gebaut, die
//   auch analysiert wird - also Verzeichnis, Projekt (.dproj) oder
//   Projektgruppe (.groupproj), je nach Auswahl. Fehlt der Index
//   (Einzeldatei-Modus, Tests), vergleicht der Detektor nur innerhalb
//   der eigenen Datei: eine Aussage ueber das Projekt waere ohne
//   Projekt schlicht nicht gedeckt.
//
// ABGRENZUNG
//   * `IFoo = interface;` (Vorwaertsdeklaration) wird uebergangen - sie
//     DARF keine GUID tragen.
//   * `dispinterface` bleibt aussen vor (eigene Automations-Regeln).
//   * Steht in den eckigen Klammern etwas, das keine GUID-Form hat
//     (eine Konstante etwa), meldet der Detektor gar nichts: weder
//     "fehlt" noch "doppelt" waere belegbar.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TInterfaceGuidDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, IfElseBegin, TooLongLine, UnsortedUses, UnusedParameter
// UnusedParameter: UnitNode bleibt ungenutzt - dieser Detektor liest den
// Quelltext, nicht den AST (der Parser fuehrt die GUID nicht). Die
// Signatur ist von der Detektor-Registry vorgegeben.

uses
  uFileTextCache, uInterfaceGuidIndex;

const
  // So viele andere Fundstellen stehen im Meldungstext, dann folgt
  // "+N more". Drei reichen, um die Suche zu eroeffnen; eine Meldung mit
  // zwanzig Pfaden liest niemand, und in SARIF-Viewern bricht sie das
  // Layout.
  MAX_ORTE = 3;

function OrtText(const D: TInterfaceDecl): string;
begin
  Result := Format('%s (%s:%d)',
    [D.Name, ExtractFileName(D.FileName), D.Line]);
end;

function SelbeStelle(const A, B: TInterfaceDecl): Boolean;
begin
  Result := (A.Line = B.Line) and SameText(A.FileName, B.FileName);
end;

function SelbeDeklaration(const A, B: TInterfaceDecl): Boolean;
// GLEICHNAMIGKEITS-GATE (Korpusmessung 2026-08-25).
//
// Traegt dieselbe GUID an beiden Stellen auch DENSELBEN Interface-Namen,
// dann ist es nicht ein zweites Interface mit geklauter GUID, sondern
// DIESELBE Deklaration ein zweites Mal im Baum: eine mitgelieferte
// Bibliothek, ein Untermodul, ein Sicherungsordner.
//
// Das ist kein blosses Rauschen, es macht den RAT DER MELDUNG falsch.
// "Generate a new GUID with Ctrl+Shift+G" ist bei einer doppelten Unit
// genau der verkehrte Schritt - er wuerde die beiden Kopien auch noch
// unvertraeglich machen. Eine Regel, deren Empfehlung schadet, darf in
// diesem Fall nicht feuern.
//
// Gemessen am Referenzkorpus (27 Projekte, 13.268 Dateien): 1.505 der
// 1.705 SCA198-Funde waren von dieser Art, also 88 Prozent. Die doppelte
// Unit selbst bleibt unentdeckt - das ist eine andere Frage als die nach
// der GUID und braucht eine eigene Regel.
begin
  Result := SameText(A.Name, B.Name);
end;

class procedure TInterfaceGuidDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Lines   : TStringList;
  Cached  : Boolean;
  Code    : string;
  LineFor : TArray<Integer>;
  Decls   : TArray<TInterfaceDecl>;
  Index   : TInterfaceGuidIndex;
  Decl    : TInterfaceDecl;
  Andere  : TInterfaceDecl;
  Stellen : TArray<TInterfaceDecl>;
  Namen   : TStringList;
  Text    : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Ueber den Context-Cache: dieselbe Datei wird von vielen Detektoren
    // gestrippt, der Slot ist genau dafuer da.
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(
              Lines, LineFor, AContext, FileName);
    Decls := TInterfaceGuidIndex.ScanCode(FileName, Code, LineFor);
  finally
    ReleaseLines(Lines, Cached);
  end;
  if Length(Decls) = 0 then Exit;

  Index := CtxInterfaceGuidIndex(AContext);

  for Decl in Decls do
  begin
    // Eckige Klammern mit Nicht-GUID-Inhalt: nichts entscheidbar.
    if Decl.GuidUnparsed then Continue;

    if Decl.Guid = '' then
    begin
      Results.Add(TLeakFinding.New(FileName, '', Decl.Line,
        Format('Interface "%s" has no GUID - Supports() and QueryInterface() ' +
               'cannot ask for it at run time. Add one with Ctrl+Shift+G.',
               [Decl.Name]),
        fkInterfaceWithoutGuid));
      Continue;
    end;

    // Andere Stellen mit derselben GUID. Mit Index: projektweit. Ohne:
    // nur diese Datei - siehe SCOPE im Kopf.
    if Assigned(Index) and not Index.IsEmpty then
      Stellen := Index.SitesOf(Decl.Guid)
    else
      Stellen := Decls;

    Namen := TStringList.Create;
    try
      for Andere in Stellen do
      begin
        if Andere.Guid <> Decl.Guid then Continue;
        if SelbeStelle(Andere, Decl) then Continue;
        if SelbeDeklaration(Andere, Decl) then Continue;
        Namen.Add(OrtText(Andere));
      end;
      if Namen.Count = 0 then Continue;

      // Sortiert, damit zwei Laeufe ueber denselben Quelltext denselben
      // Text liefern - die Reihenfolge im Index haengt sonst an der
      // Datei-Reihenfolge des Scans.
      Namen.Sort;
      if Namen.Count <= MAX_ORTE then
        Text := string.Join(', ', Namen.ToStringArray)
      else
        Text := string.Join(', ',
                  Copy(Namen.ToStringArray, 0, MAX_ORTE)) +
                Format(', +%d more', [Namen.Count - MAX_ORTE]);

      Results.Add(TLeakFinding.New(FileName, '', Decl.Line,
        Format('Interface "%s" shares its GUID {%s} with %s - Supports() ' +
               'returns whichever was registered first. Generate a new GUID ' +
               'with Ctrl+Shift+G.',
               [Decl.Name, Decl.Guid, Text]),
        fkDuplicateInterfaceGuid));
    finally
      Namen.Free;
    end;
  end;
end;

end.
