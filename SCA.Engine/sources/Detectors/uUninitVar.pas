unit uUninitVar;

// Detector: SCA166 fkUninitVar — lokale Variable wird auf einem Pfad
// gelesen bevor sie auf demselben Pfad geschrieben wurde.
//
// Konservatives MVP nach Konzept_SCA166_UninitVar.md (§5+§7):
//   * Single-Method-Scope (kein Cross-Procedure-Flow).
//   * Sequentielle Source-Line-Ordnung pro Methode.
//   * Writes erkannt aus nkAssign (LHS), nkForStmt (Loop-Var) und
//     nkCall mit Name in WRITE_ALLOWLIST (Read/ReadLn/FillChar/Move/
//     Initialize/New/GetMem/ZeroMemory).
//   * Reads = jede andere Erwaehnung der Variable im Body (Wort-
//     grenzen-Match analog uUnusedLocal).
//   * Klassifikation:
//       - Variable referenziert + KEIN Write -> fcHigh
//       - First-Read-Line < First-Write-Line  -> fcMedium
//   * Skip-Regeln (FP-Guards §5.E):
//       - Name beginnt mit '_'
//       - Managed types (string, dynamic array, interface) ohne
//         expliziten Opt-In
//       - Method ist asm-Block
//       - Method-Header passt nicht zu LocalVar-Decl (Parser-Artefakt
//         analog uUnusedLocal.LooksLikeRealLocalVar)
//       - Method ueberschreitet Hard-Caps (MaxLocalVars, MaxStatements)
//
// Phase-2-Erweiterung (siehe Konzept §11): Sibling-Write-Check fuer
// if-then-else mit beidseitigem Write. Phase-3 (CFG) und Phase-4
// (Symboltabelle) sind im Konzept dokumentiert.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext, uTypeIndex,
  uCFG;   // #6 Inkr.4: CFG-Postfilter fuer read-before-write

type
  TUninitVarDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil;
      ARecordTypes: TDictionary<string, Boolean> = nil;
      const ADirLines: TArray<Integer> = nil;
      // Zensus-Triage 2026-07-25, Hook 1b: Same-File-Signaturindex
      // Name -> var/out-Flag je Parameterposition (baut AnalyzeUnit einmal
      // pro File; nil = Aufloesung aus, z.B. Direkt-Aufrufe in Tests).
      ASigVarOut: TDictionary<string, TArray<Boolean>> = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CommentedOutCode, ConsecutiveSection, CyclomaticComplexity, DeepNesting, DuplicateBlock, GroupedDeclaration, IfElseBegin, LongMethod, NestedRoutine, NestedTry, NilComparison, RedundantJump, StringConcatInLoop, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter, UnusedRoutine
// PhaseB/PhaseC der Variable-Inventur baut TypeRef-Strings aus Tokens via
// Concat - kurze qualified names, kein O(n^2)-Risiko.

uses
  System.StrUtils,
  uFileTextCache, uDetectorUtils;

// Hard-Caps werden zur Laufzeit aus uSCAConsts.DetectorMaxLocalVars /
// DetectorMaxChildrenRecursive gelesen (konfigurierbar via analyser.ini
// [Detectors]). Default 200 / 5000.

const
  // RTL-Routinen die ihren Argumenten Werte zuweisen (out/var). Wenn
  // einer dieser Calls eine Variable als Arg hat, gilt das als Write.
  WRITE_ALLOWLIST : array[0..11] of string = (
    'read', 'readln', 'blockread',
    'fillchar', 'move', 'zeromemory',
    'initialize', 'new', 'getmem',
    'setlength', 'setstring',
    'tryfromstring'         // TBytes.TryFromString und Verwandte
  );

  // Read-Family-RTL-Methoden die ihre Buffer-Argumente FUELLEN (out/var):
  // TStream.Read/ReadBuffer/ReadData, System.Read/ReadLn, System.BlockRead.
  // Wird im Source-Scan benutzt (LineFillsVarViaReadCall) - der AST-
  // Pessimistic-Write erfasst diese Calls bei manchen Methoden nicht
  // zuverlaessig (Buffer als 'Buf[0]'-Element / Headless-Method-Pattern).
  // Das ist die dominante SCA166-FP-Klasse (Real-World 2026-06-28:
  // Abbrevia/zip/ID3/Syn*-Stream-Reader). Return-Wert-Varianten wie
  // ReadInteger/ReadString matchen NICHT (kein gefuelltes Arg, sondern
  // Rueckgabewert) - der '(' direkt nach dem Namen filtert sie aus.
  READ_FILL_FUNCS : array[0..4] of string = (
    'read', 'readln', 'readbuffer', 'blockread', 'readdata'
  );

  // Read-Only-Routinen die ihre Args garantiert NICHT schreiben.
  // Wenn ein Call in dieser Liste eine Variable als Arg hat, gilt das
  // als Read (= Variable muss VORHER assigned sein).
  // Default fuer alle ANDEREN Calls (z.B. 'Helper.Init(X)') ist
  // pessimistic-Write - akzeptiert FNs zugunsten weniger FPs.
  // Hinweis: 'identtoint' bewusst NICHT hier - IdentToInt(const Ident; var Int;
  // const Map) SCHREIBT sein 2. Arg (var) -> gehoert nicht zu den read-only-
  // Calls (Recharakterisierung after30 2026-07-12: sonst gilt das gefuellte
  // Int-Arg als uninit-Read = FP). Ohne Eintrag faellt der Call auf den
  // pessimistic-Write-Default (ProcessCall/RegisterCallArgWrites) -> Write.
  READ_ALLOWLIST : array[0..56] of string = (
    // --- Output ---
    'write', 'writeln', 'showmessage', 'showmessagefmt',
    'outputdebugstring', 'outputdebugstringa', 'outputdebugstringw',
    // --- Typ-Konvertierung / Inspektion (gibt nur einen Wert zurueck) ---
    'inttostr', 'inttohex', 'floattostr', 'datetostr', 'timetostr',
    'datetimetostr', 'formatfloat', 'formatdatetime', 'format',
    'inttoidentstr', 'strtoint', 'strtointdef',
    'strtofloat', 'strtofloatdef', 'strtodatetime', 'strtodate',
    // --- String/Array-Inspektion ---
    'length', 'sizeof', 'high', 'low', 'ord', 'chr',
    'copy', 'pos', 'posex', 'trim', 'trimleft', 'trimright',
    'uppercase', 'lowercase', 'sametext', 'comparetext', 'comparestr',
    // --- Boolean-Inspektion ---
    'assigned', 'isdebuggerpresent',
    // --- Windows-API Read-Only (Phase 2.5) ---
    'sleep', 'sleepex', 'gettickcount', 'gettickcount64',
    'getlasterror', 'getcurrentthreadid', 'getcurrentprocessid',
    'waitforsingleobject', 'waitformultipleobjects',
    'closehandle', 'freelibrary',
    'releasedc', 'deletedc', 'deleteobject', 'deletecriticalsection'
  );

  // Managed types die Pascal auto-initialisiert. Wir flaggen sie nur,
  // wenn der User explizit `UninitVarFlagManagedTypes` aktiviert.
  MANAGED_TYPE_PREFIXES : array[0..13] of string = (
    'string', 'unicodestring', 'ansistring', 'rawbytestring',
    // Real-World-FP-Audit 2026-07-12: mORMot-/RTL-Stringtypen + Variant sind
    // ebenfalls compiler-auto-initialisiert (auto '', Unassigned) -> ein
    // read-without-write ist nie ein echter uninit-Bug.
    'rawutf8', 'rawjson', 'synunicode', 'widestring',
    'variant', 'olevariant',
    'tarray<',              // TArray<T> generic dynamic array
    'iinterface',           // sehr defensive Annaehrung an ALLE Interfaces
    // Recharakterisierung after30 (2026-07-12): PascalScript-String-Aliase
    // (tbtString = AnsiString, tbtWideString = WideString). Beide sind
    // compiler-managed (auto '') -> read-without-write nie ein echter
    // uninit-Bug (analog den mORMot-Aliasen oben; 3/26 der SCA166-Sample-FPs).
    'tbtstring', 'tbtwidestring'
  );

  // Auto-init-Record-Typen: Records mit Initialize/Finalize-Management-
  // Operatoren bzw. lazy Self-Init. Bare-Verwendung
  //   'var ctx: TRttiContext; ctx.GetType(...)'
  // ist das Standard-Idiom und braucht NIE eine explizite Zuweisung ->
  // read-without-write ist hier KEIN Bug (also kein FN beim Skippen).
  // FP-Klasse Real-World 2026-06-28: Alcinoe/CEF4 RTTI-Walks, 195 bare
  // TRttiContext-Decls im 25-Repo-Korpus = dominante SCA166-FP-Quelle.
  NOINIT_RECORD_TYPES : array[0..0] of string = (
    'trtticontext'
  );

  // Methoden-Body wird als asm-Block gekennzeichnet wenn das TypeRef
  // des nkMethod-Knotens einen ';asm'-Marker enthaelt (analog dem
  // virtual/override-Pattern in uVisibilityCheck).
  ASM_MARKER = ';asm';

type
  TVarInfo = record
    Name             : string;
    NameLow          : string;
    TypeLow          : string;
    DeclLine         : Integer;
    FirstWriteLine   : Integer;     // 0 = nie geschrieben
    FirstReadLine    : Integer;     // 0 = nie gelesen (= Variable ist UnusedLocal-Domain)
    RefCount         : Integer;     // Anzahl Wortgrenzen-Matches im Body inkl. Decl
    IsManaged        : Boolean;
    // #6 Inkr.4: ALLE registrierten Write-Zeilen (AST-Walks + Source-
    // Rescan) fuer den CFG-Postfilter - FirstWriteLine allein verliert
    // die uebrigen Def-Sites. Cap 64: darueber wird der Filter nur
    // KONSERVATIVER (weniger bekannte Defs -> weniger Drops).
    WriteLines       : TArray<Integer>;
  end;
  PVarInfo = ^TVarInfo;

