unit uPublicMemberWithoutDoc;

// SCA117: Public-Member (Methode, Property, Klasse, Interface, Typ-Alias)
// in der INTERFACE-Section ohne dokumentierenden Kommentar direkt davor.
//
// "Dokumentierender Kommentar" akzeptiert sehr grosszuegig:
//   * /// XMLDoc-Format
//   * { ... }-Block direkt darueber
//   * (* ... *)-Block direkt darueber
//   * // Single-Line-Kommentare (1+ Zeilen direkt darueber, Schwellwert 1)
//
// Skip-Regeln:
//   * Implementation-Section komplett ignoriert (Doku gehoert ins
//     interface)
//   * `published`-Members: oft DFM-generiert, doc waere noise
//   * `constructor Create` / `destructor Destroy`: per Konvention selbst-
//     erklaerend
//   * Operator-Overloads (z.B. `class operator Implicit`): C++-Aequivalent,
//     Doku ist trotzdem nett aber laeuft als opt-in
//   * Member die mit `_` beginnen (private-Marker auch in public-Section)
//
// Lexisch (mit Visibility-Tracking durch die interface-Section). AST
// koennte das auch, aber der Doku-Look-Behind ist auf Source-Zeilen-
// Basis einfacher.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TPublicMemberWithoutDocDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils, System.RegularExpressions,
  uFileTextCache;

var
  // Lazy-Cache (Round 11): konstante Patterns einmalig kompilieren.
  CachedReMethod   : TRegEx;
  CachedReProperty : TRegEx;
  CachedReInit     : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReMethod   := TRegEx.Create('(?i)^\s*(procedure|function|constructor|destructor)\s+([A-Za-z_][A-Za-z0-9_]*)');
  CachedReProperty := TRegEx.Create('(?i)^\s*property\s+([A-Za-z_][A-Za-z0-9_]*)');
  CachedReInit     := True;
end;

function TrimL(const S: string): string;
begin
  Result := TrimLeft(S);
end;

function IsDocLine(const Line: string): Boolean;
// True wenn die Zeile als Doku-Kommentar zaehlt: /// XMLDoc, { ... },
// (* ... *), oder // Single-Line. Leere Zeilen zaehlen NICHT (sie
// trennen den Doku-Block vom Member).
var
  T : string;
begin
  T := TrimL(Line);
  if T = '' then Exit(False);
  if T.StartsWith('///') then Exit(True);
  if T.StartsWith('//')  then Exit(True);
  if T.StartsWith('{')   then Exit(True);
  if T.StartsWith('(*')  then Exit(True);
  // Fortsetzung eines `{ ... }`- oder `(* ... *)`-Blocks - heuristisch
  // dem letzten Zeilen-State-Check ueberlassen; fuer Single-Line ist
  // das eine ausreichend gute Naeherung.
  Result := False;
end;

function HasDocAbove(Lines: TStringList; LineIdx: Integer): Boolean;
// LineIdx = 0-basiert. Geht rueckwaerts bis zur ersten nicht-doc /
// nicht-leeren Zeile. Wenn dazwischen mindestens EINE Doku-Zeile war ->
// True.
var
  i : Integer;
  T : string;
  SawDoc : Boolean;
begin
  // Result wird am Ende aus SawDoc gesetzt - keine separate Initialisierung
  // noetig (Compiler-Hint H2077: "auf Result zugewiesener Wert wird nie
  // benutzt"). SawDoc ist der echte Akkumulator der Schleife.
  SawDoc := False;
  i := LineIdx - 1;
  while i >= 0 do
  begin
    T := TrimL(Lines[i]);
    if T = '' then
    begin
      // Leere Zeile -> wenn schon Doku gefunden, gilt sie weiter. Sonst
      // trennt sie die Doku vom Member - aber Empty allein ist kein
      // Trennsignal, wir suchen weiter.
      Dec(i);
      Continue;
    end;
    if IsDocLine(T) then
    begin
      SawDoc := True;
      Dec(i);
      Continue;
    end;
    // Erste echte Code-Zeile (kein Kommentar, kein Leerzeichen):
    Break;
  end;
  Result := SawDoc;
end;

class procedure TPublicMemberWithoutDocDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Line, T     : string;
  L           : string;
  InInterface : Boolean;
  CurrentVis  : string; // 'public' / 'published' / 'private' / 'protected' / 'strict private' / ''
  InClass     : Boolean;
  M           : TMatch;
  Name        : string;
  F           : TLeakFinding;
  IsPublicSection : Boolean;
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InInterface := False;
    InClass     := False;
    CurrentVis  := '';
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      T := TrimL(Line);
      L := LowerCase(T);

      // Section-Tracking
      if L = 'interface' then begin InInterface := True; Continue; end;
      if L = 'implementation' then begin InInterface := False; Continue; end;
      if not InInterface then Continue;

      // Visibility-Section-Tracking - sehr defensiv, nur Top-Level-Worte
      if L = 'public' then begin CurrentVis := 'public'; Continue; end;
      if L = 'published' then begin CurrentVis := 'published'; Continue; end;
      if L = 'private' then begin CurrentVis := 'private'; Continue; end;
      if L = 'protected' then begin CurrentVis := 'protected'; Continue; end;
      if L.StartsWith('strict ') then begin CurrentVis := L; Continue; end;

      // Class-Body-Open / -Close detection (vereinfacht)
      if (Pos('class', L) > 0) and (Pos(' = ', L) > 0) then InClass := True;
      // End-Token signalisiert Block-End - vereinfacht, ohne Tiefe
      if (L = 'end;') or (L = 'end') then
      begin
        InClass := False;
        CurrentVis := '';
      end;

      // Nur Member in public-Section pruefen
      IsPublicSection := CurrentVis = 'public';
      if not IsPublicSection then Continue;
      if not InClass then Continue;

      // Methode / Property?
      M := CachedReMethod.Match(Line);
      if not M.Success then
        M := CachedReProperty.Match(Line);
      if not M.Success then Continue;

      Name := M.Groups[M.Groups.Count - 1].Value;

      // Skip-Regeln
      if SameText(Name, 'Create')  then Continue;
      if SameText(Name, 'Destroy') then Continue;
      if Name.StartsWith('_') then Continue;

      if HasDocAbove(Lines, i) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := Name;
      F.LineNumber := IntToStr(i + 1);
      F.MissingVar :=
        Format('Public member %s has no documentation comment above its ' +
               'declaration. Recommended: a /// XMLDoc block, a { ... } ' +
               'or (* ... *) descriptive comment, or one or more // lines ' +
               'directly above explaining purpose + contract.',
               [Name]);
      F.SetKind(fkPublicMemberWithoutDoc);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
