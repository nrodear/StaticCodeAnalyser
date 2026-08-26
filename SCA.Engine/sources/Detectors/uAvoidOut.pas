unit uAvoidOut;

// Detektor fuer `out`-Parameter in Methoden-Signaturen.
//
// SonarDelphi-Aequivalent: communitydelphi:AvoidOut. `out`-Parameter
// haben in Delphi unterschiedliche Semantik je nach Typ:
//   * Managed-Typen (string, Interface, dynamic array): werden beim
//     Methoden-Entry freigegeben - der Aufrufer-Wert geht verloren bevor
//     die Methode anlauft.
//   * Records / einfache Typen: werden nicht initialisiert; auf den
//     Eingangswert zuzugreifen ist UB.
// Beides ist selten gewuenscht. `var` ist die robustere Wahl, sofern
// kein COM-Interop noetig ist.
//
// Erkennung: lexikalischer Scan. Match auf Wort `out` (case-insensitive)
// innerhalb von Klammern `(...)` einer `procedure`/`function`/`constructor`/
// `destructor`-Deklaration. Vereinfachung: matche `out ` (Wort + Whitespace
// + Ident) ohne Klammer-Kontext zu verfolgen - false-positives auf
// `out` als Identifier sind sehr selten.
//
// Schweregrad: lsHint - kein Bug per se, aber API-Design-Hint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext,
  uDetectorUtils;   // H2445: inline-Expansion braucht iface-Sichtbarkeit

type
  TAvoidOutDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, IfElseBegin, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils,
  uConstStringParameter,  // MethodHasDirective (Direktiven-Tail-Gate G1/G4)
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

  // G1/G4 (Autopsie 2026-08-26): Direktiven, die die Signatur von aussen
  // fixieren - ABI (COM/WinAPI/DLL-Grenze) oder Basisklassen-Vertrag.
  // `out` ist dort nicht Design-Wahl des Autors, `var` keine Option.
  ABI_DIRECTIVES : array[0..6] of string = (
    'stdcall', 'safecall', 'cdecl', 'external', 'varargs', 'dispid', 'winapi'
  );

function IsIdent(C: Char): Boolean; inline;
begin
  // Backlog-Welle 1, 2026-07-26: Zeichenklasse zentralisiert - die
  // lokale Fassung war zeichenweise identisch zu
  // TDetectorUtils.IsIdentChar (a..z, A..Z, 0..9, _). Der Wrapper
  // bleibt, damit die Aufrufer in dieser Unit unveraendert bleiben.
  Result := TDetectorUtils.IsIdentChar(C);
end;

// Liefert Spalte des `out`-Keywords als Parameter-Direktive (innerhalb
// `(...)`), sonst 0.
function FindOutParam(const Line: string; var InBlockComm: Boolean;
  var InParenStarComm: Boolean): Integer;
