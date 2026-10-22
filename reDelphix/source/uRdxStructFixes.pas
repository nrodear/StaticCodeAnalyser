unit uRdxStructFixes;

// reDelphix - Editorhilfen der Stufe 3 (Konzept_Editorhilfen_2026-10-08):
// Planer an Strukturen ueber mehrere Token oder Zeilen, OHNE ToolsAPI und
// ohne Parser. Die Bereiche der uses-Eintraege liefert der Aufrufer
// (TSourcePlaces.UsesEntries); alles andere liest die Code-Sicht.
//   SCA007 UnusedUses: einen Eintrag aus der uses-Klausel loeschen.
//   SCA168 DefaultCaseInCaseStatement: vor das end des case ein else setzen
//          - leer oder mit raise (Nico 2026-10-10: beide als Eintraege).
//   SCA101 BeginEndRequired, SCA099 IfElseBegin: die Anweisung hinter
//          then/else/do in begin..end setzen (Entscheid E7).
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche.
// Geloescht wird nichts, was einen Kommentar oder eine Direktive traegt -
// ausser dem '//'-Kommentar hinter einem Eintrag, der allein auf seiner
// Zeile steht (er gehoert zum Eintrag).

interface

uses
  uRefactorInfo,   // TRefactorSpan in TRdxUsesClause
  uRdxBufferMath, uRdxCodeMap;

const
  // Die raise-Variante von SCA168 (Katalog-Beispiel). EInvalidOpException
  // steht in System.SysUtils (Delphi 12 und 13 Zeile 476) und in SysUtils
  // von FPC 3.2.2 (sysutilh.inc) - die Hilfe gilt deshalb auch in Dateien
  // mit FPC-Weiche. Bis 2026-10-22 stand hier
  // EProgrammerError: die Klasse gibt es in keiner RTL (nur
  // EProgrammerNotFound), der Klick brach den Bau (E2003). Eine
  // EArgumentException-Unterklasse waere enger und finge sich in
  // 'on E: EArgumentException' - ein unbehandelter Wert ist aber kein
  // falsches Argument, sondern ein Zustand, den das case nicht vorsieht.
  RAISE_UNHANDLED = 'raise EInvalidOpException.Create(''Unhandled case'');';