function IsIdentChar(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

type
  // State fuer Zeilen-uebergreifende Block-Kommentar-Verfolgung.
  // String-Literale ('...') koennen in klassischem Delphi nicht ueber
  // Zeilengrenzen hinweg gehen - daher kein InString-State.
  // Delphi-12-Multi-Line-Strings ('''...''') werden bewusst NICHT
  // getrackt - rare Edge-Case, FN akzeptabel.
  TLineStripState = record
    InBrace : Boolean;   // True wenn vorige Zeile mit offenem '{' endete
    InParen : Boolean;   // True wenn vorige Zeile mit offenem '(*' endete
  end;

function StripLineEx(const Line: string; var State: TLineStripState): string;
// Stripper mit Zeilen-uebergreifendem State - State.InBrace/InParen
// werden VOR der Zeile aus dem Caller-State gelesen und NACH der Zeile
// zurueckgeschrieben. So funktionieren auch Multi-Line-Comments wie
//   { Foo bar
//     baz }
// als Stripping ueber alle drei Zeilen.
var
  Buf : array of Char;
  i, L : Integer;
  InString : Boolean;
  C, Next : Char;
begin
  L := Length(Line);
  if L = 0 then Exit('');
  SetLength(Buf, L);
  InString := False;       // Strings koennen sich nicht ueber Zeilen ziehen
  i := 1;
  while i <= L do
  begin
    C := Line[i];
    if i < L then Next := Line[i + 1] else Next := #0;

    if State.InBrace then
    begin
      Buf[i - 1] := ' ';
      if C = '}' then State.InBrace := False;
      Inc(i);
    end
    else if State.InParen then
    begin
      Buf[i - 1] := ' ';
      if (C = '*') and (Next = ')') then
      begin
        Buf[i] := ' ';
        Inc(i, 2);
        State.InParen := False;
      end
      else
        Inc(i);
    end
    else if InString then
    begin
      Buf[i - 1] := ' ';
      if C = '''' then
      begin
        if Next = '''' then    // '' Escape innerhalb String
        begin
          Buf[i] := ' ';
          Inc(i, 2);
        end
        else
        begin
          InString := False;
          Inc(i);
        end;
      end
      else
        Inc(i);
    end
    else
    begin
      if (C = '/') and (Next = '/') then
      begin
        // Line-Comment: Rest der Zeile zu Spaces.
        while i <= L do
        begin
          Buf[i - 1] := ' ';
          Inc(i);
        end;
        Break;
      end
      else if C = '{' then
      begin
        Buf[i - 1] := ' ';
        State.InBrace := True;
        Inc(i);
      end
      else if (C = '(') and (Next = '*') then
      begin
        Buf[i - 1] := ' ';
        Buf[i]     := ' ';
        Inc(i, 2);
        State.InParen := True;
      end
      else if C = '''' then
      begin
        Buf[i - 1] := ' ';
        InString := True;
        Inc(i);
      end
      else
      begin
        Buf[i - 1] := C;
        Inc(i);
      end;
    end;
  end;
  SetString(Result, PChar(Buf), L);
end;

function StripCommentsAndStrings(const Line: string): string;
// Stateless single-line convenience-Wrapper (Alt-API).
// Multi-Line-Block-Comments werden in dieser Variante NICHT erkannt.
// Verwendung nur fuer Stellen ohne Zeilen-iterierenden Scan.
var
  State : TLineStripState;
begin
  State.InBrace := False;
  State.InParen := False;
  Result := StripLineEx(Line, State);
end;

function CountWholeWordOccurrences(const NeedleLow, HaystackLow: string;
  out FirstMatchPos: Integer): Integer;
// Wortgrenz-Match analog uUnusedLocal. FirstMatchPos = 1-basierte
// Position des ersten Matches (0 wenn keiner). Result = Anzahl Matches.
var
  P, NL, HL : Integer;
  Before, After : Char;
begin
  Result := 0;
  FirstMatchPos := 0;
  NL := Length(NeedleLow);
  HL := Length(HaystackLow);
  if (NL = 0) or (HL < NL) then Exit;

  P := 1;
  while True do
  begin
    P := PosEx(NeedleLow, HaystackLow, P);
    if P = 0 then Break;
    Before := #0;
    if P > 1 then Before := HaystackLow[P - 1];
    After := #0;
    if P + NL - 1 < HL then After := HaystackLow[P + NL];
    if not IsIdentChar(Before) and not IsIdentChar(After) then
    begin
      Inc(Result);
      if FirstMatchPos = 0 then FirstMatchPos := P;
    end;
    P := P + NL;
  end;
end;

function IsManagedType(const TypeRef: string;
  AContext: TAnalyzeContext): Boolean;
var
  T, Orig : string;
  Prefix : string;
begin
  Result := False;
  Orig := Trim(TypeRef);
  T := LowerCase(Orig);
  if T = '' then Exit;
  for Prefix in MANAGED_TYPE_PREFIXES do
    if T.StartsWith(Prefix) then Exit(True);
  // Real-World-FP-Audit 2026-07-12: JEDES Interface (Delphi-Konvention 'I' +
  // Grossbuchstabe, z.B. ISynLog/ISmsSender) ist refcounted + auto-nil ->
  // managed -> read-without-write nie ein echter uninit-Bug. 'Integer'/'Int64'
  // (I + Kleinbuchstabe) matchen NICHT.
  if (Length(Orig) >= 2) and (Orig[1] = 'I') and CharInSet(Orig[2], ['A'..'Z']) then
    Exit(True);
  // SCA166-Managed-Alias (Drop-Sampling-Erkenntnis 2026-07-24): Hersteller-
  // Praefix-Interfaces wie 'IwbMainRecord' (TES5Edit: 'I' + Projektkuerzel
  // in Kleinbuchstaben + CamelCase-Name) fielen durch die strikte
  // I-Grossbuchstaben-Konvention - ihre FPs ueberlebten nur zufaellig via
  // Zyklus-Regel des CFG-Postfilters. Muster: 'I' + >=1 Kleinbuchstabe +
  // Grossbuchstabe ('IwbX' ja; 'Integer'/'Int64' nein - nach deren
  // Kleinlauf folgt kein Grossbuchstabe). NEGATIV-GATE ueber den Cross-
  // Unit-TypeIndex: kennt er den Namen als Klasse/Record/Enum, ist es
  // KEIN Interface -> nicht managed (eine uninitialisiert gelesene
  // KLASSEN-Referenz ist ein echter Bug und bleibt Fund). Korpus-Beleg
  // fuer die Strenge: IntUserFieldVTable/InstException = class,
  // ImageCodecInfo & Co. = record - das Muster trifft reale Werttypen.
  // REICHWEITEN-GRENZE (byte-identisch im Selbst-Scan-Korpus, A/B
  // after77/78): der Parser legt Interfaces als nkClass ab, der Index
  // fuehrt sie als tkiClass - liegt die Interface-DECL im Scan-Umfang,
  // blockt das Gate auch echte Interfaces. Die Konvention wirkt damit
  // fuer FREMD-Interfaces ohne mitgescannte Decl (der typische Kunden-
  // Scan). Volle Wirkung braeuchte tkiInterface im Index (Parser-
  // Marker an nkClass = eigenes risikobehaftetes Inkrement, Backlog).
  if (Length(Orig) >= 3) and (Orig[1] = 'I') and CharInSet(Orig[2], ['a'..'z']) then
  begin
    var i := 2;
    while (i <= Length(Orig)) and CharInSet(Orig[i], ['a'..'z']) do
      Inc(i);
    if (i <= Length(Orig)) and CharInSet(Orig[i], ['A'..'Z']) then
    begin
      // CtxTypeIndex kann nil sein (Tests/Single-File ohne Kontext) -
      // dann greift die Konvention ohne Gate (gleiche Vertrauensstufe
      // wie die bestehende I-Grossbuchstaben-Regel).
      var TI := CtxTypeIndex(AContext);
      if (TI = nil) or (TI.TypeKindOf(T) in [tkiUnknown, tkiAlias]) then
        Exit(True);
    end;
  end;
end;

function IsNoInitRecordType(const TypeRef: string): Boolean;
// True wenn der Typ ein Auto-init-Record (NOINIT_RECORD_TYPES) ist - dann
// ist read-without-write KEIN UninitVar (Standard-Idiom). Qualifier wie
// 'System.Rtti.TRttiContext' werden auf den nackten Namen reduziert.
var
  T, NameOnly, NT : string;
  DotPos : Integer;
begin
  Result := False;
  T := LowerCase(Trim(TypeRef));
  if T = '' then Exit;
  DotPos := LastDelimiter('.', T);
  if DotPos > 0 then NameOnly := Copy(T, DotPos + 1, MaxInt) else NameOnly := T;
  for NT in NOINIT_RECORD_TYPES do
    if NameOnly = NT then Exit(True);
end;

function BaseTypeLow(const TypeLow: string): string;
// Reduziert einen (bereits gelowerten) TypeRef auf den nackten Typnamen:
// Generic-Parameter (< ... >) und Qualifier (unit.T) werden abgeschnitten.
// 'system.rtti.trtticontext' -> 'trtticontext', 'tdynarray<byte>' -> 'tdynarray'.
var
  P : Integer;
begin
  Result := Trim(TypeLow);
  P := Pos('<', Result);
  if P > 0 then Result := Trim(Copy(Result, 1, P - 1));
  P := LastDelimiter('.', Result);
  if P > 0 then Result := Copy(Result, P + 1, MaxInt);
end;

function IsDynArrayDeclLine(Lines: TStringList; DeclLine: Integer;
  const NameLow, TypeLow: string): Boolean;
// Welle 1 (2026-07-25), Hook 1 managed-autoinit: strukturell als
// 'array of T' deklarierte Locals sind DYNAMISCHE Arrays - der Compiler
// initialisiert sie auf nil (managed wie string/Interface-Refs), ein
// read-without-write ist nie ein echter uninit-Bug -> IsManaged.
// BEWEIS-QUELLE ist die gestrippte Decl-QUELLZEILE (Kommentare zaehlen
// nie): der Parser konkateniert TypeRef-Tokens OHNE Spaces
// (ParseLocalVarSection, 'arrayofbyte') - dort waere ein dynamisches
// Array NICHT von einem NAMENSTYP 'ArrayOfByte' unterscheidbar, dessen
// Fremd-Decl ('array[0..7] of Byte'?) wir nicht kennen. Genau das ist
// die Homonym-Maskierungs-Falle der HeidiSQL-Lehre; ein AddKindStrong-/
// TypeIndex-Gate braucht es hier trotzdem NICHT, weil am Ende reine
// strukturelle SYNTAX gematcht wird ('array' + PFLICHT-Whitespace +
// 'of' auf der Quellzeile) - die kann kein Bezeichner tragen, ein
// Homonym ist damit konstruktiv unmoeglich. Konservative Ausfall-
// richtung: mehrzeilige Decls, 'packed array of', unerreichbare Zeile
// -> False -> Fund bleibt. Wirkung ist ausschliesslich zusaetzliche
// IsManaged-Suppression -> monoton, nie neue Funde.
var
  L       : string;
  P, q, NL : Integer;
begin
  Result := False;
  // Vorfilter aus dem AST: der Token-konkatenierte TypeRef muss mit
  // 'array' beginnen ('arrayof...' bzw. Space-Variante) - alles andere
  // kann keine 'array of'-Decl sein (spart den Zeilen-Scan).
  if not TypeLow.StartsWith('array') then Exit;
  if (Lines = nil) or (DeclLine < 1) or (DeclLine > Lines.Count) then Exit;
  L := LowerCase(StripCommentsAndStrings(Lines[DeclLine - 1]));
  NL := Length(NameLow);
  if NL = 0 then Exit;
  // Ersten WORTGEBUNDENEN Match des Var-Namens suchen ('a' matcht nicht
  // in 'var'/'byte').
  P := 1;
  while True do
  begin
    P := PosEx(NameLow, L, P);
    if P = 0 then Exit;
    if ((P = 1) or not IsIdentChar(L[P - 1])) and
       ((P + NL > Length(L)) or not IsIdentChar(L[P + NL])) then
      Break;
    P := P + NL;
  end;
  // Zwischen Name und ':' nur weitere Idents der Komma-Liste/Whitespace
  // zulassen - so suppresst 'a: Integer; b: array of Byte;' die Var a
  // NICHT mit (deren Typteil beginnt am EIGENEN ':').
  q := P + NL;
  while (q <= Length(L))
        and CharInSet(L[q], ['a'..'z', '0'..'9', '_', ',', ' ', #9]) do
    Inc(q);
  if (q > Length(L)) or (L[q] <> ':') then Exit;
  Inc(q);
  while (q <= Length(L)) and (L[q] <= ' ') do Inc(q);
  // 'array' + PFLICHT-Whitespace + wortgebundenes 'of': exakt die Form,
  // die ein Bezeichner nie haben kann. 'array[0..3] of' (statisch,
  // NICHT managed) scheitert am Whitespace-Muss nach 'array'.
  if Copy(L, q, 5) <> 'array' then Exit;
  Inc(q, 5);
  if (q > Length(L)) or (L[q] > ' ') then Exit;
  while (q <= Length(L)) and (L[q] <= ' ') do Inc(q);
  if Copy(L, q, 2) <> 'of' then Exit;
  Inc(q, 2);
  if (q <= Length(L)) and IsIdentChar(L[q]) then Exit;
  Result := True;
end;

function IsAsmMethod(MethodNode: TAstNode): Boolean;
begin
  Result := (MethodNode <> nil)
        and (Pos(ASM_MARKER, LowerCase(MethodNode.TypeRef)) > 0);
end;

function MethodHasAsmBlock(Lines: TStringList; StartLine, EndLine: Integer): Boolean;
// True wenn im Zeilenbereich [StartLine..EndLine] eine Zeile den asm-Block-Start
// traegt (getrimmt 'asm' bzw. 'asm '/'asm;'). Fuer EMBEDDED asm-Bloecke
// ('begin ... asm mov Local, eax end ... end'), die IsAsmMethod (';asm'-Marker =
// GANZE asm-Methode) nicht erfasst: der Parser skippt tkKwAsm ohne Knoten, die im
// asm per Register/Memory-Ref geschriebenen Locals sind unsichtbar -> read-vor-
// write-FP (Real-World: CnWizFeedbackFrm GetCPUSpeed RDTSC 'mov TimerLo, eax').
// Kommentare (// UND {..}/(*..*) cross-line via StripLineEx) + String-Literale
// werden geblankt -> ein AUSKOMMENTIERTER 'asm'-Block matcht NICHT (wichtig, da
// SCA166 error-level ist - ein Fehl-Skip wuerde einen echten uninit maskieren).
// 'asm' ist reserviert -> eine sonst leere gestrippte Zeile mit 'asm' ist immer
// der Block-Start. TP-sicher: kein False-Positive.
var
  i     : Integer;
  T     : string;
  State : TLineStripState;
begin
  Result := False;
  if Lines = nil then Exit;
  State := Default(TLineStripState);
  for i := StartLine to EndLine do
  begin
    if (i < 1) or (i > Lines.Count) then Continue;
    T := LowerCase(Trim(StripLineEx(Lines[i - 1], State)));
    if (T = 'asm') or T.StartsWith('asm ') or T.StartsWith('asm;') then Exit(True);
  end;
end;

type
  TLineRange = record
    StartLine, EndLine : Integer;
  end;

// Note: AST-basierte Nested-Method-Detection wurde im Block-1-Cleanup
// entfernt — der Parser entfernt den Outer-MethodNode bei
// 'Headless-Method'-Pattern (ParseMethodImpl), nested-Procedures landen
// NICHT als nkMethod-Children. Audit zeigte -4 Findings Effekt.
// Phase 2.6 (CollectNestedMethodRangesViaSource unten) ist die effektive
// Alternative.

function IsLineInRanges(Line: Integer;
  const Ranges: TList<TLineRange>): Boolean;
var
  i : Integer;
begin
  Result := False;
  if (Ranges = nil) or (Line <= 0) then Exit;
  for i := 0 to Ranges.Count - 1 do
    if (Line >= Ranges[i].StartLine) and (Line <= Ranges[i].EndLine) then
      Exit(True);
end;

function IsVarUsedInNestedRanges(Lines: TStringList;
  const NameLow: string; const Ranges: TList<TLineRange>): Boolean;
// Prueft ob NameLow als Identifier (mit Wortgrenzen) in einer der
// Nested-Method-Source-Zeilen auftaucht. Wenn ja, ist die Variable
// vermutlich eine outer-scope-Var die als Closure in nested-Procs
// benutzt wird - der Detector kann ihren Lifecycle nicht zuverlaessig
// rekonstruieren (Aufruf-Reihenfolge der nested-Procs vs outer-body
// Assignment-Stelle = path-sensitive). Konservativ: kein Finding.
//
// Loest die FP-Klasse 'Cands.Add(...) in AddRoots, Cands := ... in
// outer-body NACH der nested-Proc-Definition' (FindRulesConfig-Pattern
// in uRuleCatalog.pas und 4 weitere im Self-Scan).
var
  i, j, k : Integer;
  L       : string;
  NameLen : Integer;
  P       : Integer;
  Before, After : Char;
begin
  Result := False;
  if (Lines = nil) or (Ranges = nil) or (NameLow = '') then Exit;
  NameLen := Length(NameLow);
  for k := 0 to Ranges.Count - 1 do
  begin
    for i := Ranges[k].StartLine - 1 to Ranges[k].EndLine - 1 do
    begin
      if (i < 0) or (i >= Lines.Count) then Continue;
      L := LowerCase(Lines[i]);
      P := Pos(NameLow, L);
      while P > 0 do
      begin
        if P > 1 then Before := L[P - 1] else Before := ' ';
        j := P + NameLen;
        if j <= Length(L) then After := L[j] else After := ' ';
        // Wortgrenzen: vor + nach Match darf kein Identifier-Char sein.
        if not (CharInSet(Before, ['a'..'z', '0'..'9', '_'])
             or CharInSet(After,  ['a'..'z', '0'..'9', '_'])) then
          Exit(True);
        P := Pos(NameLow, L, P + 1);
      end;
    end;
  end;
end;

function IsVarReadInNestedRoutineFromSource(Lines: TStringList;
  DeclLine: Integer; const NameLow: string): Boolean;
// Robuste, AST-UNABHAENGIGE Closure-Erkennung fuer die Headless-Method-FP-
// Klasse: eine outer-scope-Variable wird im outer-body erzeugt/zugewiesen,
// aber NUR in einer nested routine gelesen. Unter dem Headless-Pattern
// (nested routine + zweite var-Section) liefert der Parser die
// nkNestedRange-Marker / Method-End-Zeile nicht zuverlaessig -> weder der
// AST-Write noch IsVarUsedInNestedRanges (das auf eben diesen AST-Ranges
// arbeitet) greifen -> FP (uRuleCatalog Cands, uFormatMismatch Reported).
//
// Diese Funktion scannt rein auf Source-Ebene ab der ZUVERLAESSIGEN
// Deklarationszeile bis zum Outer-Body-'begin' (Spalte 0) und meldet True,
// wenn NameLow als Wort-Identifier im Rumpf einer nested routine
// (eingerueckter procedure/function-Header) vorkommt. Policy identisch zur
// bestehenden Closure-Regel (Closure-Vars werden nicht geflaggt) - nur
// robuster in der Erkennung, daher kein neuer FN-Typ.
var
  i, Dummy, Depth : Integer;
  Raw, LTrim      : string;
  InNested, Started : Boolean;

  function IsNestedHeader(const S: string): Boolean;
  var
    Lead, j : Integer;
    Low     : string;
  begin
    Result := False;
    Lead := 0;
    for j := 1 to Length(S) do
      if S[j] = ' ' then Inc(Lead)
      else if S[j] = #9 then Inc(Lead, 2)
      else Break;
    if Lead < 2 then Exit;               // Top-Level-Header = nicht nested
    Low := LowerCase(TrimLeft(S));
    Result := Low.StartsWith('procedure ')   or Low.StartsWith('procedure(') or
              Low.StartsWith('function ')    or Low.StartsWith('function(')  or
              Low.StartsWith('constructor ') or Low.StartsWith('destructor ');
  end;

begin
  Result := False;
  if (Lines = nil) or (NameLow = '') then Exit;
  if (DeclLine <= 0) or (DeclLine >= Lines.Count) then Exit;
  InNested := False; Depth := 0; Started := False;
  // Ab der Zeile NACH der Deklaration (0-based Index DeclLine = Quellzeile
  // DeclLine+1) bis zum Outer-Body-'begin'.
  for i := DeclLine to Lines.Count - 1 do
  begin
    Raw   := Lines[i];
    LTrim := LowerCase(TrimLeft(Raw));
    // Spalte-0-'begin' = Outer-Body-Start: Deklarations-/nested-Sektion vorbei.
    // Nachfolgende Reads waeren echter Outer-Body, keine Closure -> stop.
    if (Length(Raw) > 0) and (Raw[1] > ' ') and LTrim.StartsWith('begin') then Break;
    if not InNested and IsNestedHeader(Raw) then
    begin
      InNested := True; Depth := 0; Started := False;
    end;
    if InNested then
    begin
      if CountWholeWordOccurrences(NameLow, LTrim, Dummy) > 0 then Exit(True);
      if LTrim.StartsWith('begin') or (Pos(' begin ', ' ' + LTrim + ' ') > 0) then
      begin Inc(Depth); Started := True; end;
      if LTrim.StartsWith('end;') or LTrim.StartsWith('end ') or (LTrim = 'end') then
      begin
        Dec(Depth);
        if Started and (Depth <= 0) then InNested := False;
      end;
    end;
  end;
end;

procedure CollectNestedMethodRangesViaSource(Lines: TStringList;
  MethodStartLine, MethodEndLine: Integer;
  Ranges: TList<TLineRange>);
// Phase 2.6 - source-line-based Nested-Method-Detection.
//
// Hintergrund: Phase 2.4 (AST-basiert) wirkt nur wenn der Parser
// nested-Procedures als nkMethod-Children unter dem Outer-MethodNode
// ablegt. ParseMethodImpl entfernt aber bei 'Headless-Method'-Pattern
// den Outer-Knoten - nested-Pattern wird damit AST-seitig verloren.
//
// Source-basierter Workaround: scanne Lines im Range
// [MethodStartLine..MethodEndLine] nach Pattern
//   ^\s{2,}(procedure|function|constructor|destructor)\s+\w+
// (nested = mindestens 2 Leading-Spaces, distinct vom 0-indent Outer-
// Header). Pro nested-Header: count begin/end-Paare bis matching
// outer 'end;', dann Range eintragen.
var
  i, EndLine, Depth : Integer;
  L, LTrim : string;
  StartCol : Integer;
  Started : Boolean;
  R : TLineRange;

  function LineLooksLikeNestedHeader(const RawLine: string;
    out LeadingSpaces: Integer): Boolean;
  var
    j : Integer;
    Low : string;
  begin
    Result := False;
    LeadingSpaces := 0;
    for j := 1 to Length(RawLine) do
      if RawLine[j] = ' ' then Inc(LeadingSpaces)
      else if RawLine[j] = #9 then Inc(LeadingSpaces, 2)
      else Break;
    if LeadingSpaces < 2 then Exit;
    Low := LowerCase(TrimLeft(RawLine));
    Result := Low.StartsWith('procedure ')   or Low.StartsWith('procedure(') or
              Low.StartsWith('function ')    or Low.StartsWith('function(')  or
              Low.StartsWith('constructor ') or Low.StartsWith('destructor ');
  end;

  function IsTopLevelMethodHeader(const RawLine: string): Boolean;
  // True wenn die Zeile mit einem Method-Header beginnt der OHNE
  // Leading-Whitespace anfaengt (= top-level Implementation, nicht
  // nested). Wird gebraucht um den effektiven Scan-Start zurueck
  // auf den Function-Header zu trimmen wenn MethodNode.Line auf
  // den 'begin'-Block zeigt (passiert bei Methoden mit nested-
  // procs UND zweiter var-Section -> Parser-Headless-Pattern).
  var
    L : string;
  begin
    Result := False;
    if (Length(RawLine) = 0) or (RawLine[1] <= ' ') then Exit;
    L := LowerCase(RawLine);
    Result := L.StartsWith('procedure ')        or L.StartsWith('function ')        or
              L.StartsWith('constructor ')      or L.StartsWith('destructor ')      or
              L.StartsWith('class procedure ')  or L.StartsWith('class function ')  or
              L.StartsWith('class constructor ')or L.StartsWith('class destructor ');
  end;

  function ResolveActualMethodStart(AInitialStart: Integer): Integer;
  // Defensive: ist MethodNode.Line auf den 'begin'-Block gesprungen
  // (z.B. wenn Method nested-procs UND zweite var-Section hat), liegt
  // der echte Function-Header weiter oben. Wir scannen rueckwaerts
  // und nehmen die naechstliegende Zeile die mit 'function'/
  // 'procedure' OHNE Leading-Whitespace anfaengt. Stop bei Datei-
  // Anfang oder bei einer anderen schon abgeschlossenen Method-
  // Boundary (= 'end;' an Spalte 1, naive aber sichere Stopp-Regel).
  var
    j : Integer;
  begin
    Result := AInitialStart;
    if AInitialStart <= 1 then Exit;
    for j := AInitialStart downto 1 do
    begin
      if j - 1 >= Lines.Count then Continue;
      if IsTopLevelMethodHeader(Lines[j - 1]) then Exit(j);
      // Sentinel: vorherige Method beendet sich mit 'end;' an Spalte 1.
      if Lines[j - 1].StartsWith('end;') then Exit(AInitialStart);
    end;
  end;

var
  ActualStart : Integer;
begin
  if (Lines = nil) or (Ranges = nil) then Exit;
  if (MethodStartLine <= 0) or (MethodEndLine < MethodStartLine) then Exit;

  ActualStart := ResolveActualMethodStart(MethodStartLine);
  i := ActualStart - 1;
  while (i < Lines.Count) and (i < MethodEndLine) do
  begin
    L := Lines[i];
    if LineLooksLikeNestedHeader(L, StartCol) then
    begin
      R.StartLine := i + 1;
      // Suche begin/end-balanced bis matching 'end;' auf dem Sub-Indent
      Depth := 0;
      Started := False;
      EndLine := i + 1;
      while (i < Lines.Count) and (i < MethodEndLine) do
      begin
        LTrim := LowerCase(TrimLeft(Lines[i]));
        // begin- und end-Tokens zaehlen (Wortgrenz-Match einfach reicht)
        if LTrim.StartsWith('begin') or (Pos(' begin ', ' ' + LTrim + ' ') > 0) then
        begin
          Inc(Depth);
          Started := True;
        end;
        // 'end' kommt am Zeilenanfang oder als 'end;' am Ende
        if LTrim.StartsWith('end;') or LTrim.StartsWith('end ')
           or (LTrim = 'end') then
        begin
          Dec(Depth);
          if Started and (Depth <= 0) then
          begin
            EndLine := i + 1;
            Break;
          end;
        end;
        Inc(i);
      end;
      R.EndLine := EndLine;
      Ranges.Add(R);
    end;
    Inc(i);
  end;
end;

procedure SinglePassCollectByKind(Root: TAstNode;
  Assigns, Calls, Fors, Ifs, Whiles, Cases: TList<TAstNode>);
// P1: Statt 8x MethodNode.FindAll(...) ueber den AST zu walken,
// einen einzigen DFS-Walk der Knoten in 6 Buckets verteilt. Spart
// ~7/8 der Tree-Walks pro Methode.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      case Cur.Kind of
        nkAssign:    if Assigns <> nil then Assigns.Add(Cur);
        nkCall:      if Calls   <> nil then Calls.Add(Cur);
        nkForStmt:   if Fors    <> nil then Fors.Add(Cur);
        nkIfStmt:    if Ifs     <> nil then Ifs.Add(Cur);
        nkWhileStmt: if Whiles  <> nil then Whiles.Add(Cur);
        nkCaseStmt:  if Cases   <> nil then Cases.Add(Cur);
      end;
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function CountChildrenRecursive(Node: TAstNode; Cap: Integer): Integer;
// Iterativ + Early-Exit bei Cap-Ueberschreitung. Verhindert
// Pathological-Method-Cost-Eskalation in der Inventur-Phase.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  Result := 0;
  if Node = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Node);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      Inc(Result);
      if Result > Cap then Exit;
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

// Identifier-Extraktion aus dem nkAssign.Name. Parser liefert hier
// LHS-Expression, z.B. 'X', 'Obj.X', 'X[i]'. Wir nehmen den linken
// nackten Identifier vor dem ersten Punkt/Bracket.
//
// Real-World-Sweep 2026-06-13: type-cast-LHS unwrappen.
// `cardinal(Sign) := $80808080;` -> 'cardinal(sign)' aus Parser.
// FastCode-CharPos und alte Pascal-Asm-Pattern nutzen das ueblich.
// Heuristik: wenn die LHS einen passenden Open-Paren hat und kein
// Klammer-Inhalt eine Komma-Liste ist, ziehen wir den Inhalt der
// Klammer als bare Identifier raus.
function ExtractBareIdent(const ExprName: string): string;
var
  i, LParen, RParen : Integer;
  C : Char;
  Inner : string;
begin
  Result := '';
  // Type-Cast-Form: 'cardinal(sign)' -> 'sign'.
  LParen := Pos('(', ExprName);
  if LParen > 0 then
  begin
    RParen := Pos(')', ExprName);
    if (RParen > LParen) and (Pos(',', Copy(ExprName, LParen + 1, RParen - LParen - 1)) = 0) then
    begin
      Inner := Trim(Copy(ExprName, LParen + 1, RParen - LParen - 1));
      for i := 1 to Length(Inner) do
      begin
        C := Inner[i];
        if IsIdentChar(C) then
          Result := Result + C
        else
          Break;
      end;
      if Result <> '' then Exit;
    end;
  end;
  for i := 1 to Length(ExprName) do
  begin
    C := ExprName[i];
    if IsIdentChar(C) then
      Result := Result + C
    else
      Break;
  end;
end;

procedure CollectBodyTokens(Root: TAstNode; SB: TStringBuilder);
// Iterativ analog uUnusedLocal.CollectAllTokens - sammelt Name+TypeRef.
var
  Stack : TStack<TAstNode>;
  Cur   : TAstNode;
  i     : Integer;
begin
  if Root = nil then Exit;
  Stack := TStack<TAstNode>.Create;
  try
    Stack.Push(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack.Pop;
      if Cur.Name    <> '' then SB.Append(' ').Append(Cur.Name);
      if Cur.TypeRef <> '' then SB.Append(' ').Append(Cur.TypeRef);
      for i := 0 to Cur.Children.Count - 1 do
        Stack.Push(Cur.Children[i]);
    end;
  finally
    Stack.Free;
  end;
end;

function LooksLikeRealLocalVar(Lines: TStringList; LineNo1: Integer): Boolean;
// Filtert nested-Routine-Headers die der Parser als nkLocalVar liefert
// (siehe uUnusedLocal.LooksLikeRealLocalVar). Wenn Lines fehlt -> akzeptieren.
//
// Real-World-Sweep 2026-06-13: Pascal-`label`-Section schluesselt sich
// in einigen Files unklar in den nkLocalVar-Stream ein (alter FastCode-
// Asm-Code mit `label Next, Last4, ...;`). Wenn die Source-Line direkt
// vor LineNo1 nur 'label' (optional whitespace) enthaelt, ist LineNo1
// die Label-Liste - kein echter Local-Var. Symptom in cnwizards/
// FastCodeCharPosUnit.pas (~22 FPs pro Funktion).
var
  S, T : string;

  function IsLabelKeywordLine(const Raw: string): Boolean;
  var R : string;
  begin
    R := LowerCase(Trim(Raw));
    Result := (R = 'label') or R.StartsWith('label ') or R.StartsWith('label;');
  end;

begin
  Result := True;
  if (Lines = nil) or (LineNo1 <= 0) or (LineNo1 > Lines.Count) then Exit;
  S := Lines[LineNo1 - 1];
  T := LowerCase(TrimLeft(S));
  if T.StartsWith('procedure ')   or T.StartsWith('procedure(') or
     T.StartsWith('function ')    or T.StartsWith('function(')  or
     T.StartsWith('constructor ') or T.StartsWith('destructor ')or
     T.StartsWith('operator ')    or T.StartsWith('class procedure ') or
     T.StartsWith('class function ') then
    Exit(False);
  // Wenn vorherige nicht-leere Line das 'label'-Keyword war, ist die
  // aktuelle Zeile eine Label-Liste und keine Var-Declaration.
  var Probe := LineNo1 - 2;
  while (Probe >= 0) and (Trim(Lines[Probe]) = '') do Dec(Probe);
  if (Probe >= 0) and IsLabelKeywordLine(Lines[Probe]) then Exit(False);
  // Zusatzform: 'label X, Y, Z;' single-line - die LineNo1 selbst startet
  // mit 'label '. Damit fangen wir Inline-Labels ab.
  if IsLabelKeywordLine(S) then Exit(False);
end;

function IsParserArtifactTypeRef(const TypeRef: string): Boolean;
// SCA166-Scope-Mis-Attribution (2026-07-14, per AST-Dump von 18 realen Korpus-
// Faellen verifiziert). Der Parser emittiert fuer fehl-geparste Konstrukte
// nkLocalVar-Knoten mit MALFORMEDEM TypeRef, der ')' oder '=' enthaelt:
//   - Nested-Routine-Parameter        -> ') ' / ') : Typ'  (z.B. 'Boolean )',
//                                        'PByte ) : Int64')  [CnWizIdeUtils:2950,
//                                        mormot.core.buffers:3185]
//   - Function-Pointer-Typ-Return-Tail -> '):HRESULT'       (z.B.
//                                        'TSHStockIconInfo):HRESULT')  [ushlobjadditional:165]
//   - Feld-`if X = nil then`-Statement -> '= nil'            (z.B.
//                                        'TCnPaletteWrapper = nil')  [CnWizIdeUtils:3188/3971/4108]
// TP-SICHER by construction:
//   ')' : ein echter Local hat nie ein SCHLIESSENDES ')' im Typ - der Parser
//         zerlegt Prozedur-Pointer-Typen (Dump #3), sodass der VAR-NAME-Knoten
//         nur '(' (offen) traegt; ')' erscheint ausschliesslich in geleakten
//         Parameter-/Return-Tail-Fragmenten (keine echten Vars). Ein echter
//         uninit-Proz-Pointer-Read (Var-Name-Knoten, '(' offen) bleibt erhalten.
//   '=' : waere 'X: T = wert' ein echter initialisierter Local, ist er
//         GESCHRIEBEN -> ohnehin kein uninit-Read.
// Dump-Beleg: beruehrte 0 echte Locals + 0 Inline-Vars. Bare-'(' (Proz-Pointer-
// Var-Name) bewusst NICHT gefiltert, um echte Proz-Pointer-TPs nicht zu maskieren.
begin
  Result := (Pos(')', TypeRef) > 0) or (Pos('=', TypeRef) > 0);
end;

// ExtractCallFunctionName + ExtractCallArgsRaw wurden nach
// uDetectorUtils verschoben (Block 1b - geteilte Expression-Helper).
// Aufrufe via TDetectorUtils.ExtractCallFunctionName / .ExtractCallArgsRaw.

function ExtractForLoopVar(const ForTypeRef: string): string;
// TypeRef von nkForStmt enthaelt den Loop-Header, z.B.:
//   'i := 0 to 10'
//   'var x: Integer := 0 to 10'    (inline-var Form, aber inline-var hat
//                                   auch nkLocalVar-Child)
//   'i in container'
//   'VAR\tx := 0 to 10'             (Tab statt Space, case-mixed)
// Wir extrahieren den ersten Identifier nach optionalem 'var'-Keyword.
var
  S, Token : string;
  i, Start, KwLen : Integer;
begin
  Result := '';
  S := Trim(ForTypeRef);
  if S = '' then Exit;
  // Optional 'var'-Keyword (case-insensitive) ueberspringen — mit
  // beliebigem Whitespace (Space oder Tab) als Trennzeichen.
  if (Length(S) >= 4)
     and SameText(Copy(S, 1, 3), 'var')
     and (S[4] <= ' ') then
  begin
    KwLen := 3;
    while (KwLen + 1 <= Length(S)) and (S[KwLen + 1] <= ' ') do Inc(KwLen);
    S := Copy(S, KwLen + 1, MaxInt);
  end;
  // Erstes Token = Identifier-Chars + optional Punkt-Qualifier brechen wir
  // an Non-IdentChar ab.
  Start := 1;
  while (Start <= Length(S)) and (S[Start] <= ' ') do Inc(Start);
  i := Start;
  while (i <= Length(S)) and IsIdentChar(S[i]) do Inc(i);
  Token := Copy(S, Start, i - Start);
  Result := Token;
end;

function IsWriteAllowlistCall(const CallName: string): Boolean;
var
  FnName, Allow : string;
begin
  Result := False;
  FnName := LowerCase(TDetectorUtils.ExtractCallFunctionName(CallName));
  if FnName = '' then Exit;
  for Allow in WRITE_ALLOWLIST do
    if FnName = Allow then Exit(True);
end;

function IsReadOnlyCall(const CallName: string): Boolean;
// True wenn der Call seine Args garantiert NICHT schreibt. Default
// (weder Read- noch Write-Allowlist) = pessimistic-Write.
var
  FnName, Allow : string;
begin
  Result := False;
  FnName := LowerCase(TDetectorUtils.ExtractCallFunctionName(CallName));
  if FnName = '' then Exit;
  for Allow in READ_ALLOWLIST do
    if FnName = Allow then Exit(True);
end;

// TExprCall + ParseCallsInExpr nach uDetectorUtils verschoben (Block 1b).
// IsIdentStart-Helper damit ebenfalls obsolet (war nur fuer ParseCallsInExpr).

function FindIdentInArgList(const ArgsLow, NeedleLow: string): Boolean;
// Wortgrenz-Match fuer einen Identifier in der (lowercase) Arg-Liste.
var
  P, NL, L : Integer;
  Before, After : Char;
begin
  Result := False;
  NL := Length(NeedleLow);
  L  := Length(ArgsLow);
  if (NL = 0) or (L < NL) then Exit;
  P := 1;
  while True do
  begin
    P := PosEx(NeedleLow, ArgsLow, P);
    if P = 0 then Exit;
    Before := #0;
    if P > 1 then Before := ArgsLow[P - 1];
    After := #0;
    if P + NL - 1 < L then After := ArgsLow[P + NL];
    if not IsIdentChar(Before) and not IsIdentChar(After) then Exit(True);
    P := P + NL;
  end;
end;

function LineFillsVarViaReadCall(const LLow, NameLow: string): Boolean;
// True wenn die (bereits lowercase + comment/string-stripped) Zeile einen
// Read-Family-Call (READ_FILL_FUNCS, bare oder '<recv>.read') enthaelt,
// dessen Argumentliste NameLow als Wort-Identifier fuehrt. Diese RTL-
// Methoden FUELLEN ihre Buffer-Argumente -> das ist ein WRITE, kein Read.
// Wortgrenze davor (kein Ident-Char; '.' erlaubt fuer 'Stream.Read') +
// '(' direkt danach schliessen ReadInteger/ReadString/MyRead etc. aus.
var
  Fn, Args : string;
  i, FnLen, J, K, Depth : Integer;
  Before : Char;
begin
  Result := False;
  if (LLow = '') or (NameLow = '') then Exit;
  for Fn in READ_FILL_FUNCS do
  begin
    FnLen := Length(Fn);
    i := 1;
    while True do
    begin
      i := PosEx(Fn, LLow, i);
      if i = 0 then Break;
      if i > 1 then Before := LLow[i - 1] else Before := ' ';
      J := i + FnLen;                         // Position direkt nach dem Namen
      while (J <= Length(LLow)) and (LLow[J] = ' ') do Inc(J);
      if (not IsIdentChar(Before))
         and (J <= Length(LLow)) and (LLow[J] = '(') then
      begin
        Depth := 1; K := J + 1;
        while (K <= Length(LLow)) and (Depth > 0) do
        begin
          if LLow[K] = '(' then Inc(Depth)
          else if LLow[K] = ')' then Dec(Depth);
          Inc(K);
        end;
        Args := Copy(LLow, J + 1, K - (J + 1) - 1);
        if FindIdentInArgList(Args, NameLow) then Exit(True);
      end;
      i := i + FnLen;
    end;
  end;
end;

function IsInitVerb(const MethodLow: string): Boolean;
// Konservative Init-Verb-Allowlist fuer record-/value-typisierte Receiver deren
// Typ NICHT als in-Unit-Record aufloesbar ist (cross-unit). 'from' ergaenzt
// From*-Initialiser (mORMot T.FromHttpDate / TSynDate.From) - From* ist ein
// Init-Idiom das praktisch nie mit einem Value-Reader kollidiert.
begin
  Result := StartsStr('init', MethodLow) or StartsStr('from', MethodLow) or
            (MethodLow = 'start') or (MethodLow = 'full') or
            (MethodLow = 'hash')  or (MethodLow = 'reset') or
            (MethodLow = 'done')  or (MethodLow = 'prepare');
end;

function LineWritesViaTypecastAssign(const LLow, NameLow: string): Boolean;
// True wenn NameLow in der (bereits lowercase+stripped) Zeile als Ziel eines
// Typecast-Assignments steht: 'TFoo(name) := ...' bzw. 'TFoo<T>(name) := ...'
// (optional '^' Deref nach der Klammer). Das ist ein WRITE von name; der
// '^name :='-Scan in FindFirstSourceWriteLine erfasst es nicht, weil name
// nicht am Zeilenanfang steht -> dominante SCA166-FP-Klasse
// 'typecast-assignment-target'.
var
  P, NL, LL, q : Integer;
  Before2 : Char;
begin
  Result := False;
  NL := Length(NameLow);
  LL := Length(LLow);
  if (NL = 0) or (LL < NL + 4) then Exit;
  P := 1;
  while True do
  begin
    P := PosEx(NameLow, LLow, P);
    if P = 0 then Break;
    // Wortgrenzen
    if (P > 1) and IsIdentChar(LLow[P - 1]) then begin P := P + NL; Continue; end;
    if (P + NL <= LL) and IsIdentChar(LLow[P + NL]) then begin P := P + NL; Continue; end;
    // Vor name muss '(' stehen, und davor ein Ident-Char (Typname) oder '>'
    // (Generic-Cast 'TFoo<T>(name)').
    if (P >= 2) and (LLow[P - 1] = '(') then
    begin
      Before2 := #0;
      if P >= 3 then Before2 := LLow[P - 2];
      if IsIdentChar(Before2) or (Before2 = '>') then
      begin
        q := P + NL;                       // Position des schliessenden ')'
        if (q <= LL) and (LLow[q] = ')') then
        begin
          Inc(q);
          while (q <= LL) and (LLow[q] = ' ') do Inc(q);
          if (q <= LL) and (LLow[q] = '^') then
          begin
            Inc(q);
            while (q <= LL) and (LLow[q] = ' ') do Inc(q);
          end;
          if (q < LL) and (LLow[q] = ':') and (LLow[q + 1] = '=') then Exit(True);
        end;
      end;
    end;
    P := P + NL;
  end;
end;

function PrecededByIntrinsicOpen(const LLow: string; NamePos: Integer): Boolean;
// True wenn der Identifier an NamePos direkt Argument von low(/high(/sizeof(/
// typeinfo(/length( ist. Diese lesen den WERT NICHT (Compile-time, Typ- bzw.
// Groessen-Query), zaehlen also nicht als Read (FP-Klasse 'low-high-not-read').
// Recharakterisierung after30 (2026-07-12): Length(arr) ist eine Groessen-Query
// - fuer dynamische Arrays/Strings liefert sie 0 bei nil OHNE die Element-Inhalte
// zu lesen, fuer statische Arrays ist sie compile-time -> nie ein uninit-Read.
// LLow lowercase.
const
  INTR : array[0..4] of string = ('low', 'high', 'sizeof', 'typeinfo', 'length');
var
  sp, ep, k, pp : Integer;
  kw : string;
begin
  Result := False;
  // B2 Hook 2 (Triage 2026-07-25): Whitespace-tolerant. 'SizeOf (Buf)' /
  // 'SizeOf( nfo )' / 'SizeOf {n} (x)' fielen durch die Null-Abstand-
  // Pruefung - StripLineEx blankt Kommentar-/String-Inhalt zu SPACES und
  // erzeugt solche Luecken sogar selbst. Rueckwaerts Spaces vor dem Namen
  // skippen, dann '(' verlangen, davor erneut Spaces skippen, dann der
  // Keyword-Walk wie bisher. Reine Read-Suppression (FirstReadLine kann
  // nur 0 werden oder spaeter ruecken) -> monoton, nie neue Funde. Das
  // Restrisiko user-definierter Routinen namens SizeOf/Length/... ist fuer
  // die Null-Abstand-Form seit after30 akzeptiert (s.o.); die Toleranz
  // verbreitert es nur marginal (Shadowing der 5 RTL-Intrinsics ist
  // praktisch inexistent). NICHT fuer die READ_ALLOWLIST: 'writeln (u)'
  // bleibt ein Read.
  pp := NamePos - 1;
  while (pp >= 1) and (LLow[pp] = ' ') do Dec(pp);
  if (pp < 1) or (LLow[pp] <> '(') then Exit;
  ep := pp - 1;                            // Char vor '(' (Spaces tolerieren)
  while (ep >= 1) and (LLow[ep] = ' ') do Dec(ep);
  if ep < 1 then Exit;
  sp := ep;
  while (sp >= 1) and IsIdentChar(LLow[sp]) do Dec(sp);
  if ep < sp + 1 then Exit;
  kw := Copy(LLow, sp + 1, ep - sp);
  for k := 0 to High(INTR) do
    if kw = INTR[k] then Exit(True);
end;

function IsConstDeclLine(const LineLow: string): Boolean;
// Erkennt eine Konstanten-Deklarationszeile (bereits lowercase+stripped):
//   'szf=regcszd;'        (untypisiert)
//   'szf = regcszd;'
//   'szf: byte = 5;'      (typisierte Konstante)
// FP-Klasse 'conditional-compilation-const' (Real-World-FP-Audit 2026-07-10,
// DAsmUtil.pas:497/574): derselbe Bezeichner ist im einen {$IFDEF}-Zweig
// 'var X: T' (nkLocalVar) und im anderen 'const X = Wert'. Der Lexer sieht
// BEIDE Zweige; die const-Zeile des inaktiven Zweigs wurde als Read des
// var-Zweig-Locals fehlgedeutet. Eine const-Deklaration ist NIE ein Read
// einer lokalen Variable (ihr RHS muss ein Compile-time-Konstanten-Ausdruck
// sein und kann daher keine Local lesen) -> blanket-skip ist TP-sicher.
//
// Mini-Parser: fuehrender EINZELNER Identifier, optional ': type', dann ein
// einzelnes '=' (kein ':=' Assignment), Zeile endet mit ';'. Mehr-Ident-
// Formen ohne Komma/Doppelpunkt (z.B. 'if a = b then ...;') werden bewusst
// abgelehnt, damit keine echte Lese-Anweisung faelschlich uebersprungen wird.
var
  T : string;
  i, L : Integer;
begin
  Result := False;
  T := Trim(LineLow);
  L := Length(T);
  if L < 3 then Exit;
  if T[L] <> ';' then Exit;
  if not CharInSet(T[1], ['a'..'z', '_']) then Exit;
  // 1) fuehrender Identifier
  i := 1;
  while (i <= L) and IsIdentChar(T[i]) do Inc(i);
  // 2) Whitespace
  while (i <= L) and CharInSet(T[i], [' ', #9]) do Inc(i);
  if i > L then Exit;
  // 3a) typisierte Konstante 'ident: type = value'
  if T[i] = ':' then
  begin
    Inc(i);
    if (i <= L) and (T[i] = '=') then Exit;      // ':=' Assignment, keine const-Decl
    while (i <= L) and (T[i] <> '=') do
    begin
      // Type-Teil: nur Ident/Space/Punkt/Generic/Komma - KEIN Operator/Klammer.
      if not CharInSet(T[i], ['a'..'z', '0'..'9', '_', ' ', #9, '.', '<', '>', ',']) then Exit;
      Inc(i);
    end;
    if i > L then Exit;                           // kein '=' -> keine const-Decl
  end;
  // 3b) jetzt MUSS ein einzelnes '=' folgen
  if (i > L) or (T[i] <> '=') then Exit;
  Result := True;
end;

function IsParamMisparseDeclLine(const DeclLow, NameLow: string): Boolean;
// B2 Hook 4 (Triage 2026-07-25): ParseLocalVarSection laeuft in die
// Parameterlisten lokaler proc-Typen/Signaturen HINEIN und liefert deren
// Parameter (bzw. den TYP-Ident bei keyword-benannten Params wie
// 'out result: RawUtf8') als nkLocalVar-Phantome. IsParserArtifactTypeRef
// faengt nur Fragmente MIT ')' im TypeRef - Mittel-Parameter ('uFlags:
// UINT;') und Typ-Ident-Leaks (TypeRef leer) rutschen durch. Zwei
// Zeilenformen, die eine ECHTE var-Decl nie hat (Parens im Typteil stehen
// NACH dem Namen und sind auf der Namenszeile balanciert bzw. nur nach
// rechts offen):
//   (a) netto-offenes '(' VOR dem ersten Wort-Match des Var-Namens
//       ('CB: procedure(a: X; uFlags: UINT; ...' - Mittel-Parameter),
//   (b) ')'-Ueberschuss ohne oeffnendes '(' auf der Zeile
//       ('out result: RawUtf8);' / 'c: Z) of object;' - Schlusszeilen
//       mehrzeiliger Parameterlisten).
// DeclLow muss bereits lowercase + comment/string-stripped sein (Kommentare
// zaehlen nie). Reine Inventur-Suppression -> monoton, nie neue Funde.
// Restrisiko exotischer Formatierung ('arg2); var x: Integer;' auf EINER
// Zeile) bewusst akzeptiert; der Mittel-Parameter ALLEIN auf eigener Zeile
// bleibt lexikalisch von einer echten Decl ununterscheidbar (Residual-FP,
// nur per Parser-Fix mit Paren-Depth-Tracking loesbar - Backlog).
var
  i, Bal, FirstPos : Integer;
begin
  Result := False;
  if (DeclLow = '') or (NameLow = '') then Exit;
  // (b) Netto-')'-Ueberschuss der ganzen Zeile
  Bal := 0;
  for i := 1 to Length(DeclLow) do
    if DeclLow[i] = '(' then Inc(Bal)
    else if DeclLow[i] = ')' then Dec(Bal);
  if Bal < 0 then Exit(True);
  // (a) netto-offenes '(' vor dem ersten Wort-Match des Namens. Kein
  // Match auf der Zeile (Multi-Line-Decl, DeclLine zeigt auf die Typzeile)
  // -> konservativ NICHT skippen.
  if CountWholeWordOccurrences(NameLow, DeclLow, FirstPos) = 0 then Exit;
  Bal := 0;
  for i := 1 to FirstPos - 1 do
    if DeclLow[i] = '(' then Inc(Bal)
    else if DeclLow[i] = ')' then Dec(Bal);
  Result := Bal > 0;
end;

// Welle 3 (Core-Detektoren-Architektur): True wenn eine {$IFDEF}-Direktiven-
// Zeile STRIKT zwischen A und B liegt. Dann stehen die beiden Positionen (hier
// Read/Write einer Variablen) in verschiedenen bedingten Kompilierungs-Zweigen.
// Identische Logik wie uDeadCode.DirLineBetween (bewusst dupliziert, damit der
// Opt-in additiv/isoliert bleibt - keine neue Shared-Unit-Abhaengigkeit).
function DirLineBetween(const Lines: TArray<Integer>; A, B: Integer): Boolean;
var d: Integer;
begin
  for d in Lines do
    if (d > A) and (d < B) then Exit(True);
  Result := False;
end;

// ============================================================
// Zensus-Triage 2026-07-25, Hook 1b: Same-File-Signatur-Aufloesung
// fuer var/out-Parameter.
//
// Zensus-Klasse 'var-out-arg-write': der Fund-Read ankert auf einer
// Zeile, die in Wahrheit ein CALL einer im SELBEN File deklarierten
// Routine mit var/out-Formalparameter an genau dieser Arg-Position
// ist - der Call FUELLT die Variable. Das 3-Klassen-Modell haette den
// pessimistic-Write laengst registriert, wenn der Call im AST laege;
// die Zensus-FPs sind die Faelle, in denen der Call-Pfad FEHLT
// (Headless-Method-Pattern verliert Outer-Body-nkCalls; repeat/until-
// Bedingungen liegen gar nicht als Knoten vor). Die Signatur-
// Aufloesung ist STRENGER als der pessimistic-Write (sie verlangt den
// var/out-BEWEIS aus allen gleichnamigen Signaturen) und bleibt damit
// innerhalb der etablierten Policy - keine neue FN-Klasse.
// Konservativ per Konstruktion:
//   * nur BARE Args (Argtext == Var-Name; 'x[i]'/'@x'/casts nie),
//   * nur UNqualifizierte Calls ('obj.Foo(' koennte eine namensgleiche
//     Fremdklassen-Methode sein -> nicht aufloesen),
//   * Overloads AND-gemergt: die Position muss in ALLEN gleichnamigen
//     Signaturen var/out sein; parameterlose Redecls ('function X;
//     external ...') mergen auf leer = Name unaufloesbar,
//   * cross-unit/unaufloesbar -> kein Write, Fund bleibt.
// Reine Write-Registrierung -> monoton, nie neue Funde.
// ============================================================

function ParseSigParamFlags(const ParamsLow: string;
  out Flags: TArray<Boolean>): Boolean;
// Zerlegt den Klammer-Inhalt einer Signatur '(a: X; var b, c: Y; out d: Z)'
// (bereits lowercase + comment/string-stripped) in Formalparameter-
// Positionen: Flags[i] = True wenn Position i var/out ist. Result=False ->
// unparsbar (z.B. '[ref] const'-Attribut) - der Aufrufer merged den Namen
// dann auf leer (unaufloesbar, Fund bleibt).
var
  i, L, Depth, GStart : Integer;

  function AppendGroup(const G: string): Boolean;
  var
    T, NamesPart : string;
    IsVO : Boolean;
    cp, n, k : Integer;
  begin
    Result := True;
    T := Trim(G);
    if T = '' then Exit;                       // '()' -> 0 Positionen
    if T[1] = '[' then Exit(False);            // '[ref] const ...' -> unparsbar
    IsVO := T.StartsWith('var ') or T.StartsWith('out ');
    // Namens-Teil = vor dem ':' (untypisiertes 'var buf' = ganze Gruppe).
    // Modifier-Woerter enthalten kein Komma -> Zaehlung bleibt korrekt.
    cp := Pos(':', T);
    if cp > 0 then NamesPart := Copy(T, 1, cp - 1) else NamesPart := T;
    n := 1;
    for k := 1 to Length(NamesPart) do
      if NamesPart[k] = ',' then Inc(n);
    for k := 1 to n do
      Flags := Flags + [IsVO];
  end;

begin
  Flags := nil;
  Result := True;
  L := Length(ParamsLow);
  Depth := 0;
  GStart := 1;
  for i := 1 to L do
    case ParamsLow[i] of
      '(', '[': Inc(Depth);
      ')', ']': Dec(Depth);
      ';': if Depth = 0 then
           begin
             if not AppendGroup(Copy(ParamsLow, GStart, i - GStart)) then
               Exit(False);
             GStart := i + 1;
           end;
    end;
  if not AppendGroup(Copy(ParamsLow, GStart, L - GStart + 1)) then
    Exit(False);
end;

function BuildSameFileVarOutIndex(Lines: TStringList)
  : TDictionary<string, TArray<Boolean>>;
// Scannt die GESTRIPPTE Quelle (Interface + Implementation, Multi-Line-
// Kommentare via StripLineEx-State) nach Routinen-Headern und baut
// Name -> var/out-Flag je Parameterposition. Key = letztes Namenssegment
// ('TFoo.Bar' -> 'bar', so wie der Call im Body lautet); Generics im
// Namen ('TFoo<T>.Bar') werden uebersprungen. Mehrzeilige Parameterlisten
// werden bis zur schliessenden Klammer eingesammelt (Cap 40 Zeilen).
const
  KWS : array[0..3] of string =
    ('procedure ', 'function ', 'constructor ', 'destructor ');
var
  State : TLineStripState;
  i, k, p, e, Depth, Guard : Integer;
  S, T, Name, Params : string;
  Flags, Old, Merged : TArray<Boolean>;
  Matched : Boolean;

  procedure Merge(const AName: string; const AFlags: TArray<Boolean>);
  // Overload-Merge: AND je Position, gekappt auf die kuerzere Liste.
  // Leere Liste (parameterlose Redecl / unparsbare Signatur) macht den
  // Namen damit dauerhaft unaufloesbar - konservativ (Fund bleibt).
  var
    NewLen, m : Integer;
  begin
    if AName = '' then Exit;
    if Result.TryGetValue(AName, Old) then
    begin
      NewLen := Length(Old);
      if Length(AFlags) < NewLen then NewLen := Length(AFlags);
      SetLength(Merged, NewLen);
      for m := 0 to NewLen - 1 do
        Merged[m] := Old[m] and AFlags[m];
      Result.AddOrSetValue(AName, Merged);
    end
    else
      Result.Add(AName, Copy(AFlags));
  end;

begin
  Result := TDictionary<string, TArray<Boolean>>.Create;
  if Lines = nil then Exit;
  State := Default(TLineStripState);
  i := 0;
  while i < Lines.Count do
  begin
    S := LowerCase(StripLineEx(Lines[i], State));
    Inc(i);
    T := TrimLeft(S);
    if T.StartsWith('class ') then T := TrimLeft(Copy(T, 7, MaxInt));
    Matched := False;
    for k := 0 to High(KWS) do
      if T.StartsWith(KWS[k]) then
      begin
        T := TrimLeft(Copy(T, Length(KWS[k]) + 1, MaxInt));
        Matched := True;
        Break;
      end;
    if not Matched then Continue;
    // Namenskette: Idents + '.' + optionale Generics; letztes Segment zaehlt.
    p := 1;
    Name := '';
    while p <= Length(T) do
    begin
      if IsIdentChar(T[p]) then
      begin
        e := p;
        while (e <= Length(T)) and IsIdentChar(T[e]) do Inc(e);
        Name := Copy(T, p, e - p);
        p := e;
      end
      else if T[p] = '<' then
      begin
        Depth := 1;
        Inc(p);
        while (p <= Length(T)) and (Depth > 0) do
        begin
          if T[p] = '<' then Inc(Depth)
          else if T[p] = '>' then Dec(Depth);
          Inc(p);
        end;
      end
      else if T[p] = '.' then
        Inc(p)
      else
        Break;
    end;
    while (p <= Length(T)) and (T[p] = ' ') do Inc(p);
    if Name = '' then Continue;
    if (p > Length(T)) or (T[p] <> '(') then
    begin
      // Parameterlose Decl bzw. Headless-Redecl ('function X; external') ->
      // Konflikt-Merge auf leer: Name unaufloesbar, Funde bleiben.
      Merge(Name, nil);
      Continue;
    end;
    // Parameter-Text einsammeln, ggf. ueber Folgezeilen (Cap 40).
    Params := '';
    Depth := 1;
    Inc(p);
    Guard := 0;
    repeat
      while (p <= Length(T)) and (Depth > 0) do
      begin
        if T[p] = '(' then Inc(Depth)
        else if T[p] = ')' then
        begin
          Dec(Depth);
          if Depth = 0 then Break;
        end;
        Params := Params + T[p];
        Inc(p);
      end;
      if Depth > 0 then
      begin
        if (i >= Lines.Count) or (Guard >= 40) then Break;
        T := LowerCase(StripLineEx(Lines[i], State));
        Inc(i);
        Inc(Guard);
        Params := Params + ' ';
        p := 1;
      end;
    until Depth = 0;
    if Depth <> 0 then Continue;               // unbalanciert -> ignorieren
    if ParseSigParamFlags(Params, Flags) then
      Merge(Name, Flags)
    else
      Merge(Name, nil);                        // unparsbar -> unaufloesbar
  end;
end;

function LineHasVarOutArgWriteFor(const LLow, NameLow: string;
  SigIdx: TDictionary<string, TArray<Boolean>>;
  Shadow: TDictionary<string, Integer>): Boolean;
// True wenn die (gestrippte, gelowerte) Zeile einen UNqualifizierten Call
// '<name>(args)' enthaelt, dessen Name via SigIdx aufgeloest ist und
// NameLow dort BARE an einer Position steht, die in ALLEN gleichnamigen
// Signaturen var/out ist. Shadow = VarMap der Methode: ist der Call-Name
// selbst eine getrackte Local (proc-Pointer-Var 'CB(1, 2)'), wird NICHT
// aufgeloest - der Call geht an die Variable, nicht an die Routine.
// Mehrzeilige Calls: nur die auf DIESER Zeile abgeschlossenen Args
// (Komma bzw. ')') werden gewertet - das letzte, unvollstaendige Arg
// bewusst nicht (konservativ).
var
  i, e, j, k, L, Depth, ArgIdx, ArgStart : Integer;
  Token : string;
  Flags : TArray<Boolean>;
  Prev : Char;

  function ArgHit(AStart, AEnd, AIdx: Integer): Boolean;
  begin
    Result := (AIdx <= High(Flags)) and Flags[AIdx]
          and (Trim(Copy(LLow, AStart, AEnd - AStart)) = NameLow);
  end;

begin
  Result := False;
  if (LLow = '') or (NameLow = '') or (SigIdx = nil) then Exit;
  L := Length(LLow);
  i := 1;
  while i <= L do
  begin
    if IsIdentChar(LLow[i]) and ((i = 1) or not IsIdentChar(LLow[i - 1])) then
    begin
      e := i;
      while (e <= L) and IsIdentChar(LLow[e]) do Inc(e);
      Token := Copy(LLow, i, e - i);
      Prev := #0;
      j := i - 1;
      while (j >= 1) and (LLow[j] = ' ') do Dec(j);
      if j >= 1 then Prev := LLow[j];
      j := e;
      while (j <= L) and (LLow[j] = ' ') do Inc(j);
      if (Prev <> '.') and (j <= L) and (LLow[j] = '(')
         and ((Shadow = nil) or not Shadow.ContainsKey(Token))
         and SigIdx.TryGetValue(Token, Flags) and (Length(Flags) > 0) then
      begin
        Depth := 1;
        ArgIdx := 0;
        k := j + 1;
        ArgStart := k;
        while (k <= L) and (Depth > 0) do
        begin
          case LLow[k] of
            '(', '[': Inc(Depth);
            ']': Dec(Depth);
            ')': begin
                   Dec(Depth);
                   if (Depth = 0) and ArgHit(ArgStart, k, ArgIdx) then
                     Exit(True);
                 end;
            ',': if Depth = 1 then
                 begin
                   if ArgHit(ArgStart, k, ArgIdx) then Exit(True);
                   Inc(ArgIdx);
                   ArgStart := k + 1;
                 end;
          end;
          Inc(k);
        end;
      end;
      i := e;
    end
    else
      Inc(i);
  end;
end;

function HasAdjacentFpcHideMarker(const RawLine, NameLow: string): Boolean;
// Zensus-Triage 2026-07-25, H3: FPC-'{%H-}'-Suppression an der Deklaration.
// ACHTUNG, bewusste Ausnahme von der 'Kommentare zaehlen nie'-Regel:
// '{%H-}' IST ein Kommentar (FPC-Direktive 'Hint an dieser Stelle
// unterdruecken') - genau deshalb wird hier die ROHE Quellzeile geprueft,
// nicht die gestrippte (dort ist der Marker weggeblankt). Der Autor hat
// den Hint an dieser Decl EXPLIZIT unterdrueckt (Lazarus-Konvention,
// z.B. 'FillChar-gefuellte' Puffer) - SCA166 respektiert den Intent.
// Adjazenz-Pflicht: der Marker muss (Spaces toleriert) DIREKT vor oder
// nach dem Var-Namen stehen - ein '{%H-}' an einer ANDEREN Var derselben
// Zeile suppresst nicht mit (H3-Gegenprobe HMarkerOtherVar_StillFlagged).
var
  L : string;
  P, NL, LL, q : Integer;
begin
  Result := False;
  if (RawLine = '') or (NameLow = '') then Exit;
  L := LowerCase(RawLine);
  if Pos('{%h-}', L) = 0 then Exit;
  NL := Length(NameLow);
  LL := Length(L);
  P := 1;
  while True do
  begin
    P := PosEx(NameLow, L, P);
    if P = 0 then Exit;
    if ((P = 1) or not IsIdentChar(L[P - 1])) and
       ((P + NL > LL) or not IsIdentChar(L[P + NL])) then
    begin
      // Marker direkt VOR dem Namen ('{%H-}Buf: ...')
      q := P - 1;
      while (q >= 1) and (L[q] = ' ') do Dec(q);
      if (q >= 5) and (Copy(L, q - 4, 5) = '{%h-}') then Exit(True);
      // Marker direkt NACH dem Namen ('Buf{%H-}: ...')
      q := P + NL;
      while (q <= LL) and (L[q] = ' ') do Inc(q);
      if Copy(L, q, 5) = '{%h-}' then Exit(True);
    end;
    P := P + NL;
  end;
end;

function IsFileDeclaredTypeName(Lines: TStringList;
  const NameLow: string): Boolean;
// Zensus-Triage 2026-07-25, H5 (Symptom-Gate keyword-misparse): traegt der
// gemeldete Var-NAME im selben File eine TYP-Deklaration ('<name> =
// class/record/...'), ist der nkLocalVar-Knoten mit hoher Sicherheit eine
// fehlgeparste Decl (der Parser hat einen Typnamen als Local eingesammelt)
// - nie eine echte Variable. Gestrippte Zeilen (Kommentare zaehlen nie),
// optionale Generics ('TFoo<T> = class'). Restrisiko einer ECHTEN Local,
// die exakt wie ein in-File-Typ heisst ('var Data: X' + 'Data = record'):
// bewusst akzeptiert - solches Shadowing ist in realem Code praktisch
// inexistent und das Symptom (Typname als Var gemeldet) dominiert.
const
  TYPE_KWS : array[0..6] of string =
    ('class', 'record', 'packed', 'object', 'interface', 'dispinterface',
     'type');
var
  i, p, e, Depth : Integer;
  T, Kw : string;
begin
  Result := False;
  if (Lines = nil) or (NameLow = '') then Exit;
  for i := 0 to Lines.Count - 1 do
  begin
    if Pos(NameLow, LowerCase(Lines[i])) = 0 then Continue;   // Quick-Reject
    T := TrimLeft(LowerCase(StripCommentsAndStrings(Lines[i])));
    if not T.StartsWith(NameLow) then Continue;
    p := Length(NameLow) + 1;
    if (p <= Length(T)) and IsIdentChar(T[p]) then Continue;  // Wortgrenze
    while (p <= Length(T)) and (T[p] = ' ') do Inc(p);
    if (p <= Length(T)) and (T[p] = '<') then                 // Generics
    begin
      Depth := 1;
      Inc(p);
      while (p <= Length(T)) and (Depth > 0) do
      begin
        if T[p] = '<' then Inc(Depth)
        else if T[p] = '>' then Dec(Depth);
        Inc(p);
      end;
      while (p <= Length(T)) and (T[p] = ' ') do Inc(p);
    end;
    if (p > Length(T)) or (T[p] <> '=') then Continue;
    Inc(p);
    while (p <= Length(T)) and (T[p] = ' ') do Inc(p);
    e := p;
    while (e <= Length(T)) and IsIdentChar(T[e]) do Inc(e);
    Kw := Copy(T, p, e - p);
    for var kk := 0 to High(TYPE_KWS) do
      if Kw = TYPE_KWS[kk] then Exit(True);
  end;
end;

// ============================================================
// HAUPT-LOGIK
// ============================================================

class procedure TUninitVarDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext; ARecordTypes: TDictionary<string, Boolean>;
  const ADirLines: TArray<Integer>;
  ASigVarOut: TDictionary<string, TArray<Boolean>>);
var
  LocalVars        : TList<TAstNode>;
  Assigns, Calls, Fors : TList<TAstNode>;
  VarMap           : TDictionary<string, Integer>;
  VarList          : TList<TVarInfo>;
  Lines            : TStringList;
  Cached           : Boolean;
  BodySB           : TStringBuilder;
  BodyLow          : string;
  NestedRanges     : TList<TLineRange>;
  // Perf (2026-07-05): P7-uninitvar - Method-End einmal berechnen (vorher
  // 2x kompletter AST-Walk: Orchestrator + PhaseC) und gestripptes,
  // gelowertes Zeilen-Array fuer den Methodenbereich einmal fuellen
  // (vorher strippten FindFirstSourceWriteLine + FindFirstReadLine pro
  // Variable JEDE Zeile neu = 2xVxL statt L StripLineEx-Durchlaeufe).
  MethodEndL       : Integer;
  StrippedLow      : TArray<string>;
  StrippedFrom0    : Integer;   // 0-basierter Lines-Index von StrippedLow[0]
  StrippedBuilt    : Boolean;   // lazy: erst bauen wenn ein Finder laeuft
  MaxChildren      : Integer;   // TD-1: Hard-Cap per-Scan aus AContext.Config
  MethodCfg        : TCFG;      // #6 Inkr.4: lazy im PhaseD-CFG-Postfilter
  AbsAliases       : TDictionary<string,string>; // A3: aliasLow -> zielLow ('absolute')

  procedure RegisterWrite(Idx: Integer; Line: Integer);
  var
    P : PVarInfo;
  begin
    if (Idx < 0) or (Idx >= VarList.Count) or (Line <= 0) then Exit;
    P := @VarList.List[Idx];
    if (P.FirstWriteLine = 0) or (Line < P.FirstWriteLine) then
      P.FirstWriteLine := Line;
    // #6 Inkr.4: Def-Site fuer den CFG-Postfilter merken (Cap s. TVarInfo).
    if Length(P.WriteLines) < 64 then
      P.WriteLines := P.WriteLines + [Line];
  end;

  function VarIndexFor(const NameLow: string): Integer;
  var
    Tmp : Integer;
    Tgt : string;
  begin
    // A3 (Triage 2026-07-24, absolute-Alias-Klasse ~21/180): eine per
    // 'absolute' ueberlagerte Alias-Var wird in PhaseA nicht getrackt -
    // ihre Writes ('ta[j] := ...', var-Arg-Uebergabe) MUESSEN aber dem
    // ZIEL zugutekommen (isaac tl/ta, IdStackVCLPosix LAddrStore/LAddr).
    // Ein-Punkt-Fix: alle Registrierungs-Pfade laufen ueber VarIndexFor.
    if (AbsAliases <> nil) and AbsAliases.TryGetValue(NameLow, Tgt) then
    begin
      Result := VarIndexFor(Tgt);
      Exit;
    end;
    if VarMap.TryGetValue(NameLow, Tmp) then Result := Tmp else Result := -1;
  end;

  procedure RegisterArgVarsAsWrites(const ArgsLow: string; Line: Integer);
  // P2: Single-Pass-Tokenizer ueber ArgsLow. Pro Identifier-Token
  // Dictionary-Lookup in VarMap (O(args-Length) statt O(N x M) wie
  // vorher mit FindIdentInArgList-pro-Var). Pessimistic-Write Hit ->
  // RegisterWrite.
  var
    P, Start, Len : Integer;
    Idx : Integer;
    Token : string;
  begin
    Len := Length(ArgsLow);
    P := 1;
    while P <= Len do
    begin
      if IsIdentChar(ArgsLow[P]) then
      begin
        Start := P;
        while (P <= Len) and IsIdentChar(ArgsLow[P]) do Inc(P);
        Token := Copy(ArgsLow, Start, P - Start);
        Idx := VarIndexFor(Token);     // VarMap-Lookup, O(1) avg
        if Idx >= 0 then RegisterWrite(Idx, Line);
      end
      else
        Inc(P);
    end;
  end;

  procedure ApplyReceiverInit(const ReceiverLow, MethodLow: string; Line: Integer);
  // Receiver-Init-Pattern: ein Methodenaufruf auf einer record-/value-typisierten
  // lokalen Var initialisiert deren Felder (Self ist var-Parameter). Fuer in-Unit-
  // Records (ARecordTypes) zaehlt JEDER Methodenaufruf als Init; sonst konservative
  // Init-Verb-Allowlist (IsInitVerb). Klassen sind ausgenommen - ein Aufruf auf
  // einer uninitialisierten Klassen-Referenz ist ein echter Read (Bug) und wird
  // hier NICHT als Write gewertet (Idx-Typ ist dann keine in-Unit-Record).
  var
    Idx : Integer;
    TI  : TTypeIndex;
  begin
    if (ReceiverLow = '') or (MethodLow = '') then Exit;
    Idx := VarIndexFor(ReceiverLow);
    if Idx < 0 then Exit;
    if (ARecordTypes <> nil) and
       ARecordTypes.ContainsKey(BaseTypeLow(VarList.List[Idx].TypeLow)) then
      RegisterWrite(Idx, Line)
    else
    begin
      // Welle 2 strukturell (2026-07-18): cross-unit value-RECORD. Eine Record-
      // Methode bekommt Self implizit per var -> JEDER Aufruf initialisiert die
      // Felder (Delphi emittiert dafuer NIE einen uninit-Hint -> FN-neutral ggue.
      // dem Compiler, dessen Verhalten SCA166 spiegelt). In-Unit-Records deckt
      // ARecordTypes oben ab; diese Branch schliesst die cross-unit-Luecke via
      // TTypeIndex (dieselbe Infra die SCA114/124/161/174 konsumieren).
      // BEWUSST NUR tkiRecord, NICHT tkiEnum: Enum-Type-Helper sind ueberwiegend
      // READER (ToString/ToInteger/ToRoman) - 'e.ToString(f)' liest den Enum,
      // initialisiert ihn NICHT; als Write zu werten wuerde einen echten uninit-
      // Read maskieren (FN auf error-Tier, kein Enum-FP-Klasse-Beleg). Record-
      // Methoden dagegen mutieren das Aggregat = etablierte FP-Klasse.
      // TI=nil/leer im Single-File -> No-Op (nur per Korpus-A/B verifizierbar).
      // Monoton: registriert nur einen Write -> Fund-Zahl kann nur sinken.
      TI := CtxTypeIndex(AContext);
      if (TI <> nil) and (not TI.IsEmpty) and
         (TI.TypeKindOf(BaseTypeLow(VarList.List[Idx].TypeLow)) = tkiRecord) then
        RegisterWrite(Idx, Line)
      else if IsInitVerb(MethodLow) then
        RegisterWrite(Idx, Line);
    end;
  end;

  procedure RegisterCallArgWrites(const CallName: string; Line: Integer);
  // Real-World-FP-Audit 2026-07-12, FP-Klasse 'var-param-out-write' (Kat. A+D):
  // Ersetzt das alte ExtractCallArgsRaw (nahm nur die ERSTE Klammer-Gruppe).
  //   Kat. A: Receiver-/Cast-Praefix 'PFoo(x)^.Method(outVar)' lieferte 'x'
  //           statt 'outVar' -> outVar bekam keinen pessimistic-Write -> FP.
  //   Kat. D: String-Literal ')' im Arg brach die Paren-Zaehlung ab.
  // Fix: ueber ALLE Klammer-Gruppen des (string-gestrippten) Ausdrucks laufen
  // und pro Gruppe die Arg-Idents als pessimistic-Write registrieren - ABER
  // Gruppen ueberspringen, deren ')' direkt von '.'/'^'/'[' gefolgt wird: das
  // ist ein Cast-/Receiver-Operand (ein READ), kein var/out-Arg.
  // FN-SCHUTZ: 'PFoo(localVar)^.M()' -> Gruppe '(localVar)' von '^' gefolgt ->
  // uebersprungen -> localVar bleibt ein Read -> echter uninit-Bug bleibt Fund.
  var
    S          : string;
    GroupBody  : string;
    i, L, GroupStart, Depth, j : Integer;
    AfterClose : Char;
  begin
    S := StripCommentsAndStrings(CallName);   // Kat. D: ')' in Literalen raus
    L := Length(S);
    i := 1;
    while i <= L do
    begin
      if S[i] = '(' then
      begin
        GroupStart := i + 1;
        Depth := 1;
        Inc(i);
        while (i <= L) and (Depth > 0) do
        begin
          if S[i] = '(' then Inc(Depth)
          else if S[i] = ')' then
          begin
            Dec(Depth);
            if Depth = 0 then Break;
          end;
          Inc(i);
        end;
        // i steht auf dem schliessenden ')' (oder L+1 bei unbalanciert).
        j := i + 1;
        while (j <= L) and (S[j] = ' ') do Inc(j);
        AfterClose := #0;
        if j <= L then AfterClose := S[j];
        // Cast-/Receiver-Praefix ')^' / ').' / ')[' -> Operand ist ein Read,
        // NICHT als Write registrieren (FN-Schutz gegen Typecast-Operand-Reads).
        // ABER: hat die Gruppe ein Komma, ist es ein Multi-Arg-CALL (verkettet,
        // z.B. 'EnterLocal(log, self, x).Log(...)'), KEIN Typecast (der hat
        // genau EINEN Operanden) -> die var/out-Args doch registrieren.
        // Verify-Concern 2026-07-12: chained-call-Kante (sonst 8 neue mORMot-FPs);
        // Single-Operand-Casts 'PFoo(x)^' bleiben uebersprungen (FN-Schutz intakt).
        GroupBody := Copy(S, GroupStart, i - GroupStart);
        if (not CharInSet(AfterClose, ['.', '^', '['])) or (Pos(',', GroupBody) > 0) then
          RegisterArgVarsAsWrites(LowerCase(GroupBody), Line);
        Inc(i);
      end
      else
        Inc(i);
    end;
  end;

  procedure ProcessAssign(A: TAstNode);
  // B2 (Triage 2026-07-25): hinter RegisterCallArgWrites verschoben -
  // Hook 1 unten braucht die Prozedur (nested Procs kennen kein forward).
  var
    LhsBare : string;
    Idx     : Integer;
  begin
    if A = nil then Exit;
    // Phase 2.4: Hits aus nested-Methods ignorieren - die haben ihren
    // eigenen AnalyzeMethod-Aufruf, dort wird die Vars-Inventur korrekt
    // gemacht.
    if IsLineInRanges(A.Line, NestedRanges) then Exit;
    // B2 Hook 1 (Triage 2026-07-25): Call-LHS-Assign. Fuer
    // 'UpperCopy255Buf(Buf, X)^ := #0' legt der Parser den KOMPLETTEN
    // Call-Ausdruck als nkAssign.Name ab; ExtractBareIdent extrahiert nur
    // den Funktionsnamen -> die var/out-Args bekamen keinen pessimistic-
    // Write (mormot PropNameUpper, fcHigh-FP). RegisterCallArgWrites
    // reuse't den bestehenden Guard 'Klammergruppe+Komma' 1:1: Single-
    // Operand-Casts ('PInteger(p)^ :=') bleiben uebersprungen (FN-Schutz
    // fuer Cast-Operand-Reads intakt), Multi-Arg-Gruppen registrieren.
    // Nur zusaetzliche Write-Registrierung -> monoton, nie neue Funde.
    if Pos('(', A.Name) > 0 then
      RegisterCallArgWrites(A.Name, A.Line);
    LhsBare := ExtractBareIdent(A.Name);
    if LhsBare = '' then Exit;
    Idx := VarIndexFor(LowerCase(LhsBare));
    if Idx >= 0 then RegisterWrite(Idx, A.Line);
    // B2 Hook 7 (Triage 2026-07-25): Array-Decay-RHS auf ein Pointer-Feld.
    // 'BrowseInfo.pszDisplayName := NameBuffer' nimmt die ADRESSE des
    // statischen Char-Arrays (Decay OHNE '@'); der spaetere API-Call fuellt
    // den Buffer ueber den gespeicherten Pointer - fuer alle Write-Pfade
    // unsichtbar -> never-written-FP. Semantik identisch zum A3b-@-Scan:
    // Adressnahme = konservativer Write an der Decay-Zeile. PFLICHT-Gate
    // (Reviewer 2026-07-25): das Zielfeld-Segment MUSS mit 'psz'/'lpsz'/
    // 'lp' beginnen (Hungarian-Pointer-Konvention; 'lpsz' ist von 'lp'
    // abgedeckt) - OHNE Gate wuerde 'Obj.Name := Buf' (String-Property
    // LIEST den Buffer / Ganz-Array-Copy) echte Garbage-Reads maskieren.
    // Nur Write-Registrierung -> monoton.
    var RhsBare := Trim(A.TypeRef);
    if (RhsBare <> '') and (Pos('.', A.Name) > 0) then
    begin
      var IsBareIdent := True;
      for var ci := 1 to Length(RhsBare) do
        if not IsIdentChar(RhsBare[ci]) then
        begin
          IsBareIdent := False;
          Break;
        end;
      if IsBareIdent then
      begin
        var Idx2 := VarIndexFor(LowerCase(RhsBare));
        if Idx2 >= 0 then
        begin
          // Entspacter TypeLow: der Parser konkateniert Tokens mal mit,
          // mal ohne Spaces ('array [ 0 .. 259 ] of ansichar' vs.
          // 'array[0..259]ofansichar') - beide Formen abdecken.
          var TL := StringReplace(VarList.List[Idx2].TypeLow, ' ', '',
                                  [rfReplaceAll]);
          if TL.StartsWith('array[') and TL.EndsWith('char') then
          begin
            var SegP := LastDelimiter('.', A.Name);
            var Seg := LowerCase(Copy(A.Name, SegP + 1, MaxInt));
            if Seg.StartsWith('psz') or Seg.StartsWith('lp') then
              RegisterWrite(Idx2, A.Line);
          end;
        end;
      end;
    end;
  end;

  procedure ProcessCallsInExprText(const ExprRaw: string; Line: Integer);
  // Kernlogik (Real-World-FP-Audit 2026-07-12 faktorisiert aus
  // ProcessConditionCalls): alle Calls in einem Expression-String tokenisieren
  // und pro var/out-Arg pessimistic-Write registrieren (READ_ALLOWLIST-Calls
  // ausgenommen). Genutzt von ProcessConditionCalls (TypeRef-Strings),
  // ProcessCaseSelectorWrites (case-Selektor aus der Quelle), ProcessCall
  // (Statement-Wrapper) und dem PhaseC-Inline-const-Scan - deshalb VOR
  // ProcessCall deklariert (nested Procs kennen kein forward).
  //
  // Nested-procedure statt anonymous-method (greift auf Outer-Scope VarList
  // und RegisterWrite zu - anonymous procs koennen das nicht, siehe E2555).
  var
    Calls   : TList<TExprCall>;
    Call    : TExprCall;
    ArgsLow : string;
  begin
    if ExprRaw = '' then Exit;
    Calls := TList<TExprCall>.Create;
    try
      TDetectorUtils.ParseCallsInExpr(ExprRaw, Calls);
      for Call in Calls do
      begin
        // IsReadOnlyCall erwartet 'FuncName(...)' - wir bauen Stub.
        if IsReadOnlyCall(Call.FuncNameLow + '(') then
        begin
          // B Hook 2 (Triage 2026-07-25): 'W := Trim(GetWordOnPos2(S, X,
          // iBeg, iEnd))' - ParseCallsInExpr emittiert NUR den Outer-Call;
          // ein read-only Wrapper versteckte damit die var-Args des INNEREN
          // Nicht-Allowlist-Calls (jvcl JvEditor iBeg). In die Argliste
          // rekurrieren (terminiert: Argtext strikt kuerzer); die nackten
          // Idents des read-only Calls selbst bleiben Reads ('Trim(v)' /
          // 'WriteLn(u)' unveraendert Fund).
          if Pos('(', Call.ArgsRaw) > 0 then
            ProcessCallsInExprText(Call.ArgsRaw, Line);
          Continue;
        end;
        ArgsLow := LowerCase(Call.ArgsRaw);
        if ArgsLow = '' then Continue;
        // P2: Single-Pass-Tokenizer + Dict-Lookup statt O(N) Inner-Loop.
        RegisterArgVarsAsWrites(ArgsLow, Line);
      end;
    finally
      Calls.Free;
    end;
  end;

  procedure ProcessCall(C: TAstNode);
  var
    FuncName : string;
    DotPos   : Integer;
    Receiver : string;
    Method   : string;
  begin
    if C = nil then Exit;
    if IsLineInRanges(C.Line, NestedRanges) then Exit;
    // Drei-Klassen-Modell (Konzept §6):
    //   1. READ_ALLOWLIST  (WriteLn, Assigned, Length, ...) -> KEIN Write
    //      registrieren. Var-Arg ist ein Read, das spaeter ueber Source-
    //      Line-Scan erkannt wird.
    //   2. WRITE_ALLOWLIST (ReadLn, FillChar, ...) -> Write registrieren.
    //   3. UNKNOWN-Calls (Helper.Init, MyProc, ...) -> pessimistic-Write
    //      registrieren (akzeptiert FNs, reduziert FPs bei OOP-Code).
    if IsReadOnlyCall(C.Name) then
    begin
      // B Hook 2 symmetrisch: Statement-Wrapper 'WriteLn(GetX(v))' -
      // geschachtelte Nicht-Allowlist-Calls registrieren ihre pessimistic-
      // Writes trotzdem. Rekursion nur bei '(' IM Argtext; 'WriteLn(u)'
      // (Golden-Corpus-TP) bleibt reiner Read.
      var WrapP := Pos('(', C.Name);
      if WrapP > 0 then
      begin
        var InnerArgs := Copy(C.Name, WrapP + 1, MaxInt);
        if Pos('(', InnerArgs) > 0 then
          ProcessCallsInExprText(InnerArgs, C.Line);
      end;
      Exit;
    end;
    // Receiver-Init-Pattern: 'doc.InitJson(...)', 'rec.Init(...)' - der
    // Receiver wird durch die Methode INITIALISIERT (mORMot/Spring
    // record-Init-Convention). Pessimistic-Write fuer den Receiver
    // damit Folge-Reads nicht als UninitVar gemeldet werden.
    // Audit-Trigger: mORMot dmvc-ai 'doc: TDocVariantData' + 'doc.InitJson'.
    // C.Name hat Form 'doc.InitJson(data, JSON_FAST)' - direkt parsen,
    // ExtractCallFunctionName ist hier nutzlos weil's den qualifier abschneidet.
    FuncName := C.Name;
    var ParenPos := Pos('(', FuncName);
    if ParenPos > 0 then FuncName := Trim(Copy(FuncName, 1, ParenPos - 1));
    // Trailing-Punctuation/Args entfernen ('timer.Start;' / 'doc.Init data')
    var EndCut := Length(FuncName) + 1;
    for var i := 1 to Length(FuncName) do
      if not CharInSet(FuncName[i], ['A'..'Z','a'..'z','0'..'9','_','.']) then
      begin EndCut := i; Break; end;
    FuncName := Copy(FuncName, 1, EndCut - 1);
    DotPos := LastDelimiter('.', FuncName);
    if DotPos > 1 then
    begin
      Receiver := LowerCase(Trim(Copy(FuncName, 1, DotPos - 1)));
      Method   := LowerCase(Trim(Copy(FuncName, DotPos + 1, MaxInt)));
      // Receiver-Init: in-Unit-Record -> jeder Methodenaufruf initialisiert
      // (Self ist var-Parameter); sonst konservative Init-Verb-Allowlist.
      // KLASSEN bleiben ausgenommen (Aufruf auf uninit Klassen-Ref = echter
      // Read/Bug). Ausgelagert nach ApplyReceiverInit (auch im Expression-
      // Kontext genutzt, siehe ProcessReceiverInitInExpr).
      ApplyReceiverInit(Receiver, Method, C.Line);
    end;
    // Real-World-FP-Audit 2026-07-12: pessimistic-Write ueber ALLE Arg-Gruppen
    // (nicht nur die erste) - Receiver-/Cast-Praefixe uebersprungen (Kat. A+D).
    RegisterCallArgWrites(C.Name, C.Line);
  end;

  procedure ProcessConditionCalls(Node: TAstNode);
  // Phase 2.2 + 2.3: Calls innerhalb von Expression-tragenden Knoten
  // (nkIfStmt/nkWhileStmt/nkCaseStmt-Conditions, nkAssign/nkForStmt-RHS) legt
  // der Parser als TypeRef-String ab (nicht als nkCall). Delegiert an
  // ProcessCallsInExprText.
  begin
    if (Node = nil) or (Node.TypeRef = '') then Exit;
    if IsLineInRanges(Node.Line, NestedRanges) then Exit;
    ProcessCallsInExprText(Node.TypeRef, Node.Line);
  end;

  procedure ProcessCaseSelectorWrites(CaseNode: TAstNode);
  // Real-World-FP-Audit 2026-07-12, FP-Klasse 'var-param-out-write' (Kat. C,
  // dominant): 'case SomeCall(outVar) of' - der Selektor bekam keinen
  // pessimistic-Write -> FP. HISTORIE: urspruenglich verwarf der Parser den
  // case-Selektor komplett (SkipTo), daher dieser Quell-Fallback. SEIT der
  // Ist-Messung 2026-07-18 legt ParseCaseStmt den Selektor als Flachtext in
  // nkCaseStmt.TypeRef ab -> ProcessConditionCalls/ProcessReceiverInitInExpr
  // sehen ihn jetzt AUCH via AST. Dieser Quell-Pfad bleibt als redundante,
  // idempotente Absicherung bestehen (mehrzeilige Selektoren, Registrierung
  // auf derselben Zeile -> doppelt schadet nicht).
  var
    n, endLine, casePos, ofPos, dummy : Integer;
    accLow, sel : string;
  begin
    if (CaseNode = nil) or (Lines = nil) then Exit;
    if IsLineInRanges(CaseNode.Line, NestedRanges) then Exit;
    if (CaseNode.Line < 1) or (CaseNode.Line > Lines.Count) then Exit;
    accLow := '';
    n := CaseNode.Line;
    endLine := n + 4;
    if endLine > Lines.Count then endLine := Lines.Count;
    while n <= endLine do
    begin
      accLow := accLow + ' ' + LowerCase(StripCommentsAndStrings(Lines[n - 1]));
      if CountWholeWordOccurrences('of', accLow, dummy) > 0 then Break;
      Inc(n);
    end;
    if CountWholeWordOccurrences('case', accLow, casePos) = 0 then Exit;
    if CountWholeWordOccurrences('of', accLow, ofPos) = 0 then Exit;
    if ofPos <= casePos + 4 then Exit;      // 'of' muss NACH 'case <sel>' stehen
    // Selektor = Text zwischen dem 'case'-Wort und dem 'of'-Wort.
    sel := Copy(accLow, casePos + 4, ofPos - (casePos + 4));
    ProcessCallsInExprText(sel, CaseNode.Line);
  end;

  procedure ProcessReceiverInitInExpr(Node: TAstNode);
  // Receiver-Init fuer Calls in Expression-Strings (assign-RHS / conditions):
  // 'int := temp.Init(...)' schreibt temp. ProcessCall sieht solche Calls NICHT
  // (Parser legt sie als TypeRef-String ab, nicht als nkCall). Scannt
  // <receiver>.<method>( Muster (inkl. generic <...>) und wendet
  // ApplyReceiverInit an. Loest die dominante SCA166-FP-Klasse
  // 'record-method-init' (mORMot temp.Init / T.From... auf der RHS).
  var
    L : string;
    i, LL, ns, ne, rs : Integer;
    Receiver, Method : string;
  begin
    if (Node = nil) or (Node.TypeRef = '') then Exit;
    if IsLineInRanges(Node.Line, NestedRanges) then Exit;
    L := LowerCase(Node.TypeRef);
    LL := Length(L);
    i := 1;
    while i <= LL do
    begin
      if IsIdentChar(L[i]) and ((i = 1) or not IsIdentChar(L[i - 1])) then
      begin
        ns := i;
        while (i <= LL) and IsIdentChar(L[i]) do Inc(i);
        ne := i - 1;
        // optionale Spaces vor dem '.' ueberspringen: nkIfStmt/nkWhileStmt-
        // Conditions sind space-separiert ('reg . readopen ( ... )'), nur
        // nkAssign-RHS ist via JoinTokInto space-los ('temp.init(...)'). Ohne
        // diese Toleranz blieb Record-Init IN einer Bedingung ('if reg.ReadOpen')
        // unerkannt -> spaeterer statement-level Call wurde als First-Write
        // gewertet -> read-before-write-FP auf der Init-Zeile (mORMot reg/hasher).
        while (i <= LL) and (L[i] = ' ') do Inc(i);
        if (i <= LL) and (L[i] = '.') then
        begin
          Receiver := Copy(L, ns, ne - ns + 1);
          Inc(i);                                // hinter '.'
          while (i <= LL) and (L[i] = ' ') do Inc(i);   // Spaces nach '.'
          rs := i;
          while (i <= LL) and IsIdentChar(L[i]) do Inc(i);
          Method := Copy(L, rs, i - rs);
          // optionales generic '<...>' vor dem '(' ueberspringen (Lookahead j)
          var j : Integer := i;
          while (j <= LL) and (L[j] = ' ') do Inc(j);
          if (j <= LL) and (L[j] = '<') then
          begin
            var gd : Integer := 1;
            Inc(j);
            while (j <= LL) and (gd > 0) do
            begin
              if L[j] = '<' then Inc(gd) else if L[j] = '>' then Dec(gd);
              Inc(j);
            end;
            while (j <= LL) and (L[j] = ' ') do Inc(j);
          end;
          // nur ein Methoden-Call (mit '('), kein Feld-Zugriff 'rec.field'
          if (Method <> '') and (j <= LL) and (L[j] = '(') then
            ApplyReceiverInit(Receiver, Method, Node.Line)
          // Zensus-Triage 2026-07-25, Hook 1a: PARAMETERLOSER Record-Init
          // im Expression-Kontext. 'sz := tmp.Init shr 1' (mormot
          // TSynTempBuffer, Zensus mormot.lib.sspi:2211) initialisiert tmp
          // via Init-Methode OHNE Klammern - Self ist var-Parameter, der
          // Call FUELLT den Receiver. Die '('-Pflicht oben liess den Read
          // an dieser Zeile zaehlen, waehrend der pessimistic-Write erst
          // auf der Folgezeile lag -> read-before-write-FP. Parenlos ist
          // ein Member-Zugriff lexikalisch nicht von einem Feld-READ
          // unterscheidbar, deshalb GILT hier - anders als im '('-Zweig -
          // NUR die Init-Verb-Allowlist (dieselbe Vertrauensstufe wie das
          // bestehende cross-unit-Gate in ApplyReceiverInit). Restrisiko
          // eines FELDES namens init/done/reset/..., das gelesen wird:
          // bewusst akzeptiert (Gegenprobe ParenlessNonInitMemberRead_
          // StillFlagged sichert, dass normale Feld-Reads Fund bleiben).
          // Nur Write-Registrierung -> monoton, nie neue Funde.
          else if (Method <> '') and IsInitVerb(Method) then
          begin
            // Welle 1 (2026-07-25), Hook 3 (Review-Follow-up zu Hook 1a):
            // tkiClass-Gate spiegeln (Vorlage: with-Scan-Gate in PhaseC).
            // Ein parenloser Member-Zugriff wie 'b := c.Initialized' auf
            // einem KLASSEN-Receiver ist ein Property-/Feld-READ der
            // uninitialisierten Referenz - ihn als Init-Write zu werten
            // wuerde den echten Bug maskieren (im '('-Zweig unproblema-
            // tisch: dort entscheidet ApplyReceiverInit record-seitig).
            // Loest der Cross-Unit-TypeIndex den Receiver-Typ BEWEISBAR
            // als tkiClass auf -> KEIN Write, Fund bleibt. tkiUnknown/
            // tkiAlias/tkiRecord bzw. ohne Index (nil/leer, Tests/Single-
            // File) -> Verhalten wie bisher, die Hook-1a-Suppression fuer
            // Record-/Fremdtyp-Receiver bleibt erhalten (Gegenprobe
            // ParenlessInitRecordReceiver_NoFinding). Interfaces fuehrt
            // der Index ebenfalls als tkiClass - deren Locals sind aber
            // IsManaged und werden in PhaseD ohnehin nie gemeldet, das
            // Gate erzeugt dort also keinen neuen Fund.
            var IdxPl := VarIndexFor(Receiver);
            var TIpl  := CtxTypeIndex(AContext);
            if (IdxPl < 0) or (TIpl = nil) or TIpl.IsEmpty or
               (TIpl.TypeKindOf(BaseTypeLow(VarList.List[IdxPl].TypeLow))
                  <> tkiClass) then
              ApplyReceiverInit(Receiver, Method, Node.Line);
          end;
        end;
      end
      else
        Inc(i);
    end;
  end;

  procedure ProcessForStmt(F: TAstNode);
  var
    LoopBare : string;
    Idx : Integer;
    Child : TAstNode;
  begin
    if F = nil then Exit;
    if IsLineInRanges(F.Line, NestedRanges) then Exit;
    // Inline-var Form: 'for var x := ...' oder 'for var x in container do'.
    // Der Parser legt die LoopVar als nkLocalVar-Child an. Die LoopVar wird
    // implizit vom for/for-in-Iterator vor jedem Body-Durchlauf zugewiesen -
    // ohne RegisterWrite stuende die Var im Inventory ohne FirstWriteLine
    // und ein Read im Body wuerde als UninitVar gemeldet (FP, gemeldet als
    // LogStats_plugin MainForm.pas:352 'for var Pair in ADict do').
    for Child in F.Children do
      if Child.Kind = nkLocalVar then
      begin
        Idx := VarIndexFor(LowerCase(Child.Name));
        if Idx >= 0 then RegisterWrite(Idx, F.Line);
        Exit;
      end;

    // Klassische Form: TypeRef enthaelt 'i := 0 to 10' o.ae.
    // Loop-Var = erstes Token.
    LoopBare := ExtractForLoopVar(F.TypeRef);
    if LoopBare = '' then Exit;
    Idx := VarIndexFor(LowerCase(LoopBare));
    if Idx >= 0 then RegisterWrite(Idx, F.Line);
  end;

  function IsVarDeclLine(const LineLow: string): Boolean;
  // Heuristik: erkennt reine Var-Deklarationszeilen wie
  //   'sum: double;'
  //   's, sum: double;'
  //   'a, b, c: integer;'
  // ohne Init-Wert. Pattern: vor dem ersten ':' nur Ident-Chars/Komma/
  // Whitespace, ':' nicht direkt von '=' gefolgt (sonst ':=' Assignment),
  // endet mit ';'.
  //
  // Var-Decl MIT Init (':' Type = Wert;) zaehlt nicht als "reine Decl" -
  // wird via FirstWriteLine-Skip behandelt (gleiche Zeile wie Decl).
  var
    Trimmed : string;
    Cp, i, L : Integer;
    C : Char;
  begin
    Result := False;
    Trimmed := Trim(LineLow);
    L := Length(Trimmed);
    if L < 4 then Exit;
    if Trimmed[L] <> ';' then Exit;
    // Erste ':' suchen
    Cp := Pos(':', Trimmed);
    if (Cp = 0) or (Cp = L) then Exit;
    // ':=' = Assignment, KEINE Decl
    if Trimmed[Cp + 1] = '=' then Exit;
    // Vor dem ':' nur Ident-Chars, Komma, Whitespace
    for i := 1 to Cp - 1 do
    begin
      C := Trimmed[i];
      if not (CharInSet(C, ['a'..'z', '0'..'9', '_', ',', ' ', #9])) then
        Exit;
    end;
    // Nach dem ':' bis ';': Type (darf '=' enthalten falls Init, dann
    // ist's keine reine Decl).
    for i := Cp + 1 to L - 1 do
      if Trimmed[i] = '=' then Exit;
    Result := True;
  end;

  function IsVarDeclContinuationLine(const LineLow: string): Boolean;
  // Multi-Line-var-Decl-Kontinuation:
  //   var
  //     luminanceIndex,         <- diese Zeile
  //     index  : Integer;
  //     byte1,                  <- diese Zeile
  //     byte2,                  <- diese Zeile
  //     b5, g5, r5,             <- diese Zeile
  //     r8, g8, b8 : Byte;
  // Pattern: NUR Ident-Chars + Kommas + Whitespace, endet mit ','
  // (kein ':', kein '(', kein '=', kein ';'). IsVarDeclLine matched
  // nur die finale Zeile mit ':type;', diese Continuation-Zeilen
  // wuerde der Source-Line-Scan sonst als Identifier-Reads
  // interpretieren - 20 FPs allein in TCodeReader RGBLuminance.pas.
  //
  // Risk: koennte fold-falsch eine multi-line Call-Arg-Zeile wie
  //   X := Bar(
  //     Foo,          <- matched auch!
  //     Baz);
  // skippen, wenn Foo eine tracked Local-Var ist. In dem Fall hat aber
  // der AST-Call-Walk Foo bereits via pessimistic-Write registriert
  // (siehe ProcessCall) - kein False-Negative.
  var
    Trimmed : string;
    i, L : Integer;
    C : Char;
    HasIdent : Boolean;
  begin
    Result := False;
    Trimmed := Trim(LineLow);
    L := Length(Trimmed);
    if L < 2 then Exit;
    if Trimmed[L] <> ',' then Exit;
    HasIdent := False;
    for i := 1 to L do
    begin
      C := Trimmed[i];
      if not CharInSet(C, ['a'..'z', '0'..'9', '_', ',', ' ', #9]) then Exit;
      if CharInSet(C, ['a'..'z', '_']) then HasIdent := True;
    end;
    Result := HasIdent;
  end;

  procedure BuildStrippedLowCache(MethodStartLine, MethodEndLine: Integer);
  // Perf (2026-07-05): P7-uninitvar - EIN StripLineEx-Durchlauf ueber den
  // Methodenbereich [From0..To0], Ergebnis gelowert in StrippedLow.
  // FindFirstSourceWriteLine/FindFirstReadLine lesen nur noch aus dem
  // Array; beide starteten bisher identisch mit frischem StripState bei
  // MethodStartLine - das vorberechnete Array ist daher byte-identisch.
  // FP-Fix-Semantik bleibt erhalten: State (InBrace/InParen) laeuft ueber
  // alle Zeilen mit, damit Multi-Line-Block-Comments { ... \n ... } und
  // (* ... \n ... *) korrekt geclipped werden. Annahme wie bisher: bei
  // MethodStartLine ist kein Block-Comment offen.
  var
    i, From0, To0 : Integer;
    StripState : TLineStripState;
  begin
    StrippedLow   := nil;
    StrippedFrom0 := 0;
    if Lines = nil then Exit;
    if (MethodStartLine <= 0) or (MethodEndLine < MethodStartLine) then Exit;
    From0 := MethodStartLine - 1;
    To0   := MethodEndLine - 1;
    if From0 < 0 then From0 := 0;
    if To0 > Lines.Count - 1 then To0 := Lines.Count - 1;
    if To0 < From0 then Exit;
    StrippedFrom0 := From0;
    SetLength(StrippedLow, To0 - From0 + 1);
    StripState.InBrace := False;
    StripState.InParen := False;
    for i := From0 to To0 do
      StrippedLow[i - From0] := LowerCase(StripLineEx(Lines[i], StripState));
  end;

  function FindFirstSourceWriteLine(const NameLow: string;
    DeclLine, MethodStartLine, MethodEndLine: Integer): Integer;
  // FP-Fix Source-Line-Fallback fuer Write-Detection. Wird gerufen wenn
  // PhaseB_AstWalks keinen Write fuer eine Var hatte. Suche nach Pattern
  //   ^\s*NameLow\s*:=
  // (= reine Assignment, kein Qualifier wie .Field, [i], ^).
  // Hintergrund: bei Methoden mit nested-procs UND zweiter var-Section
  // (Headless-Method-Pattern im Parser) wird der Outer-MethodNode
  // umgebaut und der Outer-Body-Assign landet nicht im AST.
  var
    i, From0, To0 : Integer;
    L, Trimmed : string;
    TPos, NL : Integer;
  begin
    Result := 0;
    if Lines = nil then Exit;
    NL := Length(NameLow);
    if NL = 0 then Exit;
    if (MethodStartLine <= 0) or (MethodEndLine < MethodStartLine) then Exit;
    From0 := MethodStartLine - 1;
    To0   := MethodEndLine - 1;
    if From0 < 0 then From0 := 0;
    if To0 > Lines.Count - 1 then To0 := Lines.Count - 1;
    for i := From0 to To0 do
    begin
      // Perf (2026-07-05): P7-uninitvar - vorberechnetes StrippedLow-Array
      // (BuildStrippedLowCache, identische Bounds via PhaseC) statt
      // StripLineEx pro Variable.
      L := StrippedLow[i - StrippedFrom0];
      if i + 1 = DeclLine then Continue;
      if IsLineInRanges(i + 1, NestedRanges) then Continue;
      // Read-Family-Fill ('Stream.Read(Buf, Size)') fuellt den Buffer = Write.
      if LineFillsVarViaReadCall(L, NameLow) then Exit(i + 1);
      // Typecast-Assignment-Target 'TFoo(name) := ...' / 'TFoo<T>(name) := ...'
      // schreibt name; der '^name :='-Scan unten erfasst das nicht (name steht
      // nicht am Zeilenanfang). FP-Klasse 'typecast-assignment-target'.
      if LineWritesViaTypecastAssign(L, NameLow) then Exit(i + 1);
      Trimmed := TrimLeft(L);
      if Length(Trimmed) < NL + 2 then Continue;
      if not Trimmed.StartsWith(NameLow) then Continue;
      // Nach NameLow Wortgrenze (sonst koennte 'cands' in 'candsx' matchen)
      if IsIdentChar(Trimmed[NL + 1]) then Continue;
      // Optional Whitespace, dann ':='
      TPos := NL + 1;
      while (TPos <= Length(Trimmed)) and (Trimmed[TPos] = ' ') do Inc(TPos);
      if (TPos <= Length(Trimmed) - 1)
         and (Trimmed[TPos] = ':') and (Trimmed[TPos + 1] = '=') then
        Exit(i + 1);
    end;
  end;

  function LineContainsIdent(ALines: TStringList; LineNo: Integer;
    const NameLow: string): Boolean;
  // Sanity-Check: ist Name als Wort-Identifier in Line[LineNo-1] vorhanden?
  // Strippt nichts - reine Substring-Word-Boundary-Suche im Original.
  // Defensiver Last-Line-Check vor Finding-Emit (SCA166 Line-Attribution-
  // Audit 2026-06-07).
  var
    L : string;
    P, NL, LL : Integer;
    Before, After : Char;
  begin
    Result := False;
    if (ALines = nil) or (LineNo <= 0) or (LineNo > ALines.Count) then Exit;
    L := LowerCase(ALines[LineNo - 1]);
    LL := Length(L);
    NL := Length(NameLow);
    if NL = 0 then Exit;
    P := 1;
    while True do
    begin
      P := PosEx(NameLow, L, P);
      if P = 0 then Break;
      Before := #0;
      if P > 1 then Before := L[P - 1];
      After := #0;
      if P + NL - 1 < LL then After := L[P + NL];
      if not IsIdentChar(Before) and not IsIdentChar(After) then Exit(True);
      P := P + NL;
    end;
  end;

  function FindFirstReadLine(const NameLow: string;
    DeclLine, FirstWriteLine, MethodStartLine, MethodEndLine: Integer): Integer;
  // Findet die erste Source-Zeile MIT einem Identifier-Match INNERHALB
  // der Method-Boundary [MethodStartLine..MethodEndLine] die NICHT die
  // Var-Deklaration, NICHT die Write-Zeile UND NICHT innerhalb einer
  // nested-Method ist (Phase 2.4).
  //
  // Method-Boundary ist KRITISCH: ohne sie wuerde der Scan ueber die
  // ganze Unit laufen und ein Field-Decl im Interface mit gleichem
  // Namen als "Read" werten (Faktor 30x FP-Explosion in der Praxis).
  //
  // FP-Fix (doublecmd-Audit): Multi-line Var-Decls mit Komma-Auflistung
  // wie 's,\n  sum: Double;' werden vom Parser nur mit EINER DeclLine
  // gemeldet. Die Zeilen wo die nachfolgenden Idents stehen werden
  // sonst als Read interpretiert. IsVarDeclLine-Heuristik erkennt
  // reine Decl-Zeilen und skippt sie.
  var
    i : Integer;
    L : string;
    P, NL, LL, From0, To0 : Integer;
    Before, After : Char;
  begin
    Result := 0;
    if Lines = nil then Exit;
    NL := Length(NameLow);
    if NL = 0 then Exit;
    if (MethodStartLine <= 0) or (MethodEndLine < MethodStartLine) then Exit;
    From0 := MethodStartLine - 1;
    To0   := MethodEndLine - 1;
    if From0 < 0 then From0 := 0;
    if To0 > Lines.Count - 1 then To0 := Lines.Count - 1;
    for i := From0 to To0 do
    begin
      // Perf (2026-07-05): P7-uninitvar - vorberechnetes StrippedLow-Array
      // (BuildStrippedLowCache, identische Bounds via PhaseC) statt
      // StripLineEx pro Variable. Multi-Line-Comment-State ist dort
      // bereits ueber alle Zeilen mitgelaufen (FP-Fix-Semantik unveraendert).
      L := StrippedLow[i - StrippedFrom0];
      if (i + 1 = DeclLine) or (i + 1 = FirstWriteLine) then Continue;
      if IsLineInRanges(i + 1, NestedRanges) then Continue;
      // Skip wenn Zeile eine reine Var-Decl ist (Multi-line-Decl-Fix)
      if IsVarDeclLine(L) then Continue;
      // Skip auch Multi-Line-var-Decl-Continuation ('byte1,' / 'b5, g5,')
      if IsVarDeclContinuationLine(L) then Continue;
      // Skip Konstanten-Deklarationszeile ('szf=regcszd;'): FP-Klasse
      // 'conditional-compilation-const' - im inaktiven {$IFDEF}-Zweig wird der
      // Bezeichner als const deklariert, im anderen als var. Eine const-Decl
      // liest NIE eine lokale Variable (RHS = Compile-time-Konstante).
      if IsConstDeclLine(L) then Continue;
      // Read-Family-Fill-Zeile ('Stream.Read(Buf,...)'): Buffer wird hier
      // GESCHRIEBEN, nicht gelesen -> nicht als Read werten.
      if LineFillsVarViaReadCall(L, NameLow) then Continue;
      LL := Length(L);
      P := 1;
      while True do
      begin
        P := PosEx(NameLow, L, P);
        if P = 0 then Break;
        Before := #0;
        if P > 1 then Before := L[P - 1];
        After := #0;
        if P + NL - 1 < LL then After := L[P + NL];
        if not IsIdentChar(Before) and not IsIdentChar(After) then
        begin
          // Real-World-Sweep 2026-06-13 iter 7: '<obj>.<NameLow>' ist
          // Field-/Property-Access am Objekt, nicht die lokale Variable.
          // Trigger: pyscripter frmProjectExplorer `Data.ProjectNode` als
          // ProjectNode-Read interpretiert (FP). Skippen wenn vorheriges
          // Char ein '.' war.
          if Before <> '.' then
          begin
            // Real-World-FP 2026-06-23: folgende Formen sind KEIN Werte-Read:
            // 1) `@name` (Address-of, oft WinAPI-out-Param der name FUELLT).
            if Before = '@' then begin P := P + NL; Continue; end;
            // 1b) `$F` / `$A`.. (Hex-Literal): ein '$' direkt davor macht das
            //     Match zu einer Hex-Ziffernfolge, nicht zum Lesen einer
            //     gleichnamigen Ein-Buchstaben-Var A..F (Recharakterisierung
            //     after30 2026-07-12, DCU32/op.pas 'D := B1 and $F;'). Bezeichner
            //     koennen nie mit '$' beginnen -> TP-sicher.
            if Before = '$' then begin P := P + NL; Continue; end;
            // 2) low(name)/high(name)/sizeof(name)/typeinfo(name): Compile-time-
            //    bzw. Typ-Query, KEIN Werte-Read (FP-Klasse 'low-high-not-read').
            if PrecededByIntrinsicOpen(L, P) then
              begin P := P + NL; Continue; end;
            // 3) Array-Element-Write `name[i] := ` / `name[i].F := ` ist
            //    Initialisierung (Element-Write), kein Read.
            if After = '[' then
            begin
              var q := P + NL; var depth := 0;
              while q <= LL do
              begin
                if L[q] = '[' then Inc(depth)
                else if L[q] = ']' then
                begin Dec(depth); if depth = 0 then begin Inc(q); Break; end; end;
                Inc(q);
              end;
              // '&' im Charset: escaped-keyword-Felder ('name[0].&Type := ...')
              // sind Element-Writes, kein Read. Ohne '&' bricht der Qualifier-
              // Walk an '&Type' ab und der Write wird als Read fehlgedeutet
              // (FP-Klasse Real-World 2026-06-28, Alcinoe.ServiceUtils SC_ACTION).
              while (q <= LL) and CharInSet(L[q], ['.', '_', '&', 'a'..'z', '0'..'9']) do Inc(q);
              while (q <= LL) and (L[q] = ' ') do Inc(q);
              if (q < LL) and (L[q] = ':') and (L[q + 1] = '=') then
                begin P := P + NL; Continue; end;
            end;
            // 3b) Member-Access-Write `name.field := ` / `name.a.b := ` /
            //     `name.f[i] := ` ist ein (partieller) WRITE von name, kein Read
            //     (FP-Klasse 'field-assignment-target', Real-World InlineOp.pas:2710).
            //     Ein vorangehendes Label kann den AST-nkAssign-Write dieser Zeile
            //     verschlucken; der Source-Read-Scan wertete `name.field :=` dann als
            //     Read und die naechste `name.other :=`-Zeile als Write -> read-before-
            //     write-FP. Qualifier-Kette (Punkte, escaped '&', balancierte '[...]')
            //     bis zum '=' des ':=' ueberspringen.
            if After = '.' then
            begin
              var q := P + NL;
              while q <= LL do
              begin
                if L[q] = '[' then
                begin
                  var depth := 0;
                  while q <= LL do
                  begin
                    if L[q] = '[' then Inc(depth)
                    else if L[q] = ']' then
                    begin Dec(depth); if depth = 0 then begin Inc(q); Break; end; end;
                    Inc(q);
                  end;
                end
                else if CharInSet(L[q], ['.', '_', '&', 'a'..'z', '0'..'9']) then
                  Inc(q)
                else
                  Break;
              end;
              while (q <= LL) and (L[q] = ' ') do Inc(q);
              if (q < LL) and (L[q] = ':') and (L[q + 1] = '=') then
                begin P := P + NL; Continue; end;
            end;
            // 4) `with name do ...`: Feld-Zugriff/-Write am Record, kein
            //    plain Read der Var (name steht vor dem ` do `).
            if StartsStr('with ', TrimLeft(L)) and
               ((Pos(' do', L) = 0) or (P < Pos(' do', L))) then
              begin P := P + NL; Continue; end;
            Exit(i + 1);
          end;
        end;
        P := P + NL;
      end;
    end;
  end;

  function CalcMethodEndLine(Node: TAstNode): Integer;
  // Method-Body-Ende = max(Line) ueber alle Descendants. Iterativer
  // Walk, Stack-safe auch fuer tiefe ASTs.
  var
    Stack : TStack<TAstNode>;
    Cur   : TAstNode;
    i     : Integer;
  begin
    Result := 0;
    if Node = nil then Exit;
    Result := Node.Line;
    Stack := TStack<TAstNode>.Create;
    try
      Stack.Push(Node);
      while Stack.Count > 0 do
      begin
        Cur := Stack.Pop;
        if Cur.Line > Result then Result := Cur.Line;
        for i := 0 to Cur.Children.Count - 1 do
          Stack.Push(Cur.Children[i]);
      end;
    finally
      Stack.Free;
    end;
  end;

  procedure PhaseA_VarInventur;
  // Aus FindAll(nkLocalVar) die Var-Inventur aufbauen + Skip-Regeln
  // anwenden (underscore-Prefix, Parser-Artefakt, Duplikate).
  var
    LV : TAstNode;
    VarRec : TVarInfo;
  begin
    for LV in LocalVars do
    begin
      if Trim(LV.Name) = '' then Continue;
      if LV.Name.StartsWith('_') then Continue;
      if not LooksLikeRealLocalVar(Lines, LV.Line) then Continue;
      // SCA166-Scope: Parser-Artefakt-Phantoms (nested-Proc-Param / Function-
      // Pointer-Typ-Var / Feld-`if X=nil`) tragen '(' ')' '=' im TypeRef -
      // nie ein echter uninit-Local. TP-sicher (AST-Dump-verifiziert 2026-07-14).
      if IsParserArtifactTypeRef(LV.TypeRef) then Continue;
      // B2 Hook 3+4 (Triage 2026-07-25): zwei weitere Inventur-Phantom-
      // Klassen, beide auf der GESTRIPPTEN Decl-Zeile erkannt (Kommentare
      // zaehlen nie; stateless Strip reicht, Decl-Zeilen liegen nie in
      // einem Multi-Line-Block-Kommentar - der Parser hat sie gesehen).
      if (Lines <> nil) and (LV.Line >= 1) and (LV.Line <= Lines.Count) then
      begin
        var DeclLow := LowerCase(StripCommentsAndStrings(Lines[LV.Line - 1]));
        // Hook 3: lokale resourcestring-/const-Eintraege. 'resourcestring'
        // ist KEIN Lexer-Keyword -> ab dem zweiten Eintrag wird jede Zeile
        // 'SUnknown = ''...'';' als Var-Decl geparst (TypeRef leer, kein
        // ')'/'='). Eine Zeile der Form 'ident = wert;' bzw. 'ident: typ =
        // wert;' ist nie eine ECHTE var-Decl, sondern const/resourcestring
        // (bzw. FPC-initialisiert -> ohnehin kein uninit-Read moeglich).
        // Restrisiko {$IFDEF}-Twin (aktiver Zweig 'var X: T', inaktiver
        // 'const X = w', nkLocalVar am const-Zweig verankert): der echte
        // var-Zweig wuerde mit-suppressed - dieselbe Richtung ist fuer die
        // Read-Seite bereits als TP-sicher eingestuft (FP-Klasse
        // 'conditional-compilation-const', s. FindFirstReadLine).
        if IsConstDeclLine(DeclLow) then Continue;
        // Hook 4: param-misparse (Signatur-/proc-Typ-Parameter als Locals),
        // s. IsParamMisparseDeclLine.
        if IsParamMisparseDeclLine(DeclLow, LowerCase(LV.Name)) then Continue;
        // Zensus-Triage 2026-07-25, H2: Inline-const-Ident. 'const X =
        // expr;' im BODY deklariert eine KONSTANTE - X ist ab der Decl
        // immer initialisiert, ein uninit-Read ist kategorisch unmoeglich.
        // Der PhaseC-const-Scan (Inkrement B) registriert bereits die
        // var/out-Writes der RHS-Args - hier geht es um X SELBST, falls
        // der Parser es als nkLocalVar einsammelt (die 'const X ='-Zeile
        // matcht IsConstDeclLine oben NICHT, weil 'const' selbst als
        // fuehrender Ident gelesen wird). Namens-Gate: der Ident direkt
        // hinter 'const' muss der Var-Name sein - 'const c = 1; var x'
        // auf einer Zeile suppresst x nicht mit.
        var DeclT := TrimLeft(DeclLow);
        if DeclT.StartsWith('const ') then
        begin
          var cp := 7;
          while (cp <= Length(DeclT)) and (DeclT[cp] = ' ') do Inc(cp);
          var ce := cp;
          while (ce <= Length(DeclT)) and IsIdentChar(DeclT[ce]) do Inc(ce);
          if Copy(DeclT, cp, ce - cp) = LowerCase(LV.Name) then Continue;
        end;
        // Zensus-Triage 2026-07-25, H3: FPC-'{%H-}'-Marker adjazent zum
        // Var-Namen auf der ROHEN Decl-Zeile = explizite Autor-Suppression
        // (Begruendung + Kommentar-Ausnahme s. HasAdjacentFpcHideMarker).
        if HasAdjacentFpcHideMarker(Lines[LV.Line - 1], LowerCase(LV.Name)) then
          Continue;
      end;
      // 'absolute'-Aliase ueberspringen: 'c1: TARGB absolute color1;' macht
      // c1 zum Alias der bestehenden Variable color1 - eigene Storage gibt
      // es nicht, daher auch keine 'init'-Pflicht. Audit-Trigger Img32.Extra
      // BlendAverage/AlphaAverage und mORMot crypt.ecc 'absolute Result'.
      if Pos('absolute', LowerCase(LV.TypeRef)) > 0 then
      begin
        // A3: Ziel-Ident hinter 'absolute' merken, damit Writes UEBER den
        // Alias dem Ziel zugerechnet werden (VarIndexFor-Fallback).
        var TR0 := LowerCase(LV.TypeRef);
        var pAbs := Pos('absolute', TR0) + Length('absolute');
        while (pAbs <= Length(TR0)) and (TR0[pAbs] = ' ') do Inc(pAbs);
        var eAbs := pAbs;
        while (eAbs <= Length(TR0)) and IsIdentChar(TR0[eAbs]) do Inc(eAbs);
        if eAbs > pAbs then
          AbsAliases.AddOrSetValue(LowerCase(LV.Name),
                                   Copy(TR0, pAbs, eAbs - pAbs));
        Continue;
      end;
      // Auto-init-Record-Typen (TRttiContext u.a.): bare-Verwendung ist das
      // Standard-RTTI-Idiom, niemals explizit zugewiesen -> read-without-write
      // ist kein Bug. Aus der Inventur entfernen (Real-World 2026-06-28).
      if IsNoInitRecordType(LV.TypeRef) then Continue;
      VarRec.Name           := LV.Name;
      VarRec.NameLow        := LowerCase(LV.Name);
      VarRec.TypeLow        := LowerCase(LV.TypeRef);
      VarRec.DeclLine       := LV.Line;
      VarRec.FirstWriteLine := 0;
      VarRec.FirstReadLine  := 0;
      VarRec.RefCount       := 0;
      VarRec.IsManaged      := IsManagedType(LV.TypeRef, AContext);
      // Welle 1 (2026-07-25), Hook 1 managed-autoinit: strukturell dekla-
      // riertes dynamisches Array 'array of T' ist compiler-initialisiert
      // (auto-nil) -> managed. Beweis kommt aus der Decl-QUELLZEILE, weil
      // der Token-konkatenierte TypeRef ('arrayofbyte') homonym-ambig zu
      // einem Namenstyp 'ArrayOfByte' waere - s. IsDynArrayDeclLine.
      if not VarRec.IsManaged then
        VarRec.IsManaged := IsDynArrayDeclLine(Lines, LV.Line,
                                               VarRec.NameLow, VarRec.TypeLow);
      // Duplikate (same name in nested-scope - selten, defensive skip)
      if VarMap.ContainsKey(VarRec.NameLow) then Continue;
      VarMap.Add(VarRec.NameLow, VarList.Count);
      VarList.Add(VarRec);
    end;
  end;

  procedure PhaseB_AstWalks;
  // P1: Single-Pass DFS - 1x walken, 6 Buckets gleichzeitig fuellen.
  // Vorher: 8x MethodNode.FindAll mit jeweils komplettem Tree-Walk.
  //
  // Phase B (Writes aus nkAssign/nkCall/nkForStmt) + Phase 2.2+2.3
  // (Calls innerhalb if/while/case/assign-RHS/for-Range TypeRef-
  // Strings, via ParseCallsInExpr + pessimistic-Write).
  var
    Ifs, Whiles, Cases : TList<TAstNode>;
    i : Integer;
  begin
    Assigns := TList<TAstNode>.Create;
    Calls   := TList<TAstNode>.Create;
    Fors    := TList<TAstNode>.Create;
    Ifs     := TList<TAstNode>.Create;
    Whiles  := TList<TAstNode>.Create;
    Cases   := TList<TAstNode>.Create;
    try
      SinglePassCollectByKind(MethodNode, Assigns, Calls, Fors,
                              Ifs, Whiles, Cases);
      // Phase B - direkter Write aus AST-Knoten
      for i := 0 to Assigns.Count - 1 do ProcessAssign(Assigns[i]);
      for i := 0 to Calls.Count   - 1 do ProcessCall(Calls[i]);
      for i := 0 to Fors.Count    - 1 do ProcessForStmt(Fors[i]);
      // Phase 2.2+2.3 - Calls in TypeRef-Strings
      for i := 0 to Ifs.Count     - 1 do ProcessConditionCalls(Ifs[i]);
      for i := 0 to Whiles.Count  - 1 do ProcessConditionCalls(Whiles[i]);
      for i := 0 to Cases.Count   - 1 do ProcessConditionCalls(Cases[i]);
      // Kat. C (var-param-out-write): case-Selektor zusaetzlich aus der Quelle.
      // Seit 2026-07-18 fuellt der Parser nkCaseStmt.TypeRef (ProcessCondition-
      // Calls oben sieht den Selektor jetzt auch) - dieser Quell-Pfad bleibt
      // als idempotente Absicherung (mehrzeilige Selektoren).
      for i := 0 to Cases.Count   - 1 do ProcessCaseSelectorWrites(Cases[i]);
      for i := 0 to Assigns.Count - 1 do ProcessConditionCalls(Assigns[i]);
      for i := 0 to Fors.Count    - 1 do ProcessConditionCalls(Fors[i]);
      // A3 (Triage 2026-07-24, Call-Fill-Klasse): 'Exit(TryStrToX(S, v))'
      // legt der Parser als nkExit mit Arg-Text in TypeRef ab - KEINER
      // der Expression-Pfade sah das bisher -> v galt als never-written
      // (MinimalAPI lInt64/lFloat/lDate). Gleicher pessimistic-Write-Weg
      // wie if/while/case/assign-RHS.
      var Exits := MethodNode.FindAllRef(nkExit);
      for i := 0 to Exits.Count - 1 do ProcessConditionCalls(Exits[i]);
      // Receiver-Init fuer Calls in Expression-Strings (assign-RHS/conditions):
      // 'int := temp.Init(...)' schreibt temp - ProcessCall (nkCall) sieht das
      // nicht, weil solche Calls als TypeRef-String abgelegt sind.
      for i := 0 to Assigns.Count - 1 do ProcessReceiverInitInExpr(Assigns[i]);
      for i := 0 to Fors.Count    - 1 do ProcessReceiverInitInExpr(Fors[i]);
      for i := 0 to Ifs.Count     - 1 do ProcessReceiverInitInExpr(Ifs[i]);
      for i := 0 to Whiles.Count  - 1 do ProcessReceiverInitInExpr(Whiles[i]);
      for i := 0 to Cases.Count   - 1 do ProcessReceiverInitInExpr(Cases[i]);
    finally
      Cases.Free;
      Whiles.Free;
      Ifs.Free;
      Fors.Free;
      Calls.Free;
      Assigns.Free;
    end;
  end;

  procedure PhaseC_BodyTokenAndReads;
  // BodyToken-Sammlung fuer RefCount + Source-Line-Scan fuer FirstRead.
  // Method-Boundary [Start..End] limitiert den Scan - sonst matcht
  // Field-Decl im Interface mit gleichem Namen (FP-Faktor ~30x).
  var
    MethodStartLine, MethodEndLine, FirstMatchPos, i : Integer;
    P : PVarInfo;
  begin
    CollectBodyTokens(MethodNode, BodySB);
    BodyLow := LowerCase(BodySB.ToString);
    MethodStartLine := MethodNode.Line;
    // Perf (2026-07-05): P7-uninitvar - Method-End aus dem Orchestrator
    // durchgereicht statt zweitem CalcMethodEndLine-AST-Walk.
    MethodEndLine   := MethodEndL;
    for i := 0 to VarList.Count - 1 do
    begin
      P := @VarList.List[i];
      P.RefCount := CountWholeWordOccurrences(P.NameLow, BodyLow,
                                              FirstMatchPos);
      // RefCount<=1 -> nur Deklaration = UnusedLocal-Domain (SCA019).
      if P.RefCount <= 1 then Continue;
      // Perf (2026-07-05): P7-uninitvar - Stripped-Cache lazy bauen: nur
      // wenn mindestens eine Variable die Finder wirklich erreicht
      // (RefCount>1). Bounds identisch zu den Finder-Aufrufen darunter.
      if not StrippedBuilt then
      begin
        BuildStrippedLowCache(MethodStartLine, MethodEndLine);
        StrippedBuilt := True;
        // B Hook 1 (Triage 2026-07-25, dominante Sub-Klasse 4/5): Inline-
        // const-Initializer 'const Ok = ReadPE(F, OptHeader64, ...);' hat
        // der Parser verschluckt (kein tkKwConst-Arm; SkipToSemicolon frisst
        // die RHS restlos) -> die var/out-Args bekamen NIE den pessimistic-
        // Write, der Ident auf der const-Zeile zaehlte aber als Read ->
        // fcHigh-FP (issrc OptHeader64/VersionHandle/FindData). Source-
        // seitig nachziehen: RHS jeder const-Zeile durch das bestehende
        // 3-Klassen-Modell (ProcessCallsInExprText inkl. READ_ALLOWLIST-
        // Skip). Registriert ausschliesslich Writes -> monoton. Klassische
        // const-SEKTIONS-Zeilen matchen mit: deren Arg-Idents sind Compile-
        // time-Konstanten, VarIndexFor=-1 -> No-Op.
        for var cli := 0 to High(StrippedLow) do
        begin
          var CLine := StrippedLow[cli].TrimLeft;
          if CLine.StartsWith('const ') and (Pos(':=', CLine) = 0)
             and (Pos('(', CLine) > 0) then
          begin
            var CSrcLine := StrippedFrom0 + cli + 1;
            if IsLineInRanges(CSrcLine, NestedRanges) then Continue;
            var EqP := Pos('=', CLine);
            if EqP > 0 then
              ProcessCallsInExprText(Copy(CLine, EqP + 1, MaxInt), CSrcLine);
          end;
        end;
      end;
      // FirstWrite = fruehester ECHTER Write. Den Source-Scan IMMER laufen
      // lassen (nicht nur bei FirstWriteLine=0):
      //   * AST-Walks koennen den Outer-Body-Assign missen (Parser-Headless-
      //     Pattern) -> Fallback fuer FirstWriteLine=0.
      //   * Ein Read-Family-Fill ('Stream.Read(Buf,..)') bzw. 'name :=' kann
      //     FRUEHER liegen als ein vom AST registrierter Pessimistic-Arg-Write
      //     (SetLength(buf, lenVar) / Dec(n)), der sonst den echten Buffer-Fill
      //     maskiert und den Befund nur VERSCHIEBT statt ihn aufzuloesen
      //     (Real-World 2026-06-28: Abbrevia/SynEdit relocated FPs).
      // Frueher-Write-gewinnt ist monoton sicher: kann Befunde nur aufloesen,
      // nie neue erzeugen - ein Read VOR dem fruehen Write bleibt
      // < FirstWriteLine und wird weiterhin gemeldet.
      var SrcWrite := FindFirstSourceWriteLine(P.NameLow, P.DeclLine,
                                               MethodStartLine, MethodEndLine);
      if (SrcWrite > 0)
         and ((P.FirstWriteLine = 0) or (SrcWrite < P.FirstWriteLine)) then
        P.FirstWriteLine := SrcWrite;
      // #6 Inkr.4: der Source-Write ist eine Def-Site fuer den CFG-
      // Postfilter - unabhaengig davon, ob er das Minimum unterbietet.
      if (SrcWrite > 0) and (Length(P.WriteLines) < 64) then
        P.WriteLines := P.WriteLines + [SrcWrite];
      // A3b (Triage-Klasse @-Adressnahme, nachgezogen wegen Kategorien-
      // Verschiebung im A/B): ein Vorkommen von @varname im Methodenkoerper
      // bedeutet, dass die Variable ueber einen Pointer gefuellt werden kann
      // (LMsg.msg_name := @LAddr; RecvMsg fuellt) - konservativ als Write an
      // der @-Zeile werten (FN-tolerant, spiegelt Compiler-Verhalten; ein
      // reiner @-Leser ohne jeden Fill ist eine akzeptierte FN-Klasse).
      // Zensus-Triage 2026-07-25, H4: dieser Scan deckt auch das
      // GetProcAddress-Idiom '@X := GetProcAddress(...)' ab (LHS-
      // Adressnahme = Write auf X an der Zeile; der Read-Scan skippt
      // '@'-Vorkommen ohnehin) - kein eigener Hook noetig, per Tests
      // GetProcAddressAtLhs_NoFinding / ReadBeforeAtLhsAssign_StillFlagged
      // abgesichert.
      if StrippedBuilt then
      begin
        // A3b-Fix: auch @<alias> zaehlt fuers ZIEL (Indy: LMsg.msg_name
        // := AT-LAddr fuellt LAddrStore ueber den absolute-Alias).
        var AtPats := TStringList.Create;
        try
        AtPats.Add(chr(64) + P.NameLow);
        for var AliasPair in AbsAliases do
          if AliasPair.Value = P.NameLow then
            AtPats.Add(chr(64) + AliasPair.Key);
        for var api := 0 to AtPats.Count - 1 do
        begin
        var AtPat := AtPats[api];
        for var li := 0 to High(StrippedLow) do
        begin
          var ap := Pos(AtPat, StrippedLow[li]);
          if (ap > 0) and
             ((ap + Length(AtPat) > Length(StrippedLow[li])) or
              not IsIdentChar(StrippedLow[li][ap + Length(AtPat)])) then
          begin
            var AtLine := StrippedFrom0 + li + 1;
            if (P.FirstWriteLine = 0) or (AtLine < P.FirstWriteLine) then
              P.FirstWriteLine := AtLine;
            if Length(P.WriteLines) < 64 then
              P.WriteLines := P.WriteLines + [AtLine];
            Break;
          end;
        end;
        end;
        finally
          AtPats.Free;
        end;
      end;
      // B2 Hook 6 (Triage 2026-07-25): 'with <var> do' als konservativer
      // Write an der with-Zeile. Der with-Body fuellt Felder der Basis
      // ('with rec do begin Left := 0; ... end'), die Feld-Writes sind der
      // Basis aber nicht zuordenbar -> never-written-FP. Analog @-Scan:
      // FN-Toleranz fuer reine read-only-withs bewusst akzeptiert (ein
      // with, das nur liest, gilt faelschlich als Write - dieselbe dort
      // dokumentierte, akzeptierte Klasse). NUR single-target und wort-
      // gebunden: 'with a, b do' und 'with a.b do' matchen NICHT (nach dem
      // Namen darf bis 'do' nur Whitespace stehen). KLASSEN-Gate: loest
      // der Cross-Unit-TypeIndex den Typ als tkiClass auf, ist 'with obj
      // do' der echte Deref einer uninitialisierten Referenz -> KEIN
      // Write, Fund bleibt. Ohne TypeIndex (nil/leer: Single-File/Tests)
      // greift der Write fuer ALLE Typen - Begruendung: die with-FP-Klasse
      // ist record-/API-Struct-dominiert, die with-Zeile selbst war im
      // Read-Scan schon immer uebersprungen (Regel 4), und ohne Index ist
      // die Klassen-Eigenschaft nicht beweisbar - dieselbe Vertrauensstufe
      // wie beim @-Scan. Nur Write-Registrierung -> monoton.
      if StrippedBuilt then
      begin
        var TIw := CtxTypeIndex(AContext);
        if (TIw = nil) or TIw.IsEmpty or
           (TIw.TypeKindOf(BaseTypeLow(P.TypeLow)) <> tkiClass) then
        begin
          for var wli := 0 to High(StrippedLow) do
          begin
            var WT := TrimLeft(StrippedLow[wli]);
            if not WT.StartsWith('with ') then Continue;
            var wp := 6;
            while (wp <= Length(WT)) and (WT[wp] = ' ') do Inc(wp);
            if Copy(WT, wp, Length(P.NameLow)) <> P.NameLow then Continue;
            var wq := wp + Length(P.NameLow);
            if (wq <= Length(WT)) and IsIdentChar(WT[wq]) then Continue;
            while (wq <= Length(WT)) and (WT[wq] = ' ') do Inc(wq);
            if Copy(WT, wq, 2) <> 'do' then Continue;
            if (wq + 2 <= Length(WT)) and IsIdentChar(WT[wq + 2]) then Continue;
            var WithLine := StrippedFrom0 + wli + 1;
            if (P.FirstWriteLine = 0) or (WithLine < P.FirstWriteLine) then
              P.FirstWriteLine := WithLine;
            if Length(P.WriteLines) < 64 then
              P.WriteLines := P.WriteLines + [WithLine];
            Break;
          end;
        end;
      end;
      // Zensus-Triage 2026-07-25, Hook 1b: Same-File-Signatur-Aufloesung.
      // Steht die Variable BARE an einer Arg-Position eines unqualifizierten
      // Calls, dessen Formalparameter in ALLEN gleichnamigen Signaturen des
      // Files var/out ist, FUELLT der Call die Variable -> Write an der
      // Call-Zeile. Greift genau dort, wo der AST-Call-Pfad fehlt (Headless-
      // Pattern, repeat/until) - liegt der Call im AST, hat der pessimistic-
      // Write laengst registriert (Doppel-Registrierung ist idempotent).
      // VarMap als Shadow-Gate: 'CB(1, 2)' auf eine getrackte proc-Pointer-
      // Local loest NICHT auf (der Call geht an die Variable - ihr Read
      // bleibt Fund, s. ProcPointerVarReadBeforeWrite_StillFlagged).
      // Nur Write-Registrierung -> monoton, nie neue Funde.
      if StrippedBuilt and (ASigVarOut <> nil) and (ASigVarOut.Count > 0) then
      begin
        for var svi := 0 to High(StrippedLow) do
        begin
          if Pos(P.NameLow, StrippedLow[svi]) = 0 then Continue;
          var SvLine := StrippedFrom0 + svi + 1;
          if IsLineInRanges(SvLine, NestedRanges) then Continue;
          if LineHasVarOutArgWriteFor(StrippedLow[svi], P.NameLow,
                                      ASigVarOut, VarMap) then
          begin
            if (P.FirstWriteLine = 0) or (SvLine < P.FirstWriteLine) then
              P.FirstWriteLine := SvLine;
            if Length(P.WriteLines) < 64 then
              P.WriteLines := P.WriteLines + [SvLine];
            Break;
          end;
        end;
      end;
      P.FirstReadLine := FindFirstReadLine(P.NameLow, P.DeclLine,
                                           P.FirstWriteLine,
                                           MethodStartLine, MethodEndLine);
    end;
  end;

  function CfgBlockForLine(ALine: Integer): TCFGBlock;
  // #6 Inkr.4: Zeile -> CFG-Block (SCA134-Rezept FindBlockForLine): erster
  // Block, dessen AstNodes die Zeile tragen; Fallback Block.Line. nil wenn
  // nicht mappbar - der Read-Anker kann eine reine Source-Zeile aus dem
  // Raw-Rescan sein (Headless-Pattern), dort versagt auch das Mapping ->
  // der Aufrufer droppt dann NICHT (monoton).
  var
    B : TCFGBlock;
    N : TAstNode;
  begin
    Result := nil;
    if (MethodCfg = nil) or (ALine <= 0) then Exit;
    for B in MethodCfg.Blocks do
      for N in B.AstNodes do
        if N.Line = ALine then Exit(B);
    for B in MethodCfg.Blocks do
      if B.Line = ALine then Exit(B);
  end;

  function BodyHasGotoOrLabel: Boolean;
  // #6 Inkr.4: goto/label sind im CFG nicht modelliert (Sprungziele nur als
  // nkLabelMark am Unit-Node) - der Postfilter ist dann komplett inaktiv.
  // Scan auf dem gestrippten Zeilencache aus PhaseC.
  // Hinweis (CLI-verifiziert 2026-07-24): label-Methoden erzeugen aktuell
  // ohnehin keine fcMedium-Funde (label-Sektion stoert die lexikalische
  // Pipeline) - dieser Guard ist reine Defense-in-Depth fuer den Fall, dass
  // sich das aendert. Deshalb existiert kein End-to-End-Test dafuer.
  var
    i, p : Integer;
    L    : string;
  begin
    Result := False;
    if not StrippedBuilt then Exit(True);   // kein Cache -> konservativ inaktiv
    for i := 0 to High(StrippedLow) do
    begin
      L := StrippedLow[i];
      if L = '' then Continue;
      if L.StartsWith('label ') or (L = 'label') then Exit(True);
      p := Pos('goto', L);
      if (p > 0) and
         ((p = 1) or not IsIdentChar(L[p - 1])) and
         ((p + 4 > Length(L)) or not IsIdentChar(L[p + 4])) then Exit(True);
    end;
  end;

  function HasDeclInitializer(const AInfo: TVarInfo): Boolean;
  // #6 Inkr.4b: FPC-Deklarations-Initializer ('StartPos: Integer = 1;') -
  // laeuft bei JEDEM Routineneintritt, dominiert also jeden Read. Der
  // AST-/Source-Write-Scan sieht ihn nicht (kein ':='), aber er war laut
  // Drop-Sampling 2026-07-24 der wahre Sicherheitsmechanismus hinter ~der
  // Haelfte der Zyklus-Drops (doublecmd = FPC-Code). SOUND und billig:
  // auf der bekannten Decl-Zeile nach '=' hinter dem ':' suchen (':='
  // ausgeschlossen; auf einer Decl-Zeile gibt es sonst kein '=').
  var
    L        : string;
    Idx      : Integer;
    p, colon : Integer;
  begin
    Result := False;
    // KRITISCH (Re-Scan-Audit 2026-07-24, mormot cache x4): auf der GE-
    // STRIPPTEN Zeile matchen, nie auf der rohen - ein '=' im Zeilen-
    // kommentar ('cache: array[..] of cardinal; // 16KB+16KB=32KB') wuerde
    // sonst als Initializer fehlgedeutet und einen echten (dort sogar
    // absichtlichen) Uninit-Read maskieren.
    if not StrippedBuilt then Exit;
    Idx := (AInfo.DeclLine - 1) - StrippedFrom0;
    if (Idx < 0) or (Idx > High(StrippedLow)) then Exit;
    L := StrippedLow[Idx];   // bereits gelowert + kommentarfrei
    p := Pos(AInfo.NameLow, L);
    if p <= 0 then Exit;
    colon := Pos(':', L, p);
    if colon <= 0 then Exit;
    p := Pos('=', L, colon);
    // ':=' waere ein Assignment, kein Initializer - auf einer echten
    // Decl-Zeile steht ': <Typ> = <Wert>' (mind. 1 Zeichen dazwischen).
    Result := (p > colon + 1);
  end;

  function CfgFilterDropsReadBeforeWrite(const AInfo: TVarInfo): Boolean;
  // #6 Inkr.4 (SCA166 read-before-write, CFG Shared Service). Drei Regeln:
  //   0 (Decl-Initializer, sound): s. HasDeclInitializer.
  //   B (Zyklus/Back-Edge, der Ertragstreiber): Read-Block und ein Def-
  //     Block liegen im SELBEN Zyklus (beidseitiges CanReach) -> die Def
  //     der Iteration N erreicht den Read der Iteration N+1 ueber die
  //     Back-Edge. NUR fuer GEGUARDETE Reads (ReadBlk haengt an einem
  //     ckBranch = 'if not First then ...'-Arm): das Iteration-1-Risiko
  //     ist dort wert-korreliert (First-Guard). Inkr.4b-Verschaerfung nach
  //     Drop-Sampling (37 Stellen, 1 MASKED_BUG mormot bson): ein UN-
  //     geguardeter Read (Schleifenbedingung/gerader Body) laeuft in
  //     Iteration 1 ungeschuetzt -> kein Drop.
  //   A (ReachingDefs, sound): existiert KEIN def-freier Pfad Entry->Read,
  //     ist die Variable auf jedem Weg geschrieben -> sicherer Drop.
  // BEWUSST NICHT gedroppt (Selbst-Review 2026-07-24):
  //   * Same-Block-Defs ('D := Prev; Prev := Cur;' UNGEGUARDET im selben
  //     Block eines Loops): Iteration 1 liest echt uninitialisiert -
  //     plausibler TP; nur die GEGUARDETE Form (Read in eigenem Arm-Block)
  //     ist die FP-Klasse.
  //   * Sibling-Arme OHNE Loop ('if c then X := V else V := 1'): moeglicher
  //     Iteration-unabhaengiger TP, v1 laesst den Fund stehen.
  // Konservative Guards: goto/label -> Filter inaktiv; Read-/Def-Anker
  // nicht mappbar -> kein Drop.
  var
    ReadBlk : TCFGBlock;
    DefBlk  : TCFGBlock;
    PredB   : TCFGBlock;
    Defs    : TArray<TCFGBlock>;
    WL, k   : Integer;
    Dup     : Boolean;
    Guarded : Boolean;
  begin
    Result := False;
    // Regel 0: Decl-Initializer dominiert jeden Read (kein CFG noetig).
    if HasDeclInitializer(AInfo) then Exit(True);
    if Length(AInfo.WriteLines) = 0 then Exit;
    if BodyHasGotoOrLabel then Exit;
    if MethodCfg = nil then
      MethodCfg := TCFGBuilder.BuildFromMethod(MethodNode);
    ReadBlk := CfgBlockForLine(AInfo.FirstReadLine);
    if ReadBlk = nil then Exit;
    Defs := nil;
    for WL in AInfo.WriteLines do
    begin
      DefBlk := CfgBlockForLine(WL);
      if (DefBlk = nil) or (DefBlk = ReadBlk) then Continue;
      Dup := False;
      for k := 0 to High(Defs) do
        if Defs[k] = DefBlk then
        begin
          Dup := True;
          Break;
        end;
      if not Dup then Defs := Defs + [DefBlk];
    end;
    if Length(Defs) = 0 then Exit;
    // Regel B: gemeinsamer Zyklus - NUR wenn der Read geguardet ist
    // (ReadBlk ist Arm eines ckBranch, Inkr.4b s.o.).
    Guarded := False;
    for PredB in ReadBlk.Predecessors do
      if PredB.Kind = ckBranch then
      begin
        Guarded := True;
        Break;
      end;
    if Guarded then
      for k := 0 to High(Defs) do
        if MethodCfg.CanReach(Defs[k], ReadBlk) and
           MethodCfg.CanReach(ReadBlk, Defs[k]) then Exit(True);
    // Regel A: kein def-freier Pfad Entry->Read
    if not MethodCfg.CanReachAvoiding(MethodCfg.Entry, ReadBlk, Defs) then
      Exit(True);
  end;

  procedure PhaseD_Emit;
  // Klassifikation pro Var + Emit Findings.
  // Vier Skip-Pfade (UnusedLocal-Domain, managed types, nur Writes,
  // clean Read>=Write). Zwei Emit-Pfade:
  //   - FirstWrite = 0 + Refs > 0  -> 'never written' fcHigh
  //   - FirstRead < FirstWrite     -> 'read vor write' fcMedium
  var
    i : Integer;
    P : PVarInfo;
    F : TLeakFinding;
  begin
    for i := 0 to VarList.Count - 1 do
    begin
      P := @VarList.List[i];
      if P.RefCount <= 1 then Continue;        // UnusedLocal-Domain
      if P.IsManaged then Continue;            // managed types: opt-in
      if P.FirstReadLine = 0 then Continue;    // nur Writes - clean

      // Defensive Sanity-Check (Audit 2026-06-07 SCA166 Line-Attribution):
      // wenn der Var-Name auf der reported FirstReadLine GAR NICHT
      // vorkommt, hat irgendwo im Pipeline (Parser ifdef-Bloecke o.ae.)
      // eine fehlerhafte Zuordnung stattgefunden -> Befund suppress'en.
      // Klassisches Symptom: mormot.core.text 'temp' auf L3452 wo
      // weder 'temp' noch 'tmp' im Code steht.
      if (P.FirstReadLine > 0)
         and not LineContainsIdent(Lines, P.FirstReadLine, P.NameLow) then
        Continue;

      // Phase 2.7 (Audit 2026-06-10 Self-Scan): wenn die Variable als
      // Identifier in einer der Nested-Procedure-Ranges auftaucht, ist
      // sie potentiell eine Closure-Variable - outer-Body assigned,
      // nested-Proc liest. Der Lifecycle ist path-sensitive (Aufruf-
      // Reihenfolge); konservativ kein Finding. Killt 5-12 FPs aus dem
      // Self-Scan (Cands/Reported/SourceCache/grid/HasVal etc.).
      if IsVarUsedInNestedRanges(Lines, P.NameLow, NestedRanges) then
        Continue;
      // Robuster Source-Fallback: greift wenn der Parser unter dem Headless-
      // Pattern (nested routine + zweite var-Section) KEINE nkNestedRange-Marker
      // liefert, sodass NestedRanges leer/unvollstaendig ist und obiger Check
      // ins Leere laeuft (uRuleCatalog Cands, uFormatMismatch Reported).
      if IsVarReadInNestedRoutineFromSource(Lines, P.DeclLine, P.NameLow) then
        Continue;

      // Zensus-Triage 2026-07-25, H5 (Symptom-Gate keyword-misparse): der
      // gemeldete Var-NAME traegt im File eine eigene TYP-Deklaration
      // ('<name> = class/record/...') -> fehlgeparste Decl, kein echter
      // Local (Details s. IsFileDeclaredTypeName). Emit-seitig statt in
      // der Inventur, damit der File-Scan nur fuer die wenigen Emit-
      // Kandidaten laeuft (Perf) - fuer die Fundmenge aequivalent.
      if IsFileDeclaredTypeName(Lines, P.NameLow) then
        Continue;

      if P.FirstWriteLine = 0 then
      begin
        // B Hook 3 (Triage 2026-07-25): FPC-Decl-Initializer ('size: Int64
        // = 0;') dominiert jeden Read - Rule 0 galt bisher NUR im fcMedium-
        // Zweig (via CfgFilterDropsReadBeforeWrite), der fcHigh-Zweig
        // emittierte davor (doublecmd size/DenySym). HasDeclInitializer ist
        // stripped-basiert (Kommentar-'=' sicher, DeclCommentEquals-Test)
        // und fail-safe: ohne Stripped-Cache Exit(False) -> keine
        // Suppression.
        if HasDeclInitializer(P^) then
          Continue;
        // Referenced + never written - UninitVar fcHigh.
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(P.DeclLine);
        F.MissingVar := Format(
          'Uninitialised variable: %s is read on line %d but never ' +
          'assigned in this method. Add an explicit initialiser ' +
          '(%s := Default; / Create; / SetLength(...)).',
          [P.Name, P.FirstReadLine, P.Name]);
        F.SetKind(fkUninitVar, fcHigh);
        Results.Add(F);
        Continue;
      end;

      if P.FirstReadLine < P.FirstWriteLine then
      begin
        // Welle 3 (Core-Detektoren-Architektur, dritter nkConditionalRange-
        // Opt-in): liegt eine {$IFDEF}-Direktiven-Grenze STRIKT zwischen Read
        // und Write, stehen beide in verschiedenen bedingten Kompilierungs-
        // Zweigen (klassisch: Read im {$IFDEF LOGGING}-Block, Write danach).
        // Auf jeder realen Uebersetzung existiert nur EIN Zweig -> der 'Read
        // vor Write' ist ein Preprocessor-Phantom. Konservativ suppress'en
        // (matcht die Real-World-FP-Audit-Einstufung fuer conditional-
        // compilation). TP-sicher: nur Suppression, nie neuer Befund; ein
        // echtes Read-vor-Write OHNE Direktive dazwischen bleibt Befund.
        if DirLineBetween(ADirLines, P.FirstReadLine, P.FirstWriteLine) then
          Continue;

        // FP-Gate #6 Inkr.4 (2026-07-24): CFG-Postfilter - Def erreicht
        // den Read ueber die Loop-Back-Edge (Zyklus-Regel) oder jeder
        // Pfad zum Read passiert eine Def (ReachingDefs). Konservativ:
        // goto/label oder nicht mappbare Anker -> kein Drop.
        if CfgFilterDropsReadBeforeWrite(P^) then
          Continue;

        // Read vor Write - konservativ fcMedium (Phase 2.1 Sibling-
        // Write-Check obsolet weil pessimistic-Write sowieso jeden
        // Write registriert, kein Confidence-Downgrade-Pfad).
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := MethodNode.Name;
        F.LineNumber := IntToStr(P.FirstReadLine);
        F.MissingVar := Format(
          'Potential uninitialised read: %s read on line %d before its ' +
          'first assignment on line %d. Move the assignment up or add ' +
          'an explicit default before the first use.',
          [P.Name, P.FirstReadLine, P.FirstWriteLine]);
        F.SetKind(fkUninitVar, fcMedium);
        Results.Add(F);
      end;
    end;
  end;

var
  ChildCount : Integer;
begin
  // ------------------------------------------------------------------
  // ORCHESTRATOR: Fast-Outs + 4 Phasen (A, B, C, D)
  // ------------------------------------------------------------------
  if MethodNode = nil then Exit;
  // Fast-Out 1: asm-Block - kein Body zum Parsen.
  if IsAsmMethod(MethodNode) then Exit;
  // Fast-Out 2: pathologisch grosse Methode - Hard-Cap.
  // TD-1: einmal aus dem Context lesen (Arg + Vergleich derselbe Wert).
  MaxChildren := CfgMaxChildrenRecursive(AContext);
  ChildCount := CountChildrenRecursive(MethodNode, MaxChildren);
  if ChildCount > MaxChildren then Exit;

  LocalVars := MethodNode.FindAll(nkLocalVar);
  try
    if LocalVars.Count = 0 then Exit;
    if LocalVars.Count > CfgMaxLocalVars(AContext) then Exit;   // TD-1: per-Scan

    VarList      := TList<TVarInfo>.Create;
    VarMap       := TDictionary<string, Integer>.Create;
    BodySB       := TStringBuilder.Create;
    NestedRanges := TList<TLineRange>.Create;
    Lines        := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
    MethodCfg    := nil;   // #6 Inkr.4: lazy gebaut im PhaseD-Postfilter
    AbsAliases   := TDictionary<string,string>.Create;   // A3
    try
      // Perf (2026-07-05): P7-uninitvar - CalcMethodEndLine nur EINMAL
      // walken (vorher hier + nochmal in PhaseC); Stripped-Cache-Flag
      // initialisieren (lazy Build in PhaseC).
      MethodEndL    := CalcMethodEndLine(MethodNode);
      StrippedBuilt := False;
      // asm-Body-Skip (2026-07-13): eine Methode mit EINGEBETTETEM asm-Block
      // schreibt ihre Locals oft per Register/Memory-Ref (unsichtbar fuer den
      // Parser, tkKwAsm wird ohne Knoten geskippt) -> read-vor-write-FP. Der
      // ';asm'-Marker (IsAsmMethod, Fast-Out oben) fasst nur GANZE asm-Methoden.
      // Konservativ die ganze Methode ueberspringen (asm selten -> FN akzeptabel,
      // TP-sicher). Exit loest das umgebende finally (Lines/Ranges freigeben).
      if (Lines <> nil) and MethodHasAsmBlock(Lines, MethodNode.Line, MethodEndL) then
        Exit;
      // Phase 2.6: source-line-basierte Nested-Method-Detection.
      if Lines <> nil then
        CollectNestedMethodRangesViaSource(Lines, MethodNode.Line,
          MethodEndL, NestedRanges);

      // Phase 2.7: EXAKTE nkNestedRange-Marker vom Parser (verworfene nested
      // routines). Der Parser kennt deren Grenzen praezise; das ist robuster
      // als die line-basierte begin/end-Heuristik oben (die try/case/asm-end
      // nicht balanciert). Union beider Range-Quellen = nur mehr Skipping =
      // strikt weniger FP. Loest die SCA166-Self-Errors in grossen Methoden
      // mit vielen nested procs (uUninitVar/uUseAfterFree/uVisibilityCheck).
      for var NRMark in MethodNode.Children do
        if NRMark.Kind = nkNestedRange then
        begin
          var Rng : TLineRange;
          Rng.StartLine := NRMark.Line;
          Rng.EndLine   := StrToIntDef(NRMark.TypeRef, NRMark.Line);
          NestedRanges.Add(Rng);
        end;

      PhaseA_VarInventur;
      if VarList.Count = 0 then Exit;

      PhaseB_AstWalks;
      PhaseC_BodyTokenAndReads;
      PhaseD_Emit;
    finally
      AbsAliases.Free;  // A3
      MethodCfg.Free;   // #6 Inkr.4 (nil-sicher)
      ReleaseLines(Lines, Cached);
      NestedRanges.Free;
      BodySB.Free;
      VarMap.Free;
      VarList.Free;
    end;
  finally
    LocalVars.Free;
  end;
end;

class procedure TUninitVarDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Methods  : TList<TAstNode>;
  Recs     : TList<TAstNode>;
  RecTypes : TDictionary<string, Boolean>;
  M, R     : TAstNode;
  CondR    : TList<TAstNode>;
  DirLines : TArray<Integer>;
  n        : Integer;
  SigVarOut : TDictionary<string, TArray<Boolean>>;
  SigLines  : TStringList;
  SigCached : Boolean;
begin
  if UnitNode = nil then Exit;

  // Option C (2026-07-15, User-Scope-Entscheidung): SCA166 ueberspringt Test-
  // Fixture-Dateien komplett. Solche Files (Formatter-/Parser-TestCases,
  // *Test.pas, /test/ /tests/ /demos/ /samples/-Ordner) enthalten ABSICHTLICH
  // uninitialisierte Variablen als Edge-Case-Input - read-vor-write ist dort
  // kein produktiver Bug. Real-World-Baseline after38: 95 SCA166-Funde in 50
  // solchen Dateien (cnwizards/Test/.../TestCases, jvcl/tests, mORMot/test).
  // Nutzt die projektweite Fixture-Definition (TDetectorUtils.IsTestFixturePath).
  if TDetectorUtils.IsTestFixturePath(FileName, '') then Exit;

  // Welle 3: {$IFDEF}-Direktiven-Zeilen aus den nkConditionalRange-Markern
  // (Start=Node.Line, Ende=TypeRef) fuer den Read-vor-Write-Preprocessor-Guard.
  CondR := UnitNode.FindAll(nkConditionalRange);
  try
    n := 0;
    SetLength(DirLines, CondR.Count * 2);
    for R in CondR do
    begin
      DirLines[n] := R.Line; Inc(n);
      DirLines[n] := StrToIntDef(R.TypeRef, R.Line); Inc(n);
    end;
  finally
    CondR.Free;
  end;
  // Zensus-Triage 2026-07-25, Hook 1b: Same-File-Signaturindex EINMAL pro
  // File bauen (Interface + Implementation der gestrippten Quelle) und an
  // alle AnalyzeMethod-Aufrufe durchreichen. Lines kommen aus demselben
  // Cache, den auch AnalyzeMethod nutzt.
  SigVarOut := nil;
  SigLines := AcquireLines(FileName, SigCached, CtxFileTextCache(AContext));
  try
    if SigLines <> nil then
      SigVarOut := BuildSameFileVarOutIndex(SigLines);
  finally
    ReleaseLines(SigLines, SigCached);
  end;
  try
  // Value-Type-Records dieser Unit einsammeln: ein Methodenaufruf auf einer
  // record-typisierten lokalen Variablen initialisiert deren Felder (Self ist
  // var) - siehe ProcessCall. nkClass/Interface NICHT. Hinweis: das alte
  // `object`-Idiom fuehrt der Parser nicht als nkRecord -> hier nicht erfasst
  // (faellt auf die Init-Verb-Allowlist zurueck, konservativ).
  RecTypes := TDictionary<string, Boolean>.Create;
  try
    Recs := UnitNode.FindAll(nkRecord);
    try
      for R in Recs do
        if R.Name <> '' then
          RecTypes.AddOrSetValue(LowerCase(Trim(R.Name)), True);
    finally
      Recs.Free;
    end;
    Methods := UnitNode.FindAll(nkMethod);
    try
      for M in Methods do
        AnalyzeMethod(M, FileName, Results, AContext, RecTypes, DirLines,
                      SigVarOut);
    finally
      Methods.Free;
    end;
  finally
    RecTypes.Free;
  end;
  finally
    SigVarOut.Free;
  end;
end;

end.