var
  i, n, j   : Integer;
  InStr     : Boolean;
  pClose    : Integer;
  c         : Char;
  ParenDep  : Integer;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  ParenDep := 0;
  while i <= n do
  begin
    if InBlockComm then
    begin
      pClose := PosEx('}', Line, i);
      if pClose = 0 then Exit;
      InBlockComm := False;
      i := pClose + 1; Continue;
    end;
    if InParenStarComm then
    begin
      pClose := PosEx('*)', Line, i);
      if pClose = 0 then Exit;
      InParenStarComm := False;
      i := pClose + 2; Continue;
    end;
    c := Line[i];
    if InStr then
    begin
      if c = '''' then
      begin
        if (i < n) and (Line[i + 1] = '''') then Inc(i, 2)
        else begin InStr := False; Inc(i); end;
      end
      else Inc(i);
      Continue;
    end;
    if c = '''' then begin InStr := True; Inc(i); Continue; end;
    if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
    if c = '{' then
    begin
      pClose := PosEx('}', Line, i + 1);
      if pClose = 0 then begin InBlockComm := True; Exit; end;
      i := pClose + 1; Continue;
    end;
    if (c = '(') and (i < n) and (Line[i + 1] = '*') then
    begin
      pClose := PosEx('*)', Line, i + 2);
      if pClose = 0 then begin InParenStarComm := True; Exit; end;
      i := pClose + 2; Continue;
    end;
    if c = '(' then begin Inc(ParenDep); Inc(i); Continue; end;
    if c = ')' then begin Dec(ParenDep); Inc(i); Continue; end;
    // Innerhalb `(...)` und Wort `out` matchen
    if (ParenDep > 0) and CharInSet(c, ['O', 'o']) and (i + 2 <= n) and
       SameText(Copy(Line, i, 3), 'out') then
    begin
      if (i > 1) and IsIdent(Line[i - 1]) then begin Inc(i); Continue; end;
      if (i + 3 <= n) and IsIdent(Line[i + 3]) then begin Inc(i); Continue; end;
      // Naechstes Nicht-Whitespace muss Ident-Start sein (Parametername)
      j := i + 3;
      while (j <= n) and CharInSet(Line[j], [' ', #9]) do Inc(j);
      if (j <= n) and CharInSet(Line[j], ['A'..'Z','a'..'z','_']) then
      begin
        // G3 (Autopsie 2026-08-26, gemessen 343 Drops): UNTYPISIERTES
        // out ('out Obj' ohne ': Typ' - QueryInterface/Supports/
        // Factory-Resolver) nicht melden. Untypisierte Parameter werden
        // vom Compiler nicht finalisiert; der Regel-Mechanismus
        // (Entry-Clear, Record-/Mehrfach-Rueckgabe als Abhilfe) greift
        // dort schlicht nicht, und 'var' waere semantisch irrefuehrend.
        // Erkennung: hinter dem Parameternamen folgt (nach WS) ';' oder
        // ')' oder das Zeilenende - kein ':' heisst kein Typ. Namens-
        // LISTEN ('out A, B: T') behalten das ',' und bleiben Fund.
        var k := j;
        while (k <= n) and IsIdent(Line[k]) do Inc(k);
        while (k <= n) and CharInSet(Line[k], [' ', #9]) do Inc(k);
        if (k > n) or CharInSet(Line[k], [';', ')']) then
        begin
          i := k;
          Continue;
        end;
        Result := i;
        Exit;
      end;
      Inc(i);
      Continue;
    end;
    Inc(i);
  end;
end;

// ---- Direktiven-Tail-Gate (G1/G2/G4, Autopsie 2026-08-26) -----------------
// Der Detektor blieb absichtlich lexikalisch; die Gates arbeiten auf der
// GEJOINTEN Deklaration (Kopfzeile rueckwaerts suchen, Folgezeilen bis
// Klammerbilanz 0 + ';' anhaengen) und lesen dann den Tail hinter der
// Parameterliste. Gemessen am rw11-Korpus (bit-treue Replika): G1-G4
// zusammen 3.393 der 9.233 Funde (36,7 %), Stichproben 8/8 + 8/8 sauber.

function StripToCode(const Line: string): string;
// Einzeilen-Strip fuer die Join-Bewertung: //-Tail ab, {..}/(*..*) raus,
// String-INHALTE geblankt (Direktivenwoerter in Literalen zaehlen nicht -
// Hausinvariante). Unvollstaendige Blockkommentare kappen die Zeile;
// FindOutParam behaelt seinen eigenen zeilenuebergreifenden Zustand.
var
  i, n, p : Integer;
  InStr   : Boolean;
begin
  Result := Line;
  n := Length(Result);
  i := 1; InStr := False;
  while i <= n do
  begin
    if InStr then
    begin
      if Result[i] = '''' then InStr := False else Result[i] := ' ';
      Inc(i); Continue;
    end;
    case Result[i] of
      '''': begin InStr := True; Inc(i); end;
      '/' : if (i < n) and (Result[i + 1] = '/') then
            begin SetLength(Result, i - 1); Exit; end
            else Inc(i);
      '{' : begin
              p := PosEx('}', Result, i + 1);
              if p = 0 then begin SetLength(Result, i - 1); Exit; end;
              Delete(Result, i, p - i + 1); n := Length(Result);
            end;
      '(' : if (i < n) and (Result[i + 1] = '*') then
            begin
              p := PosEx('*)', Result, i + 2);
              if p = 0 then begin SetLength(Result, i - 1); Exit; end;
              Delete(Result, i, p - i + 2); n := Length(Result);
            end
            else Inc(i);
    else
      Inc(i);
    end;
  end;
end;

function IsFuncPtrHead(const CleanLow: string): Boolean;
// G2: `: function(` / `= procedure(` - prozeduraler Typ bzw. Feld.
// `out` steht dort in einer TYP-Signatur (Callback-/DLL-Import-Vertrag),
// nicht in einer aenderbaren Methode.
const
  KW : array[0..1] of string = ('function', 'procedure');
var
  k, p, q, L : Integer;
begin
  Result := False;
  for k := 0 to High(KW) do
  begin
    L := Length(KW[k]);
    p := 1;
    while True do
    begin
      p := PosEx(KW[k], CleanLow, p);
      if p = 0 then Break;
      if ((p = 1) or not TDetectorUtils.IsIdentChar(CleanLow[p - 1])) and
         ((p + L > Length(CleanLow)) or not TDetectorUtils.IsIdentChar(CleanLow[p + L])) then
      begin
        q := p - 1;
        while (q >= 1) and CharInSet(CleanLow[q], [' ', #9]) do Dec(q);
        if (q >= 1) and CharInSet(CleanLow[q], [':', '=']) then Exit(True);
      end;
      p := p + L;
    end;
  end;
end;

function DeclHeadKind(const CleanLow: string): Integer;
// 0 = kein Deklarationskopf, 1 = Routinen-Kopf, 2 = Funktionszeiger-Kopf.
var
  T : string;
begin
  T := Trim(CleanLow);
  if StartsStr('class ', T) then T := Trim(Copy(T, 7, MaxInt));
  if StartsStr('procedure ', T) or StartsStr('function ', T) or
     StartsStr('constructor ', T) or StartsStr('destructor ', T) or
     StartsStr('procedure(', T) or StartsStr('function(', T) then Exit(1);
  if IsFuncPtrHead(CleanLow) then Exit(2);
  Result := 0;
end;

function TailStartsWithDirective(const TrimLow: string): Boolean;
// Fortsetzungszeile, die NUR Direktiven traegt (`  stdcall; external ...`).
var
  k : Integer;
begin
  for k := 0 to High(ABI_DIRECTIVES) do
    if StartsStr(ABI_DIRECTIVES[k], TrimLow) then Exit(True);
  Result := StartsStr('override', TrimLow);
end;

function JoinDeclLow(Lines: TStringList; Idx: Integer): string;
// Deklaration um Zeile Idx als EINEN lowercase String: Kopf bis 8 Zeilen
// rueckwaerts (FindOutParam startet seine Klammerbilanz je Zeile bei 0 -
// der Treffer kann auf einer Fortsetzungszeile liegen), dann vorwaerts
// bis Klammerbilanz <= 0 und ';' hinter der Parameterliste; eine reine
// Direktiven-Folgezeile (`  stdcall;`) wird noch mitgenommen.
var
  k, HeadIdx, Lo, Hi, Bal, c : Integer;
  L : string;
begin
  HeadIdx := Idx;
  Lo := Idx - 8; if Lo < 0 then Lo := 0;
  for k := Idx downto Lo do
    if DeclHeadKind(LowerCase(StripToCode(Lines[k]))) > 0 then
    begin HeadIdx := k; Break; end;

  Result := '';
  Bal := 0;
  Hi := HeadIdx + 16; if Hi > Lines.Count - 1 then Hi := Lines.Count - 1;
  for k := HeadIdx to Hi do
  begin
    L := StripToCode(Lines[k]);
    Result := Result + ' ' + L;
    for c := 1 to Length(L) do
      if L[c] = '(' then Inc(Bal) else if L[c] = ')' then Dec(Bal);
    if (k >= Idx) and (Bal <= 0) and
       (LastDelimiter(';', Result) > LastDelimiter(')', Result)) then
    begin
      if (k < Hi) and TailStartsWithDirective(Trim(LowerCase(StripToCode(Lines[k + 1])))) then
        Result := Result + ' ' + StripToCode(Lines[k + 1]);
      Break;
    end;
  end;
  Result := LowerCase(Result);
end;

function DeclTail(const JoinedLow: string): string;
// Alles hinter der schliessenden Klammer der Parameterliste - dort
// stehen Rueckgabetyp und Direktiven.
var
  p : Integer;
begin
  p := LastDelimiter(')', JoinedLow);
  Result := Copy(JoinedLow, p + 1, MaxInt);
end;

function DeclBareName(const JoinedLow: string; out HasDot: Boolean): string;
// Routinen-Name der gejointen Decl; bei qualifizierten Impl-Koepfen
// (`procedure tfoo.bar(`) das LETZTE Segment. HasDot unterscheidet
// Interface-Decl (ohne Punkt) vom Implementations-Zwilling (mit Punkt).
// Generic-Segmente werden UEBERSPRUNGEN (Gegenpruefung 2026-08-26:
// `procedure tcache<t>.tryget(` stoppte am '<', HasDot blieb False,
// der G4-Zwilling war fuer generische Klassen wirkungslos -
// MVCFramework.LRUCache.pas:145 als Korpus-Beleg).
const
  HEADS : array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
var
  h, p, q, L, Seg, SegEnd, Depth : Integer;
begin
  Result := ''; HasDot := False;
  L := Length(JoinedLow);
  p := 0;
  for h := 0 to High(HEADS) do
  begin
    q := Pos(HEADS[h] + ' ', JoinedLow);
    if (q > 0) and ((p = 0) or (q < p)) then p := q + Length(HEADS[h]) + 1;
  end;
  if p = 0 then Exit;
  while (p <= L) and (JoinedLow[p] = ' ') do Inc(p);
  Seg := p; SegEnd := p;
  q := p;
  while q <= L do
  begin
    if TDetectorUtils.IsIdentChar(JoinedLow[q]) then
    begin
      Inc(q); SegEnd := q;
    end
    else if JoinedLow[q] = '<' then
    begin
      Depth := 1; Inc(q);
      while (q <= L) and (Depth > 0) do
      begin
        if JoinedLow[q] = '<' then Inc(Depth)
        else if JoinedLow[q] = '>' then Dec(Depth);
        Inc(q);
      end;
    end
    else if JoinedLow[q] = '.' then
    begin
      HasDot := True; Inc(q); Seg := q; SegEnd := q;
    end
    else
      Break;
  end;
  Result := Copy(JoinedLow, Seg, SegEnd - Seg);
end;

class procedure TAvoidOutDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines  : TStringList;
  i, Col, d : Integer;
  InBlk, InParen : Boolean;
  Cached : Boolean;
  Twins  : TDictionary<string, Boolean>;
  JoinedLow, TailLow, BareName : string;
  Abi, Ovr, HasDot : Boolean;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  Twins := TDictionary<string, Boolean>.Create;
  try
    InBlk   := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Col := FindOutParam(Lines[i], InBlk, InParen);
      if Col <= 0 then Continue;

      // G1/G2/G4: Tail der gejointen Deklaration befragen.
      JoinedLow := JoinDeclLow(Lines, i);
      TailLow   := DeclTail(JoinedLow);
      Abi := False;
      for d := 0 to High(ABI_DIRECTIVES) do
        if MethodHasDirective(TailLow, ABI_DIRECTIVES[d]) then
        begin Abi := True; Break; end;
      Ovr := MethodHasDirective(TailLow, 'override');
      BareName := DeclBareName(JoinedLow, HasDot);

      if Abi or Ovr then
      begin
        // Zwilling vormerken: der gleichnamige Implementations-Kopf
        // wiederholt override/Konvention NICHT und wuerde sonst als
        // zweiter Fund stehen bleiben (Beleg uwinnetfilesource:153/208).
        if (not HasDot) and (BareName <> '') then
          Twins.AddOrSetValue(BareName, True);
        Continue;
      end;
      if IsFuncPtrHead(JoinedLow) then Continue;   // G2
      if HasDot and (BareName <> '') and Twins.ContainsKey(BareName) then
        Continue;                                  // G4-Zwilling

      Results.Add(TLeakFinding.New(FileName, '', i + 1,
        Format('`out` parameter at column %d - prefer `var` (out clears ' +
               'managed types on entry, leaves records uninitialized).',
          [Col]),
        fkAvoidOut));
    end;
  finally
    Twins.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