type
  // Eine uses-Klausel: die Eintraege (TSourcePlaces.UsesEntries, in
  // Quelltext-Reihenfolge) und die Zeile des Schluesselworts 'uses'.
  TRdxUsesClause = record
    Entries  : TArray<TRefactorSpan>;
    UsesLine : Integer;
  end;

  // Die Planer an Strukturen ueber mehrere Token oder Zeilen (SCA007,
  // SCA168, SCA101/SCA099) und ihre geteilten Bausteine (StartsStatementAt,
  // ElseBelongsToIf): reine Textlogik auf der Code-Sicht. Die uses-Eintraege,
  // die FPC-Weiche und die uses-Ergaenzung fuer EInvalidOpException liefert
  // bzw. prueft der Aufrufer (uRdxFixRunner: TRdxFixRunner.UnusedUsesFix
  // bzw. CaseRaiseFix).
  TRdxStructFixes = class
  public
    // SCA007: den Eintrag AIndex der Klausel loeschen. Vor dem letzten
    // Eintrag: bis zum Anfang des naechsten (Name, 'in'-Pfad, Komma,
    // Leerraum) - steht er allein auf seiner Zeile, die ganze Zeile samt
    // '//'-Kommentar; der letzte: ab dem Komma davor bis vor das ';'; der
    // einzige: die ganze Klausel ab 'uses' bis hinter ';' - ganze Zeilen,
    // wenn sie allein stehen. Kein Kommentar und keine Direktive im
    // Bereich, und darin steht genau dieser Eintrag mit einem Trenner (ein
    // Eintrag, den UsesEntries ausliess, ginge sonst mit).
    class function RemoveUsesEntry(AMap: TRdxCodeMap;
      const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA168: ein else vor das end des case-Statements auf Zeile ALine
    // (genau ein 'case' im Code der Zeile). AStatement = '': leer ('else'
    // vor 'end', bedeutungsgleich); sonst diese Anweisung im else-Zweig
    // (RAISE_UNHANDLED), eingerueckt wie die Arme. Das end findet ein
    // Token-Lauf (begin/case/try/asm/record zaehlen hoch, end herunter;
    // '&End' und '@@End' nicht). Endet der letzte Arm nicht auf ';', kommt
    // als zweite Ersetzung ein ';' dahinter - sonst bande das else an ein
    // offenes if ('1: if B then DoA' + 'else'). Keine Hilfe bei einer
    // Direktive zwischen case und end, bei einem else oder (FPC) otherwise
    // hinter ';', bei einem case ohne Zweige und bei einem case, das keine
    // Anweisung ist - im Variantenteil eines Records (CaseContextReason).
    class function CaseElse(AMap: TRdxCodeMap; ALine: Integer;
      const AStatement: string; out AEdits: TArray<TRdxEdit>;
      out AReason: string): Boolean; static;

    // SCA101: das then, else oder do, das an (ALine, ACol) beginnt - die
    // Spalte aus der Meldung.
    class function BranchKeywordAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out AKeyword: TRdxToken; out AReason: string): Boolean; static;

    // SCA099: das else hinter dem einen 'end else' auf ALine (das else darf
    // auf einer Folgezeile stehen).
    class function ElseAfterEndOn(AMap: TRdxCodeMap; ALine: Integer;
      out AKeyword: TRdxToken; out AReason: string): Boolean; static;

    // SCA101 und SCA099: die Anweisung hinter AKeyword (then, else, do) in
    // begin..end setzen - bedeutungsgleich. Sie endet mit ';' (das bleibt
    // in ihr, das end bekommt eines) oder vor else/end/until/except/finally
    // (sie bekommt ein ';', das end keines). Hinter dem else eines case
    // oder except steht eine Anweisungsliste: dann alles bis vor dessen end.
    // Form: endet die Zeile des Schluesselworts mit ihm und die letzte Zeile
    // der Anweisung mit ihr, kommen begin und end in eigene Zeilen
    // (eingerueckt wie die Zeile des if/for/while/with/on bzw. des else);
    // steht die Anweisung ganz auf der Zeile des Schluesselworts, kommt sie
    // eine Stufe tiefer in eine eigene Zeile; sonst inline. Keine Hilfe bei
    // einem bedingten Ausdruck (Delphi 13: 'X := if A then B else C'), bei
    // Struktur, anonymer Methode oder Inline-Deklaration in der Anweisung,
    // bei einer Direktive im Bereich, bei schon vorhandenem begin und bei
    // einer leeren Anweisung.
    class function WrapInBlock(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
      out AEdits: TArray<TRdxEdit>; out AReason: string): Boolean; static;

    // Beginnt an ATok eine Anweisung? Davor ein Anweisungsanfang
    // (STATEMENT_PREV); ist es then oder else, muss auch das if davor eine
    // beginnen (kein bedingter Ausdruck, Delphi 13), ein ':' darf nicht in
    // Klammern stehen ('Write(X: ...)'). Geteilt mit SCA120 (uRdxRaiseFixes).
    class function StartsStatementAt(AMap: TRdxCodeMap;
      const ATok: TRdxToken): Boolean; static;

    // Gehoert das else AElse zu einem if? Dieselbe Rueckwaerts-Suche wie
    // WrapInBlock (dangling else, Bloecke uebersprungen). False mit Grund,
    // wenn es zu case/except gehoert (dahinter steht eine Anweisungsliste)
    // oder der Besitzer unklar ist. Geteilt mit SCA080 (uRdxFlowFixes:
    // 'else Exit;').
    class function ElseBelongsToIf(AMap: TRdxCodeMap; const AElse: TRdxToken;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  SPAN_007 = 'sca007';
  SPAN_168 = 'sca168';
  SPAN_101 = 'sca101';
  BRANCH_KEYWORDS: array[0..2] of string = ('then', 'else', 'do');
  // Vor diesen Token endet eine Anweisung ohne ';'.
  BRANCH_STOPPERS: array[0..4] of string = ('else', 'end', 'until',
    'except', 'finally');
  // In der einfachen Anweisung hinter then/else/do gesperrt: eine Struktur
  // (ihr Ende sucht die Hilfe nicht), ein bedingter Ausdruck (Delphi 13),
  // eine anonyme Methode (ihr Rumpf traegt ';') und eine Inline-
  // Deklaration (begin..end engte ihren Gueltigkeitsbereich ein).
  NOT_IN_BRANCH: array[0..16] of string = ('if', 'then', 'do', 'of',
    'begin', 'case', 'try', 'asm', 'record', 'repeat', 'while', 'for',
    'with', 'procedure', 'function', 'var', 'const');
  // In einer Anweisungsliste (else eines case/except) gesperrt.
  INLINE_DECLS: array[0..1] of string = ('var', 'const');
  // Rueckwaerts ohne Besitzer bis zu diesem Wort (oder ';'): die Suche endet.
  OWNER_STOPS: array[0..9] of string = ('begin', 'end', 'then', 'else',
    'do', 'of', 'try', 'repeat', 'except', 'finally');
  IF_OWNERS: array[0..0] of string = ('if');
  DO_OWNERS: array[0..3] of string = ('for', 'while', 'with', 'on');
  // Ein else hinter ';' oder diesen Woertern (oberste Ebene) gehoert zu
  // case/except.
  LIST_ELSE_OWNERS: array[0..2] of string = ('of', 'case', 'except');
  // Obergrenze fuer then/else-Spruenge rueckwaerts (StartsStatement) - eine
  // else-if-Kette ist so lang wie ihre Zweige.
  MAX_HOPS = 10000;
  // Hier endet die Suche nach dem Besitzer eines else ohne Fund (auf
  // oberster Ebene; repeat..until wird wie begin..end uebersprungen).
  ELSE_STOPS: array[0..4] of string = ('begin', 'try', 'asm', 'repeat',
    'finally');
  // Deklarationen: rueckwaerts hinter einem ';' der Kopf einer anonymen
  // Methode (Gegen-Review SCA101, Blocker 1).
  DECL_WORDS: array[0..5] of string = ('procedure', 'function', 'var',
    'const', 'type', 'label');
  // Hinter 'end else' meldet uIfElseBegin diese Woerter nicht.
  SCA099_ALLOWED: array[0..7] of string = ('begin', 'if', 'case', 'try',
    'for', 'while', 'repeat', 'with');
  // Rueckwaerts vor einem ':' auf oberster Ebene: Anfang einer Anweisung -
  // der ':' ist eine case-Marke oder ein Label (ColonInParens).
  COLON_STOPS: array[0..9] of string = ('begin', 'of', 'then', 'else', 'do',
    'try', 'except', 'finally', 'repeat', 'end');
  // Vor 'on' eines Handlers steht ';' oder except - sonst ist On ein
  // Bezeichner ('while not On do').
  HANDLER_PREV: array[0..1] of string = (';', 'except');
  // Rueckwaerts vor einem case auf oberster Ebene: hier beginnt der
  // Abschnitt einer Unit, in dem Anweisungen stehen (CaseContextReason;
  // begin/try/repeat/asm/case zaehlen als Block).
  STATEMENT_SECTIONS: array[0..1] of string = ('initialization',
    'finalization');
  R_CASE_IN_RECORD = 'das case steht im Variantenteil eines Records - kein '
    + 'case-Statement (Fund verschoben? Datei neu pruefen)';
  R_CASE_OPEN_PAREN = 'zwischen einer offenen ( und dem case steht eine '
    + 'Compiler-Direktive - ein Zweig kann die Klammer offen lassen, ob das '
    + 'case eine Anweisung ist, ist unklar';
  R_BRANCH_MOVED = 'kein then/else/do an der gemeldeten Stelle - Zeile '
    + 'verschoben? Datei neu pruefen';
  R_NO_ELSE_OWNER = 'kein if, case oder except zum else gefunden';

type
  // Code-Token eines Bereichs nach Art (CountRangeTokens).
  TRangeTokens = record
    Words  : Integer;   // ohne 'in' und 'uses'
    Dots   : Integer;
    Commas : Integer;
    Semis  : Integer;
    Others : Integer;
  end;

  // Die Anweisung hinter then/else/do (WrapInBlock).
  TRdxBranch = record
    Keyword  : TRdxToken;
    First    : TRdxToken;   // ihr erstes Token
    Stop     : TRdxToken;   // ohne ';': das Token dahinter (else, end ...)
    LastLine : Integer;     // ihr letztes Zeichen aus Code oder String -
    LastCol  : Integer;     //   bei HasSemi das ';'
    HasSemi  : Boolean;
    IsList   : Boolean;     // else eines case/except: Liste bis vor das end
    Indent   : string;      // fuer begin und end
    // Erste Zeile der Direktiven-Pruefung: die des Schluesselworts, beim
    // else die des Tokens, das seinen Besitzer entschied (then, of, except).
    CheckFrom : Integer;
  end;

  // Wem ein else gehoert (ElseOwner).
  TRdxElseOwner = (eoUnknown, eoIf, eoList);

  // Die Rueckwaerts-Suche nach dem Besitzer eines else: offene Bloecke
  // (end bzw. until ohne Anfang), else ohne then und ob schon ein ';' auf
  // oberster Ebene dahinter liegt; das Ergebnis in Owner und Decider (das
  // then bzw. of/case/except) oder Reason. Die Schritte liefern True, wenn
  // die Suche endet.
  TRdxElseScan = record
    Block     : Integer;
    Pending   : Integer;
    AfterSemi : Boolean;
    Owner     : TRdxElseOwner;
    Decider   : TRdxToken;
    Reason    : string;
    function StepWord(const T: TRdxToken): Boolean;     // ein Schluesselwort
    function StepTopWord(const T: TRdxToken): Boolean;  // ... auf oberster Ebene
    function StepSymbol(const T: TRdxToken): Boolean;   // ein Satzzeichen
    function TakeThen(const T: TRdxToken): Boolean;
    function TakeList(const T: TRdxToken): Boolean;
    function Fail(const AReason: string): Boolean;
  end;

// Wem ein else gehoert (Rumpf unten bei TRdxElseScan) - vorab, weil die
// end-Bilanz von SCA168 (TopLevelReason) es braucht.
function ElseOwner(AMap: TRdxCodeMap; const AElse: TRdxToken): TRdxElseScan;
  forward;

{ ---- SCA007 ---- }

// Das Token hinter dem uses-Eintrag: ',' oder ';' - ein 'in'-Pfad
// dazwischen ('X in ''x.pas''') wird uebersprungen (Strings sieht der
// Token-Leser nicht).
function SeparatorAfter(AMap: TRdxCodeMap; const AEntry: TRefactorSpan): TRdxToken;
begin
  Result := NextToken(AMap, AEntry.EndLine, AEntry.EndCol);
  if Result.Low = 'in' then
    Result := After(AMap, Result);
end;

// Steht hinter ASemi auf seiner Zeile nur Leerraum oder ein '//'-Kommentar
// ohne Marker (MarkerReason: noinspection, Absichtsmarker - ein
// '// noinspection X' hinter Code gilt der naechsten Zeile und bleibt)?
function TailFreeAfter(AMap: TRdxCodeMap; const ASemi: TRdxToken): Boolean;
var
  L    : string;
  Rest : Integer;
begin
  L := AMap.Raw(ASemi.Line);
  Rest := SkipBlanks(L, ASemi.EndCol);
  Result := (Rest > Length(L))
    or ((Rest = AMap.LineCommentCol(ASemi.Line))
        and (MarkerReason(Copy(L, Rest, MaxInt)) = ''));
end;

// Der einzige Eintrag: die ganze Klausel ab 'uses' (auf Zeile AUsesLine)
// bis hinter ASemi; ACheck ist der Teil, in dem kein Kommentar stehen darf
// ('uses' bis ';'). Folgt ';' nur Leerraum oder ein '//'-Kommentar ohne
// Marker (TailFreeAfter): steht 'uses' am Zeilenanfang, ganze Zeilen - der
// Kommentar beschrieb den Eintrag (bis zur Review Woche G07-23 blieb er
// als Zeile ' // x' stehen); steht davor Code, geht der Leerraum vor
// 'uses' mit ('interface uses A;' -> 'interface', bis dahin 'interface ').
// '' oder der Grund.
function WholeClauseSpan(AMap: TRdxCodeMap; AUsesLine: Integer;
  const ASemi: TRdxToken; out ASpan, ACheck: TRefactorSpan): string;
var
  T   : TRdxToken;
  L   : string;
  Col : Integer;
begin
  Result := '';
  ASpan := Default(TRefactorSpan);
  ACheck := Default(TRefactorSpan);
  T := NextToken(AMap, AUsesLine, 1);
  while (T.Low <> '') and (T.Line = AUsesLine) and (T.Low <> 'uses') do
    T := After(AMap, T);
  if (T.Low <> 'uses') or (T.Line <> AUsesLine) then
    Exit('Schluesselwort uses nicht auf der erwarteten Zeile');
  ACheck := TRefactorSpan.Make(SPAN_007, T.Line, T.Col, ASemi.Line,
    ASemi.EndCol);
  ASpan := ACheck;
  if not TailFreeAfter(AMap, ASemi) then Exit;
  L := AMap.Raw(T.Line);
  if SkipBlanks(L, 1) = T.Col then
  begin
    if ASemi.Line < AMap.LineCount then
      ASpan := TRefactorSpan.Make(SPAN_007, T.Line, 1, ASemi.Line + 1, 1);
    Exit;
  end;
  Col := T.Col;
  while (Col > 1) and IsBlank(L[Col - 1]) do
    Dec(Col);
  ASpan := TRefactorSpan.Make(SPAN_007, T.Line, Col, ASemi.Line, ASemi.EndCol);
end;

// Der zu loeschende Bereich des Eintrags AIndex (s. RemoveUsesEntry) und
// der Teil davon, in dem kein Kommentar stehen darf (ACheck - nur beim
// einzigen Eintrag kleiner, WholeClauseSpan); ASep ist das Token hinter
// ihm. '' oder der Grund. GRENZE (Review Woche G07-23 c): im Stil 'Komma
// voran' ('  A' / '  , C;') bleibt beim letzten Eintrag '  ;' als eigene
// Zeile - der Schnitt muesste auf dem letzten Zeichen von A beginnen
// (SpanFits) und es neu schreiben; uebersetzt, nur ein Schoenheitsfehler.
function EntrySpan(AMap: TRdxCodeMap; const AClause: TRdxUsesClause;
  AIndex: Integer; const ASep: TRdxToken;
  out ASpan, ACheck: TRefactorSpan): string;
var
  E    : TArray<TRefactorSpan>;
  Prev : TRdxToken;
begin
  Result := '';
  ASpan := Default(TRefactorSpan);
  ACheck := Default(TRefactorSpan);
  E := AClause.Entries;
  if Length(E) = 1 then
  begin
    if ASep.Low <> ';' then
      Exit('hinter dem einzigen Eintrag steht kein ";"');
    Exit(WholeClauseSpan(AMap, AClause.UsesLine, ASep, ASpan, ACheck));
  end;
  if AIndex < High(E) then
  begin
    if ASep.Low <> ',' then
      Exit('hinter dem Eintrag steht kein ","');
    ASpan := TRefactorSpan.Make(SPAN_007, E[AIndex].StartLine,
      E[AIndex].StartCol, E[AIndex + 1].StartLine, E[AIndex + 1].StartCol);
    ACheck := ASpan;
    Exit;
  end;
  Prev := SeparatorAfter(AMap, E[AIndex - 1]);
  if (Prev.Low <> ',') or (ASep.Low <> ';') then
    Exit('Komma vor bzw. Semikolon hinter dem letzten Eintrag nicht gefunden');
  ASpan := TRefactorSpan.Make(SPAN_007, Prev.Line, Prev.Col, ASep.Line, ASep.Col);
  ACheck := ASpan;
end;

// Steht der Eintrag allein auf seiner Zeile - davor nur Leerraum, dahinter
// sein ',' und hoechstens ein '//'-Kommentar (Stil 'System.Classes,
// // Grund')?
function OwnLine(AMap: TRdxCodeMap; const AEntry: TRefactorSpan;
  const ASep: TRdxToken): Boolean;
var
  L    : string;
  Rest : Integer;
begin
  L := AMap.Raw(AEntry.StartLine);
  Rest := SkipBlanks(L, ASep.EndCol);
  Result := (SkipBlanks(L, 1) = AEntry.StartCol) and (ASep.Low = ',')
    and (ASep.Line = AEntry.StartLine) and (AEntry.StartLine < AMap.LineCount)
    and ((Rest > Length(L)) or (Rest = AMap.LineCommentCol(AEntry.StartLine)));
end;

// Die Code-Token im Bereich nach Art gezaehlt (Strings und Kommentare
// sieht der Token-Leser nicht).
function CountRangeTokens(AMap: TRdxCodeMap;
  const ASpan: TRefactorSpan): TRangeTokens;
var
  T : TRdxToken;
begin
  Result := Default(TRangeTokens);
  T := NextToken(AMap, ASpan.StartLine, ASpan.StartCol);
  while (T.Low <> '') and ((T.Line < ASpan.EndLine)
     or ((T.Line = ASpan.EndLine) and (T.Col < ASpan.EndCol))) do
  begin
    if T.Low = '.' then
      Inc(Result.Dots)
    else if T.Low = ',' then
      Inc(Result.Commas)
    else if T.Low = ';' then
      Inc(Result.Semis)
    else if not T.IsWord then
      Inc(Result.Others)
    else if (T.Low <> 'in') and (T.Low <> 'uses') then
      Inc(Result.Words);
    T := After(AMap, T);
  end;
end;

// Darf ASpan geloescht werden? Kein Kommentar und keine Direktive in
// ACheck, und in ASpan steht genau der Eintrag AName (seine Namensteile)
// mit einem Trenner. '' oder der Grund.
function RangeReason(AMap: TRdxCodeMap; const ASpan, ACheck: TRefactorSpan;
  const AName: string): string;
var
  C        : TRangeTokens;
  Parts, i : Integer;
begin
  Result := '';
  if CommentInRange(AMap, ACheck) then
    Exit('Kommentar oder Direktive im zu loeschenden Bereich');
  Parts := 1;
  for i := 1 to Length(AName) do
    if AName[i] = '.' then
      Inc(Parts);
  C := CountRangeTokens(AMap, ASpan);
  if (C.Words <> Parts) or (C.Dots <> Parts - 1) or (C.Others <> 0)
     or (C.Commas + C.Semis <> 1) then
    Result := 'im Bereich steht mehr als dieser Eintrag - ginge ein '
      + 'weiterer mit? Datei neu pruefen';
end;

class function TRdxStructFixes.RemoveUsesEntry(AMap: TRdxCodeMap;
  const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  E           : TRefactorSpan;
  Sep         : TRdxToken;
  Span, Check : TRefactorSpan;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if (AIndex < 0) or (AIndex > High(AClause.Entries)) then
  begin
    AReason := 'kein solcher uses-Eintrag';
    Exit;
  end;
  E := AClause.Entries[AIndex];
  Sep := SeparatorAfter(AMap, E);
  AReason := EntrySpan(AMap, AClause, AIndex, Sep, Span, Check);
  if AReason <> '' then Exit;
  if (AIndex < High(AClause.Entries)) and OwnLine(AMap, E, Sep) then
  begin
    Span := TRefactorSpan.Make(SPAN_007, E.StartLine, 1, E.StartLine + 1, 1);
    Check := TRefactorSpan.Make(SPAN_007, E.StartLine, 1, E.StartLine,
      Sep.EndCol);
  end;
  AReason := RangeReason(AMap, Span, Check, E.Resolved);
  if AReason <> '' then Exit;
  AEdit.Span := Span;
  AEdit.Expected := RangeText(AMap, Span);
  AEdit.NewText := '';
  Result := True;
end;

{ ---- SCA168 ---- }

// Das Wort 'case' als Schluesselwort (OneTokenOnLine, CaseTokenOn) -
// 'Obj.&Case(1)' und 'X.Case' sind Bezeichner (IsKeywordAfter, wie die
// Haken der Bilanz; bis zur Review Woche G07-24 zaehlte jedes 'case', und
// ein verschobener Fund auf 'Obj.&Case(1);' schrieb ein else vor das end
// der Routine).
function IsCaseWord(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := (T.Low = 'case') and IsKeywordAfter(T, Before(AMap, T));
end;

// Das eine 'case' im Code der Zeile ALine. '' oder der Grund.
function CaseTokenOn(AMap: TRdxCodeMap; ALine: Integer;
  out ACase: TRdxToken): string;
var
  S : TRdxLineSearch;
begin
  S := Default(TRdxLineSearch);
  S.Test    := IsCaseWord;
  S.What    := 'kein case';
  S.ManyFmt := '%d case-Anweisungen';
  Result := OneTokenOnLine(AMap, ALine, S, ACase);
end;

// Auf oberster Ebene des case: ein else, das dem case gehoert (ElseOwner:
// eoList - auch OHNE ';' davor, 'case K of 1: Foo else Bar end'; Review
// Quick-Fix-Units 2026-10-14), ist schon sein Zweig; ein else zu einem if
// in einem Arm (eoIf) nicht; ist der Besitzer unklar, keine Hilfe.
// 'otherwise' auf oberster Ebene ist der FPC-Zweig - auch OHNE ';' davor:
// FPC liest 'case K of 1: Foo otherwise Bar end' wie die else-Form (nach
// der Grammatik des FPC-Handbuchs: ohne ';' hinter dem Arm endet die
// Armliste, dann else bzw. otherwise; eine FPC-Mikroprobe steht aus), und
// uDefaultCaseInCaseStatement kennt otherwise nicht, meldet
// also auch solche case. Bis zur Review Woche G07-06 sperrte nur '; otherwise'
// - sonst kaeme 'otherwise Bar; else end', zwei Default-Zweige. Ein
// Bezeichner Otherwise als Arm-Anweisung (Delphi) sperrt so mit - die
// sichere Richtung. '' oder der Grund.
function TopLevelReason(AMap: TRdxCodeMap; const T, APrev: TRdxToken): string;
var
  Scan : TRdxElseScan;
begin
  Result := '';
  if T.Low = 'else' then
  begin
    Scan := ElseOwner(AMap, T);
    if Scan.Owner = eoList then
      Result := 'das case hat schon einen else-Zweig'
    else if Scan.Owner = eoUnknown then
      Result := 'else im case, Besitzer unklar: ' + Scan.Reason;
  end
  else if T.Low = 'otherwise' then
    Result := 'das case hat einen otherwise-Zweig (FPC) - oder ein Arm ruft '
      + 'einen Bezeichner Otherwise; von Hand pruefen';
end;

// Der Haken der end-Bilanz von SCA168 (BlockEnd, MatchingEnd): auf der
// obersten Ebene des case ein Schluesselwort gegen TopLevelReason halten.
// '&Else' und 'X.Else' sind Bezeichner (IsKeywordAfter), kein Zweig.
function CaseTopHook(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if (ADepth = 1) and IsKeywordAfter(T, APrev) then
    Result := TopLevelReason(AMap, T, APrev);
end;

// Das end zum case ACase und das Token davor (ALast). '' oder der Grund.
function MatchingEnd(AMap: TRdxCodeMap; const ACase: TRdxToken;
  out AEnd, ALast: TRdxToken): string;
begin
  Result := BlockEnd(AMap, ACase, CaseTopHook, AEnd, ALast);
  if (Result = '') and (AEnd.Low = '') then
    Result := 'kein end zum case gefunden';
end;

// Der Ersatz fuer das end: steht es am Zeilenanfang, das else in eigener
// Zeile mit derselben Einrueckung (AStatement eine Stufe tiefer), sonst
// inline vor dem end.
function ElseText(const ALine: string; const AEnd: TRdxToken;
  const AStatement, AArmLine: string): string;
var
  Indent, EndText : string;
begin
  EndText := Copy(ALine, AEnd.Col, AEnd.Len);
  if SkipBlanks(ALine, 1) <> AEnd.Col then
  begin
    Result := 'else ';
    if AStatement <> '' then
      Result := Result + AStatement + ' ';
    Exit(Result + EndText);
  end;
  Indent := Copy(ALine, 1, AEnd.Col - 1);
  Result := 'else' + #10;
  if AStatement <> '' then
    Result := Result + Indent + IndentStep(Indent, AArmLine) + AStatement + #10;
  Result := Result + Indent + EndText;
end;

// Endet der letzte Arm vor AEnd nicht auf ';' (im Code), ein ';' hinter
// sein letztes Zeichen - als eigene Ersetzung (das Zeichen wird mit ';'
// dahinter neu geschrieben, ein leerer Erwartungstext ist nicht erlaubt).
procedure AppendSemicolon(AMap: TRdxCodeMap; const AEnd: TRdxToken;
  var AEdits: TArray<TRdxEdit>);
var
  Li, Co : Integer;
  E      : TRdxEdit;
begin
  if not LastCharBefore(AMap, AEnd, Li, Co) then Exit;
  E := Default(TRdxEdit);
  E.Expected := Copy(AMap.Raw(Li), Co, 1);
  if (E.Expected = ';') and AMap.IsCode(Li, Co) then Exit;
  E.Span := TRefactorSpan.Make(SPAN_168, Li, Co, Li, Co + 1);
  E.NewText := E.Expected + ';';
  SetLength(AEdits, Length(AEdits) + 1);
  AEdits[High(AEdits)] := E;
end;

// CaseContextReason, ein Schluesselwort rueckwaerts: rsFound - das case ist
// eine Anweisung; rsStop - ein record (Variantenteil); sonst rsGoOn, ganze
// Bloecke in ABlock gezaehlt.
function CaseBlockStep(const T: TRdxToken; var ABlock: Integer): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = 'record' then
    Result := rsStop
  else if (T.Low = 'end') or (T.Low = 'until') then
    Inc(ABlock)
  else if IsEndOpener(T.Low) or (T.Low = 'repeat') then
  begin
    if ABlock = 0 then
      Result := rsFound
    else
      Dec(ABlock);
  end
  else if (ABlock = 0) and InList(T.Low, STATEMENT_SECTIONS) then
    Result := rsFound;
end;

// CaseContextReason, ein Token rueckwaerts: eine offene '(' ist die
// Feldliste eines Variantenzweigs (rsStop); Schluesselwoerter zaehlt
// CaseBlockStep.
function CaseScanStep(const T, APrev: TRdxToken; var ABlock,
  AParen: Integer): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = ')' then
    Inc(AParen)
  else if T.Low = '(' then
  begin
    Dec(AParen);
    if AParen < 0 then
      Result := rsStop;
  end
  else if IsKeywordAfter(T, APrev) then
    Result := CaseBlockStep(T, ABlock);
end;

// Ist das case ACase eine Anweisung? Der Detektor meldet nur case-
// Anweisungen; ein verschobener Fund (Zeilen eingefuegt, die Birne auf
// einer alten Zeile) kann aber auf dem Variantenteil eines Records landen
// - das else kaeme dann in die Typdeklaration und uebersetzte nicht
// (Review R3-04, Charge FC). Rueckwaerts bis zum innersten offenen Block,
// ganze Bloecke (end..begin/case/try/asm, until..repeat) uebersprungen: ein
// offenes begin/try/repeat/asm/case oder initialization/finalization auf
// oberster Ebene heisst Anweisung (''); ein 'record' - auf jeder Tiefe: ein
// case in seinem Variantenteil hat kein eigenes end, die Bilanz stimmt dort
// nicht (wie TRdxElseScan.StepWord) - oder eine offene '(' (Feldliste eines
// Variantenzweigs, 'case Tag of 0: (case ..') heisst Variantenteil. Steht
// zwischen der offenen '(' und dem case eine Direktive, kann auch ein Zweig
// die Klammer offen lassen ('{$IFDEF A} Foo( {$ELSE} Bar( {$ENDIF} 1);' vor
// einer case-Anweisung) - dann ist die Lage unklar (bis zur Nachpruefung FC
// hiess auch das Variantenteil). Ohne offenen Block bis zum Dateianfang (ein
// Fragment) ist die Lage ebenso unklar. Alles das sperrt. '' oder der Grund.
function CaseContextReason(AMap: TRdxCodeMap; const ACase: TRdxToken): string;
var
  T, P         : TRdxToken;
  Block, Paren : Integer;
  Step         : TRdxStep;
begin
  Block := 0;
  Paren := 0;
  T := Before(AMap, ACase);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    Step := CaseScanStep(T, P, Block, Paren);
    if Step = rsFound then
      Exit('');
    if (Step = rsStop) and (T.Low = '(')
       and DirectiveBetween(AMap, T, ACase.Line, ACase.Col) then
      Exit(R_CASE_OPEN_PAREN);
    if Step = rsStop then
      Exit(R_CASE_IN_RECORD);
    T := P;
  end;
  Result := 'kein Block um das case gefunden (Fragment?) - ob es eine '
    + 'Anweisung ist, ist unklar';
end;

class function TRdxStructFixes.CaseElse(AMap: TRdxCodeMap; ALine: Integer;
  const AStatement: string; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  CaseTok, EndTok, LastTok : TRdxToken;
  L                        : string;
begin
  Result := False;
  AEdits := nil;
  EndTok := Default(TRdxToken);
  LastTok := Default(TRdxToken);
  AReason := CaseTokenOn(AMap, ALine, CaseTok);
  if AReason = '' then
    AReason := MatchingEnd(AMap, CaseTok, EndTok, LastTok);
  if (AReason = '') and (LastTok.Low = 'of') then
    AReason := 'das case hat keine Zweige';
  if AReason = '' then
    AReason := CaseContextReason(AMap, CaseTok);
  if (AReason = '') and DirectiveBefore(AMap, CaseTok.Line, EndTok) then
    AReason := 'Compiler-Direktive im case - ein Zweig koennte die '
      + 'end-Bilanz verschieben';
  if AReason <> '' then Exit;
  L := AMap.Raw(EndTok.Line);
  SetLength(AEdits, 1);
  AEdits[0].Span := TRefactorSpan.Make(SPAN_168, EndTok.Line, EndTok.Col,
    EndTok.Line, EndTok.EndCol);
  AEdits[0].Expected := Copy(L, EndTok.Col, EndTok.Len);
  AEdits[0].NewText := ElseText(L, EndTok, AStatement, AMap.Raw(LastTok.Line));
  AppendSemicolon(AMap, EndTok, AEdits);
  Result := True;
end;

{ ---- SCA101 / SCA099 ---- }

class function TRdxStructFixes.BranchKeywordAt(AMap: TRdxCodeMap; ALine,
  ACol: Integer; out AKeyword: TRdxToken; out AReason: string): Boolean;
var
  L : string;
begin
  AKeyword := Default(TRdxToken);
  AReason := '';
  L := AMap.Raw(ALine);
  if ACol <= 0 then
    AReason := R_NO_COLUMN
  else if not AMap.IsCode(ALine, ACol) or not IsIdentStart(L[ACol])
     or ((ACol > 1) and IsIdentChar(L[ACol - 1])) then
    AReason := R_BRANCH_MOVED
  else
  begin
    AKeyword := TokenAt(AMap, ALine, ACol);
    if not InList(AKeyword.Low, BRANCH_KEYWORDS)
       or InList(Before(AMap, AKeyword).Low, IDENT_PREFIXES) then
      AReason := R_BRANCH_MOVED;
  end;
  Result := AReason = '';
end;

// Das end eines Paars 'end else', das uIfElseBegin meldet - nicht 'end
// else if' usw. (OneTokenOnLine, ElseAfterEndOn).
function IsEndElsePair(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  N := After(AMap, T);
  if (T.Low <> 'end') or (N.Low <> 'else') then Exit;
  Result := not InList(Before(AMap, T).Low, IDENT_PREFIXES)
    and not InList(After(AMap, N).Low, SCA099_ALLOWED);
end;

class function TRdxStructFixes.ElseAfterEndOn(AMap: TRdxCodeMap;
  ALine: Integer; out AKeyword: TRdxToken; out AReason: string): Boolean;
var
  S      : TRdxLineSearch;
  EndTok : TRdxToken;
begin
  AKeyword := Default(TRdxToken);
  S := Default(TRdxLineSearch);
  S.Test    := IsEndElsePair;
  S.What    := 'kein "end else"';
  S.ManyFmt := '%d-mal "end else"';
  AReason := OneTokenOnLine(AMap, ALine, S, EndTok);
  Result := AReason = '';
  if Result then
    AKeyword := After(AMap, EndTok);
end;

// Klammertiefe rueckwaerts: ')' und ']' hoch, '(' und '[' herunter
// (ParenDelta, uRdxCodeMap, abgezogen). True, wenn T eine Klammer war.
function ParenBack(const T: TRdxToken; var AParen: Integer): Boolean;
var
  Delta : Integer;
begin
  Delta := ParenDelta(T);
  Dec(AParen, Delta);
  Result := Delta <> 0;
end;

// FindOwner, ein Token ausserhalb von Klammern: ';' oder ein Wort aus
// OWNER_STOPS beendet die Suche, ein Wort aus AOwners ist der Besitzer.
function OwnerStep(const T, APrev: TRdxToken;
  const AOwners: array of string): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = ';' then
    Result := rsStop
  else if not IsKeywordAfter(T, APrev) then
    Exit
  else if (T.Low = 'on') and not InList(APrev.Low, HANDLER_PREV) then
    Exit
  else if InList(T.Low, AOwners) then
    Result := rsFound
  else if InList(T.Low, OWNER_STOPS) then
    Result := rsStop;
end;

// Rueckwaerts ab AKeyword ausserhalb von Klammern das erste Wort aus
// AOwners (if zu then; for/while/with/on zu do). '' oder der Grund.
function FindOwner(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
  const AOwners: array of string; out AOwner: TRdxToken): string;
var
  T, P  : TRdxToken;
  Paren : Integer;
  Step  : TRdxStep;
begin
  AOwner := Default(TRdxToken);
  Paren := 0;
  T := Before(AMap, AKeyword);
  while (T.Low <> '') and (Paren >= 0) do
  begin
    P := Before(AMap, T);
    // Klammern und was in ihnen steht, zaehlen nicht.
    Step := rsGoOn;
    if not ParenBack(T, Paren) and (Paren = 0) then
      Step := OwnerStep(T, P, AOwners);
    if Step = rsFound then
    begin
      AOwner := T;
      Exit('');
    end;
    if Step = rsStop then
      Break;
    T := P;
  end;
  if Paren < 0 then
    Exit(Format('das %s steht in Klammern', [AKeyword.Low]));
  Result := Format('keinen Anfang der Anweisung zum %s gefunden',
    [AKeyword.Low]);
end;

{ TRdxElseScan }

function TRdxElseScan.Fail(const AReason: string): Boolean;
begin
  Owner := eoUnknown;
  Reason := AReason;
  Result := True;
end;

function TRdxElseScan.TakeThen(const T: TRdxToken): Boolean;
begin
  Result := Pending = 0;
  if not Result then
    Dec(Pending)
  else
  begin
    Owner := eoIf;
    Decider := T;
  end;
end;

function TRdxElseScan.TakeList(const T: TRdxToken): Boolean;
begin
  if Pending > 0 then
    Exit(Fail('das else passt zu keinem if'));
  Owner := eoList;
  Decider := T;
  Result := True;
end;

// Bloecke rueckwaerts ueberspringen (end..begin/case/try/asm, until..repeat).
// Ein record bricht ab: ein case in seinem Variantenteil hat kein eigenes
// end, die Bilanz stimmte nicht mehr.
function TRdxElseScan.StepWord(const T: TRdxToken): Boolean;
begin
  Result := False;
  if T.Low = 'record' then
    Result := Fail('record vor dem else - die end-Bilanz ist unsicher')
  else if (T.Low = 'end') or (T.Low = 'until') then
    Inc(Block)
  else if (IsEndOpener(T.Low) or (T.Low = 'repeat')) and (Block > 0) then
    Dec(Block)
  else if Block = 0 then
    Result := StepTopWord(T);
end;

// Ein Schluesselwort auf oberster Ebene. Liegt schon ein ';' dahinter
// (AfterSemi), kommt nur noch ein case oder except in Frage - then und else
// gehoeren dann zu dessen Armen. Eine Deklaration zeigt, dass das ';' im
// Kopf einer anonymen Methode stand ('H := procedure var S: string; begin
// ... end else'): abbrechen, sonst zoege die Hilfe den Rest des Blocks in
// den else-Zweig (Gegen-Review SCA101, Blocker 1).
function TRdxElseScan.StepTopWord(const T: TRdxToken): Boolean;
begin
  Result := False;
  if InList(T.Low, LIST_ELSE_OWNERS) then
    Result := TakeList(T)
  else if InList(T.Low, ELSE_STOPS) then
    Result := Fail(R_NO_ELSE_OWNER)
  else if AfterSemi and InList(T.Low, DECL_WORDS) then
    Result := Fail(Format('"%s" hinter einem ";" vor dem else - Kopf einer '
      + 'anonymen Methode? Wem das else gehoert, ist unklar', [T.Low]))
  else if AfterSemi then
    Exit
  else if T.Low = 'else' then
    Inc(Pending)
  else if T.Low = 'then' then
    Result := TakeThen(T);
end;

// Ein ';' auf oberster Ebene: ein if-else kann es nicht mehr sein - aber
// erst ein of oder except entscheidet (StepTopWord).
function TRdxElseScan.StepSymbol(const T: TRdxToken): Boolean;
begin
  if (Block = 0) and (T.Low = ';') then
    AfterSemi := True;
  Result := False;
end;

// Wem gehoert das else? Rueckwaerts ausserhalb von Klammern und Bloecken:
// das erste then ohne eigenes else -> eoIf; of, case oder except davor ->
// eoList (else eines case oder except: dahinter steht eine
// Anweisungsliste bis zum end); Decider ist das entscheidende Token. Sonst
// Reason.
function ElseOwner(AMap: TRdxCodeMap; const AElse: TRdxToken): TRdxElseScan;
var
  T, P  : TRdxToken;
  Paren : Integer;
  Done  : Boolean;
begin
  Result := Default(TRdxElseScan);
  Paren := 0;
  T := Before(AMap, AElse);
  while (T.Low <> '') and (Paren >= 0) do
  begin
    P := Before(AMap, T);
    if ParenBack(T, Paren) or (Paren > 0) then
      Done := False
    else if IsKeywordAfter(T, P) then
      Done := Result.StepWord(T)
    else
      Done := Result.StepSymbol(T);
    if Done then Exit;
    T := P;
  end;
  Result.Owner := eoUnknown;
  if Paren < 0 then
    Result.Reason := 'das else steht in Klammern'
  else
    Result.Reason := R_NO_ELSE_OWNER;
end;

// Steht der ':' vor einem if in Klammern ('Write(X: if A then 1 else 2)')?
// Dann ist das if ein Ausdruck - keine case-Marke, kein Label.
function ColonInParens(AMap: TRdxCodeMap; const AColon: TRdxToken): Boolean;
var
  T     : TRdxToken;
  Paren : Integer;
begin
  Result := False;
  Paren := 0;
  T := Before(AMap, AColon);
  while (T.Low <> '') and (T.Low <> ';') do
  begin
    if ParenBack(T, Paren) and (Paren < 0) then
      Exit(True);
    if (Paren = 0) and IsKeywordAfter(T, Before(AMap, T))
       and InList(T.Low, COLON_STOPS) then
      Exit;
    T := Before(AMap, T);
  end;
end;

// Ein Sprung von StartsStatement - AThenOrElse ist then oder else: rsGoOn
// mit dem if davor (AIf), dessen Anfang weiter zu pruefen ist; rsFound,
// wenn das else zu case/except gehoert (eine Anweisungsliste); rsStop ohne
// Besitzer.
function HopToIf(AMap: TRdxCodeMap; const AThenOrElse: TRdxToken;
  out AIf: TRdxToken): TRdxStep;
var
  ThenTok : TRdxToken;
  Scan    : TRdxElseScan;
begin
  AIf := Default(TRdxToken);
  ThenTok := AThenOrElse;
  if AThenOrElse.Low = 'else' then
  begin
    Scan := ElseOwner(AMap, AThenOrElse);
    if Scan.Reason <> '' then Exit(rsStop);
    if Scan.Owner = eoList then Exit(rsFound);
    ThenTok := Scan.Decider;
  end;
  Result := rsGoOn;
  if FindOwner(AMap, ThenTok, IF_OWNERS, AIf) <> '' then
    Result := rsStop;
end;

// Beginnt AOwner (if, for, while, with, on) eine Anweisung? Davor steht
// ein Token aus STATEMENT_PREV; ist es then oder else, muss auch das if
// davor eine beginnen - sonst ist es ein verschachtelter bedingter
// Ausdruck ('X := if A then if B then C else D else E').
function StartsStatement(AMap: TRdxCodeMap; const AOwner: TRdxToken): Boolean;
var
  P, IfTok : TRdxToken;
  Hop      : Integer;
  Step     : TRdxStep;
begin
  Result := False;
  P := Before(AMap, AOwner);
  for Hop := 1 to MAX_HOPS do
  begin
    if not InList(P.Low, STATEMENT_PREV) then Exit;
    if (P.Low = ':') and ColonInParens(AMap, P) then Exit;
    if (P.Low <> 'then') and (P.Low <> 'else') then Exit(True);
    Step := HopToIf(AMap, P, IfTok);
    if Step <> rsGoOn then Exit(Step = rsFound);
    P := Before(AMap, IfTok);
  end;
end;

// Der Besitzer muss eine Anweisung beginnen (StartsStatement).
function StatementOwner(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
  const AOwners: array of string; out AOwner: TRdxToken): string;
begin
  Result := FindOwner(AMap, AKeyword, AOwners, AOwner);
  if (Result = '') and not StartsStatement(AMap, AOwner) then
    Result := Format('das %s steht in einem Ausdruck (bedingter Ausdruck, '
      + 'Delphi 13) - kein Zweig einer Anweisung', [AOwner.Low]);
end;

// Besitzer und Einrueckung der Anweisung hinter ABranch.Keyword: then ->
// if, do -> for/while/with/on (eingerueckt wie deren Zeile); else -> if-else
// oder Liste (eingerueckt wie die else-Zeile). '' oder der Grund.
function BranchOwner(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  Kw, Owner : TRdxToken;
  Scan      : TRdxElseScan;
  L         : string;
begin
  Kw := ABranch.Keyword;
  ABranch.CheckFrom := Kw.Line;
  if Kw.Low = 'then' then
    Result := StatementOwner(AMap, Kw, IF_OWNERS, Owner)
  else if Kw.Low = 'do' then
    Result := StatementOwner(AMap, Kw, DO_OWNERS, Owner)
  else
  begin
    Scan := ElseOwner(AMap, Kw);
    Result := Scan.Reason;
    ABranch.IsList := Scan.Owner = eoList;
    ABranch.CheckFrom := Scan.Decider.Line;
    if (Result = '') and (Scan.Owner = eoIf) then
      Result := StatementOwner(AMap, Scan.Decider, IF_OWNERS, Owner);
    Owner := Kw;
  end;
  L := AMap.Raw(Owner.Line);
  ABranch.Indent := Copy(L, 1, SkipBlanks(L, 1) - 1);
end;

// StatementEnd, ein Token: Klammertiefe fortschreiben; rsFound an einem
// ';' oder Stopper ausserhalb von Klammern, rsStop mit AReason an einem
// gesperrten Wort.
function StatementStep(const T, APrev: TRdxToken; var AParen: Integer;
  out AReason: string): TRdxStep;
var
  IsKw  : Boolean;   // nicht 'Word': verdeckte System.Word (Review R3-06)
  Delta : Integer;
begin
  Result := rsGoOn;
  AReason := '';
  IsKw := IsKeywordAfter(T, APrev);
  Delta := ParenDelta(T);
  if Delta <> 0 then
    Inc(AParen, Delta)
  else if (AParen = 0)
     and ((T.Low = ';') or (IsKw and InList(T.Low, BRANCH_STOPPERS))) then
    Result := rsFound
  else if IsKw and (InList(T.Low, NOT_IN_BRANCH)
     or InList(T.Low, BRANCH_STOPPERS)) then
  begin
    AReason := Format('"%s" in der Anweisung - Struktur, bedingter '
      + 'Ausdruck, anonyme Methode oder Inline-Deklaration', [T.Low]);
    Result := rsStop;
  end;
end;

// Das Ende der einfachen Anweisung ab ABranch.First, ausserhalb von
// Klammern: ein ';' (HasSemi, LastLine/LastCol) oder ein Stopper (Stop).
// '' oder der Grund.
function StatementEnd(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  T, Prev : TRdxToken;
  Paren   : Integer;
  Step    : TRdxStep;
begin
  Paren := 0;
  Prev := ABranch.Keyword;
  T := ABranch.First;
  while (T.Low <> '') and (Paren >= 0) do
  begin
    Step := StatementStep(T, Prev, Paren, Result);
    if Step = rsStop then Exit;
    if Step = rsFound then
    begin
      ABranch.HasSemi := T.Low = ';';
      ABranch.Stop := T;
      ABranch.LastLine := T.Line;
      ABranch.LastCol := T.Col;
      Exit;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := 'Ende der Anweisung nicht gefunden';
end;

// Der Haken der end-Bilanz von ListEnd (BlockEnd): eine Inline-
// Deklaration im else-Zweig sperrt.
function ListDeclHook(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if IsKeywordAfter(T, APrev) and InList(T.Low, INLINE_DECLS) then
    Result := Format('Inline-Deklaration (%s) im else-Zweig - begin..end engte '
      + 'ihren Gueltigkeitsbereich ein', [T.Low]);
end;

// Das Ende der Anweisungsliste hinter dem else eines case oder except: das
// end, das den case bzw. try schliesst (end-Bilanz BlockEnd ab dem else).
// Endet die Liste auf ';', HasSemi. '' oder der Grund.
function ListEnd(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  EndTok, Last : TRdxToken;
begin
  Result := BlockEnd(AMap, ABranch.Keyword, ListDeclHook, EndTok, Last);
  if Result <> '' then Exit;
  if EndTok.Low = '' then
    Exit('kein end zum else-Zweig gefunden');
  ABranch.Stop := EndTok;
  ABranch.HasSemi := Last.Low = ';';
  ABranch.LastLine := Last.Line;
  ABranch.LastCol := Last.Col;
end;

// Erstes Token und Ende der Anweisung (bzw. Liste). '' oder der Grund.
function BranchEnd(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  F      : TRdxToken;
  Li, Co : Integer;
begin
  F := After(AMap, ABranch.Keyword);
  ABranch.First := F;
  if F.Low = '' then
    Exit('Dateiende hinter dem ' + ABranch.Keyword.Low);
  if F.Low = 'begin' then
    Exit('die Anweisung steht schon in begin..end - Fund veraltet? Datei neu '
      + 'pruefen');
  if (F.Low = ';') or InList(F.Low, BRANCH_STOPPERS) then
    Exit('leere Anweisung hinter dem ' + ABranch.Keyword.Low);
  // Der Token-Leser sieht keine Strings: begaenne die Anweisung mit einem,
  // waere F nicht ihr Anfang.
  if not FirstCharAfter(AMap, ABranch.Keyword, Li, Co)
     or (Li <> F.Line) or (Co <> F.Col) then
    Exit('die Anweisung beginnt mit einem String');
  if ABranch.IsList then
    Result := ListEnd(AMap, ABranch)
  else
    Result := StatementEnd(AMap, ABranch);
  if (Result = '') and not ABranch.HasSemi
     and not LastCharBefore(AMap, ABranch.Stop, ABranch.LastLine,
       ABranch.LastCol) then
    Result := 'Ende der Anweisung nicht gefunden';
end;

// Eine Direktive in den Zeilen B.CheckFrom bis zur letzten Zeile der
// Anweisung bzw. ihres Stoppers? Sie stuende nach der Hilfe womoeglich auf
// der anderen Seite von begin oder end - oder sie entschied, wem ein else
// gehoert ('{$IFDEF A} if X then Y {$ELSE} case K of 1: Y; {$ENDIF} else',
// Gegen-Review SCA101, Minor 2). Zeilenweise: lieber zu streng.
function DirectiveInRange(AMap: TRdxCodeMap; const B: TRdxBranch): Boolean;
var
  Last : Integer;
begin
  Last := B.LastLine;
  if B.Stop.Line > Last then
    Last := B.Stop.Line;
  Result := DirectiveInLines(AMap, B.CheckFrom, Last);
end;

// begin und end als eigene Zeilen: hinter die Zeile des Schluesselworts
// und hinter die letzte Zeile der Anweisung (deren Rest bleibt bei ihr).
function OwnLinesEdit(AMap: TRdxCodeMap; const B: TRdxBranch;
  const ASemi, AEnd: string): TRdxEdit;
var
  Last : string;
begin
  Result := Default(TRdxEdit);
  Last := AMap.Raw(B.LastLine);
  Result.Span := TRefactorSpan.Make(SPAN_101, B.Keyword.Line, B.Keyword.Col,
    B.LastLine, Length(Last) + 1);
  Result.Expected := RangeText(AMap, Result.Span);
  Result.NewText := Copy(AMap.Raw(B.Keyword.Line), B.Keyword.Col, MaxInt)
    + #10 + B.Indent + 'begin' + #10
    + RangeText(AMap, TRefactorSpan.Make(SPAN_101, B.Keyword.Line + 1, 1,
        B.LastLine, B.LastCol + 1))
    + ASemi + Copy(Last, B.LastCol + 1, MaxInt) + #10 + B.Indent + AEnd;
end;

// Folgt der Anweisung (ohne ';') ein else auf ihrer letzten Zeile?
function ElseOnLastLine(const B: TRdxBranch): Boolean;
begin
  Result := not B.HasSemi and (B.Stop.Low = 'else')
    and (B.Stop.Line = B.LastLine);
end;

// Alles auf der Zeile des Schluesselworts: dahinter begin, die Anweisung
// eine Stufe tiefer und end in eigenen Zeilen - ein else, das auf der
// Zeile folgte, beginnt eine weitere.
function SplitLineEdit(AMap: TRdxCodeMap; const B: TRdxBranch;
  const ASemi, AEnd: string): TRdxEdit;
var
  L, Body, Gap, Tail : string;
  EndCol             : Integer;
begin
  Result := Default(TRdxEdit);
  L := AMap.Raw(B.Keyword.Line);
  Body := Trim(Copy(L, B.Keyword.EndCol, B.LastCol + 1 - B.Keyword.EndCol))
    + ASemi;
  EndCol := B.LastCol + 1;
  Tail := '';
  if ElseOnLastLine(B) then
  begin
    Gap := Trim(Copy(L, B.LastCol + 1, B.Stop.Col - B.LastCol - 1));
    if Gap <> '' then
      Body := Body + ' ' + Gap;
    EndCol := B.Stop.Col;
    Tail := #10 + B.Indent;
  end;
  Result.Span := TRefactorSpan.Make(SPAN_101, B.Keyword.Line, B.Keyword.Col,
    B.Keyword.Line, EndCol);
  Result.Expected := Copy(L, B.Keyword.Col, EndCol - B.Keyword.Col);
  Result.NewText := Copy(L, B.Keyword.Col, B.Keyword.Len) + #10 + B.Indent
    + 'begin' + #10 + B.Indent + IndentStep(B.Indent, '') + Body + #10
    + B.Indent + AEnd + Tail;
end;

// Inline: 'begin ' vor die Anweisung, ' end' hinter sie - eine Ersetzung
// auf einer Zeile, sonst zwei.
function InlineEdits(AMap: TRdxCodeMap; const B: TRdxBranch;
  const ASemi, AEnd: string): TArray<TRdxEdit>;
var
  Close : string;
begin
  Close := ASemi + ' ' + AEnd;
  if B.First.Line = B.LastLine then
  begin
    SetLength(Result, 1);
    Result[0].Span := TRefactorSpan.Make(SPAN_101, B.First.Line, B.First.Col,
      B.LastLine, B.LastCol + 1);
    Result[0].Expected := Copy(AMap.Raw(B.LastLine), B.First.Col,
      B.LastCol + 1 - B.First.Col);
    Result[0].NewText := 'begin ' + Result[0].Expected + Close;
    Exit;
  end;
  SetLength(Result, 2);
  Result[0].Span := TRefactorSpan.Make(SPAN_101, B.First.Line, B.First.Col,
    B.First.Line, B.First.EndCol);
  Result[0].Expected := Copy(AMap.Raw(B.First.Line), B.First.Col, B.First.Len);
  Result[0].NewText := 'begin ' + Result[0].Expected;
  Result[1].Span := TRefactorSpan.Make(SPAN_101, B.LastLine, B.LastCol,
    B.LastLine, B.LastCol + 1);
  Result[1].Expected := Copy(AMap.Raw(B.LastLine), B.LastCol, 1);
  Result[1].NewText := Result[1].Expected + Close;
end;

// Die Form waehlen (s. WrapInBlock): eigene Zeilen, Zeile aufteilen oder
// inline.
function BlockEdits(AMap: TRdxCodeMap; const B: TRdxBranch): TArray<TRdxEdit>;
var
  Semi, EndText : string;
begin
  Semi := ';';
  EndText := 'end';
  if B.HasSemi then
  begin
    Semi := '';
    EndText := 'end;';
  end;
  if CanAppendLine(AMap, B.Keyword.Line, B.Keyword.EndCol - 1)
     and CanAppendLine(AMap, B.LastLine, B.LastCol) then
  begin
    SetLength(Result, 1);
    Result[0] := OwnLinesEdit(AMap, B, Semi, EndText);
  end
  else if (B.First.Line = B.Keyword.Line) and (B.LastLine = B.Keyword.Line)
     and (ElseOnLastLine(B) or TailIsComment(AMap, B.LastLine, B.LastCol)) then
  begin
    SetLength(Result, 1);
    Result[0] := SplitLineEdit(AMap, B, Semi, EndText);
  end
  else
    Result := InlineEdits(AMap, B, Semi, EndText);
end;

class function TRdxStructFixes.WrapInBlock(AMap: TRdxCodeMap;
  const AKeyword: TRdxToken; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  B : TRdxBranch;
begin
  Result := False;
  AEdits := nil;
  B := Default(TRdxBranch);
  B.Keyword := AKeyword;
  if not InList(AKeyword.Low, BRANCH_KEYWORDS) then
    AReason := R_BRANCH_MOVED
  else
    AReason := BranchOwner(AMap, B);
  if AReason = '' then
    AReason := BranchEnd(AMap, B);
  if (AReason = '') and DirectiveInRange(AMap, B) then
    AReason := 'Compiler-Direktive im Bereich - begin oder end stuende auf '
      + 'der anderen Seite';
  if AReason <> '' then Exit;
  AEdits := BlockEdits(AMap, B);
  Result := True;
end;

class function TRdxStructFixes.StartsStatementAt(AMap: TRdxCodeMap;
  const ATok: TRdxToken): Boolean;
begin
  Result := StartsStatement(AMap, ATok);
end;

class function TRdxStructFixes.ElseBelongsToIf(AMap: TRdxCodeMap;
  const AElse: TRdxToken; out AReason: string): Boolean;
var
  Scan : TRdxElseScan;
begin
  Scan := ElseOwner(AMap, AElse);
  AReason := Scan.Reason;
  if (AReason = '') and (Scan.Owner <> eoIf) then
    AReason := 'das else gehoert zu einem case bzw. except - dahinter steht '
      + 'eine Anweisungsliste';
  Result := AReason = '';
end;

end.
