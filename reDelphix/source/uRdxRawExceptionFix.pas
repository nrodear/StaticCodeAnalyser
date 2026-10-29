unit uRdxRawExceptionFix;

// reDelphix - Editorhilfe fuer SCA127 RaisingRawException, OHNE ToolsAPI und
// ohne Parser: in 'raise Exception.Create(..)' wird nur der Klassenname
// ersetzt - 'Exception' -> 'EArgumentException' (erster Eintrag) bzw.
// 'EInvalidOpException' (zweiter Eintrag, Variant = 1). Konstruktor und
// Argumente bleiben, wie sie sind (Create, CreateFmt, CreateRes, CreateHelp
// ...): beide Klassen erben alle Konstruktoren von Exception.
//
// WELCHE KLASSE (Konzept_Editorhilfen_Recherche_2026-10-11_Tabellen, Zeile
// SCA127): die Wahl ist das Urteil des Benutzers - die Hilfe raet nicht. Die
// Recherche nennt ein Menue weniger RTL-Klassen; die Tabelle hat zwei
// Eintraege, und die decken die beiden Absichten, die ein rohes
// 'raise Exception' meist traegt: ein falsches ARGUMENT des Aufrufers
// (EArgumentException; EArgumentOutOfRangeException ist ihre Unterklasse,
// ein Handler darauf faengt sie nicht) und ein unzulaessiger ZUSTAND bzw.
// Aufruf zur falschen Zeit (EInvalidOpException). Passt keine von beiden
// (Datei fehlt, Netz, Fachfehler), waehlt der Benutzer keinen Eintrag. Die
// Meldung des Detektors nennt selbst EArgumentException. Beide Klassen
// stehen in SysUtils von Delphi (System.SysUtils) und FPC 3.2.2
// (sysutilh.inc) - keine FPC-Weiche noetig. EProgrammerError gibt es in
// keiner der beiden RTLs. In Delphi gibt es beide erst seit Delphi 2009
// (mit den Generics; Delphi 7/2007 kennen sie nicht): eine Datei, die
// nach aelteren Compilern fragt, bekommt keine Hilfe (Realworld-Test
// rwE29: cnwizards ThirdParty\PascalScript, gebaut nur mit Delphi 5-2007,
// '{$IFDEF DELPHI3UP}' in der Unit - E2003 nach der Hilfe).
//
// AENDERT DAS VERHALTEN (Changes=True): Handler 'on E: EArgumentException'
// bzw. 'on E: EInvalidOpException' - auch in Aufrufern anderer Units -
// fangen die Ausnahme jetzt, 'E is ...' und E.ClassName im Log aendern sich.
// 'on E: Exception' faengt weiter.
//
// DER FUND: uRaisingRawException meldet die Zeile des 'raise' (nkRaise),
// wenn der Ausdruck mit 'Exception.Create' beginnt oder genau 'Exception'
// ist; die Meldung ist fest und nennt keine Spalte. Der Planer sucht das
// 'raise' im Code der Zeile; Klassenname und Konstruktor duerfen auf den
// Folgezeilen stehen (die Ersetzung trifft nur das Token 'Exception').
//
// GESPERRT (lieber keine Hilfe als eine falsche):
//   - kein 'raise Exception' im Code der Zeile (Zeile verschoben, nur in
//     Kommentar oder String, schon eine andere Klasse) oder mehr als eines
//     (der Fund koennte jedes meinen),
//   - kein Konstruktor ('raise Exception;' - es gibt kein Objekt, dessen
//     Klasse sich aendern koennte),
//   - eine Compiler-Direktive zwischen 'raise' und dem Konstruktor,
//   - die Datei deklariert selbst 'Exception' (dann ist es nicht die Klasse
//     aus SysUtils, und die neue haette eine andere Hierarchie) - seit
//     rwE30 Stufe 2 nur, wo die Deklaration am raise gilt: ein Parameter
//     oder eine lokale Variable einer ANDEREN Routine sperrt nicht
//     (DeclReaches; Alcinoe.FBX.Lib.pas, Setup.MainFunc.pas) - oder die
//     Zielklasse (dann bande der neue Name an die eigene; jede Deklaration),
//   - die Datei fragt nach Compilern vor Delphi 2009 (uRdxCompilerTraces,
//     FLOOR_DEFAULT_FN - dieselbe Schwelle wie Default(T) bei SCA121; die
//     Schwelle selbst zaehlt mit: wer nach 2009 fragt, baut auch davor;
//     seit rwE30 Stufe 2 auch die mORMot-Symbole und mormot.defines.inc) -
//     ausser die Datei beweist selbst einen neueren Compiler
//     (ModernProof: Inline-Variable, RTL-Namensraum im uses),
//   - was nur die Platte weiss, prueft der Adapter (uRdxFixTable,
//     TRdxMagicFixes.ProjectReason mit lfExceptionClasses, rwE30 Stufe 2):
//     alte Projektdateien in der Nachbarschaft (.dof, .cfg/.dof eines
//     Projekts ohne eigene .dproj, .dproj vor 2009), Pakete fuer ein Delphi
//     vor 2009, alte Spuren in den Includes - nur ein Beleg sperrt; ein
//     erschoepfter Deckel, ein nicht gefundenes Include und ein Netzpfad
//     nicht (der Normalfall ist ein Delphi ab 2009).
// Grenze: eine Unit im uses, die selbst EArgumentException bzw.
// EInvalidOpException deklariert, sieht der Planer nicht (nur die Datei);
// ebensowenig ein with-Ausdruck mit einem Member 'Exception'.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// (Form TRdxFixPlanner, mit der uses-Ergaenzung SysUtils) traegt die Tabelle
// uRdxFixTable.

interface

uses
  uRdxBufferMath,     // TRdxEdit
  uRdxCodeMap;        // TRdxCodeMap

const
  // Die Klassen der beiden Eintraege (SysUtils in Delphi und FPC 3.2.2).
  RAWEXC_ARGUMENT   = 'EArgumentException';
  RAWEXC_INVALID_OP = 'EInvalidOpException';
  // Die Gruende der Ablehnung als englische msgids (Entscheid E29); die Tests
  // pruefen sie mit _().
  R_RAWEXC_MOVED = 'no "raise Exception" in the code of the reported line';
  R_RAWEXC_MANY = 'line %d carries %d "raise Exception" statements - '
    + 'ambiguous';
  R_RAWEXC_NO_CTOR = '"raise Exception" without a constructor call '
    + '(Create, CreateFmt ...) - there is no object whose class could change';
  R_RAWEXC_DIRECTIVE = 'compiler directive between "raise" and the '
    + 'constructor';
  R_RAWEXC_OWN = 'the file declares its own "%s" - it is not the class from '
    + 'SysUtils';
  R_RAWEXC_OLD = 'the file asks for old compilers (%s, line %d) - %s exists '
    + 'in SysUtils only from Delphi 2009 on';

type
  // Die Planer an einer Zeile (TRdxMapPlanner-Form, MapFix oeffnet die
  // Code-Sicht): reine Textlogik. AMessage bleibt ungenutzt - die Meldung
  // des Detektors ist fest.
  TRdxRawExceptionFix = class
  public
    // Erster Eintrag: 'raise Exception.X(..)' -> 'raise
    // EArgumentException.X(..)'.
    class function ToArgumentException(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Zweiter Eintrag: 'raise Exception.X(..)' -> 'raise
    // EInvalidOpException.X(..)'.
    class function ToInvalidOpException(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Der gemeinsame Rumpf: das eine 'raise Exception.<Konstruktor>' auf
    // ALine bekommt die Klasse AClass (wie geschrieben eingesetzt).
    class function Retype(AMap: TRdxCodeMap; ALine: Integer;
      const AClass: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxBlocks,        // TRdxBlocks.HeadBefore/ReadRoutine (DeclReaches)
  uRdxCompilerTraces, // OldCompilerTrace, FLOOR_DEFAULT_FN (Delphi 2009),
                     // ModernProof
  uRdxText;          // _(), MsgMovedSuffix (E29, nie uLocalization)

const
  SPAN_127   = 'sca127';
  EXC_LOW    = 'exception';
  CTOR_LOW   = 'create';     // Create, CreateFmt, CreateRes, CreateHelp ...
  // Davor bzw. dahinter wird ein Name deklariert: 'var X', 'X: T',
  // 'X = class', 'function X' (wie uRdxGotoExitFix fuer 'Exit').
  DECL_PREV: array[0..4] of string = ('var', 'const', 'property',
    'procedure', 'function');
  DECL_NEXT: array[0..1] of string = (':', '=');
  // DeclReaches (rwE30 Stufe 2): Kopfwoerter, Woerter, an denen die Suche
  // nach der Parameterliste endet, und die Abschnitte der Unit.
  ROUTINE_HEAD_WORDS: array[0..4] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator');
  PARAM_STOPS: array[0..7] of string = ('begin', 'end', 'type',
    'implementation', 'interface', 'uses', 'do', 'then');
  SECTION_WORDS: array[0..3] of string = ('interface', 'implementation',
    'initialization', 'finalization');
  KW_IMPLEMENTATION = 'implementation';
  MAX_PARAM_TOKENS = 400;

type
  // Ein 'raise Exception' im Code: das raise, der Klassenname und - wenn
  // einer folgt - der Konstruktor hinter dem Punkt.
  TRaiseSite = record
    RaiseTok : TRdxToken;
    ExcTok   : TRdxToken;
    CtorTok  : TRdxToken;   // Low = '' ohne Konstruktor
  end;

// Beginnt an AWord ein Konstruktorname ('Create', 'CreateFmt' ...)?
function IsCtorWord(const AWord: TRdxToken): Boolean;
begin
  Result := AWord.IsWord and (Copy(AWord.Low, 1, Length(CTOR_LOW)) = CTOR_LOW);
end;

// Folgt dem raise-Token ARaise der Klassenname 'Exception'? Dann True und
// die Stelle in ASite (CtorTok leer, wenn kein '.Create..' folgt).
function ReadSite(AMap: TRdxCodeMap; const ARaise: TRdxToken;
  out ASite: TRaiseSite): Boolean;
var
  Dot, Ctor : TRdxToken;
begin
  ASite := Default(TRaiseSite);
  ASite.RaiseTok := ARaise;
  ASite.ExcTok := After(AMap, ARaise);
  Result := ASite.ExcTok.Low = EXC_LOW;
  if not Result then Exit;
  Dot := After(AMap, ASite.ExcTok);
  if Dot.Low <> '.' then Exit;
  Ctor := After(AMap, Dot);
  if IsCtorWord(Ctor) then
    ASite.CtorTok := Ctor;
end;

// Die 'raise Exception' im Code von ALine: ihre Zahl, die letzte in ASite.
function SitesOnLine(AMap: TRdxCodeMap; ALine: Integer;
  out ASite: TRaiseSite): Integer;
var
  T, Prev : TRdxToken;
  S       : TRaiseSite;
begin
  Result := 0;
  ASite := Default(TRaiseSite);
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = 'raise') and IsKeywordAfter(T, Prev) and ReadSite(AMap, T, S)
    then
    begin
      Inc(Result);
      ASite := S;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
end;

// Der Routinenkopf, in dessen Parameterliste ADecl steht ('procedure
// X(const Exception: AnsiString)') - das Kopfwort; Low = '' sonst. Rueckwaerts
// bis zur offenen '(' (ein ';' auf Tiefe 0 trennt dort nur Parameter); ein
// Schluesselwort, das keine Parameterliste traegt, beendet die Suche.
function ParamHead(AMap: TRdxCodeMap; const ADecl: TRdxToken): TRdxToken;
var
  T, P  : TRdxToken;
  Depth : Integer;
  Count : Integer;
begin
  Result := Default(TRdxToken);
  T := Before(AMap, ADecl);
  Depth := 0;
  Count := 0;
  while (T.Low <> '') and (Count < MAX_PARAM_TOKENS) do
  begin
    Depth := Depth - ParenDelta(T);
    if Depth < 0 then Break;
    if (Depth = 0) and IsKeywordAfter(T, Before(AMap, T))
       and InList(T.Low, PARAM_STOPS) then
      Exit;
    T := Before(AMap, T);
    Inc(Count);
  end;
  if (Depth >= 0) or (T.Low <> '(') then Exit;
  // Vor der '(' der Name (auch 'TFoo.Bar', 'Foo<T>' bleibt aussen vor) und
  // davor das Kopfwort.
  P := Before(AMap, T);
  while P.IsWord and not InList(P.Low, ROUTINE_HEAD_WORDS) do
  begin
    P := Before(AMap, P);
    if P.Low <> '.' then Break;
    P := Before(AMap, P);
  end;
  if InList(P.Low, ROUTINE_HEAD_WORDS) and IsRoutineHead(AMap, P) then
    Result := P;
end;

// Die innerste Routine (Kopf bis letztes ';'), die AAt umfasst: rbfFound
// mit ARoutine; rbfUnsure, wenn davor ein Kopf mit unsicheren Grenzen steht
// (er koennte es sein); rbfNone ausserhalb jeder Routine (Abschnittswort
// der Unit oder Dateianfang).
function RoutineAround(AMap: TRdxCodeMap; const AAt: TRdxToken;
  out ARoutine: TRdxRoutine): TRdxBodyFind;
var
  T : TRdxToken;
  S : TRdxHeadStep;
begin
  ARoutine := Default(TRdxRoutine);
  T := AAt;
  while TRdxBlocks.HeadBefore(AMap, T, SECTION_WORDS, S) do
  begin
    if S.Stop then
      Break;
    if S.Reason <> '' then
      Exit(rbfUnsure);
    if TokBefore(S.Routine.Head, AAt) and (S.Routine.Last.Low <> '')
       and TokBefore(AAt, S.Routine.Last) then
    begin
      ARoutine := S.Routine;
      Exit(rbfFound);
    end;
  end;
  Result := rbfNone;
end;

// Umfasst die Routine R (Kopf bis letztes ';') das Token AAt?
function Encloses(const R: TRdxRoutine; const AAt: TRdxToken): Boolean;
begin
  Result := (R.Last.Low <> '') and TokBefore(R.Head, AAt)
    and TokBefore(AAt, R.Last);
end;

// Das Schluesselwort 'implementation' der Datei; Low = '' ohne.
function ImplementationTok(AMap: TRdxCodeMap): TRdxToken;
var
  T : TRdxToken;
begin
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), KW_IMPLEMENTATION);
  while T.Low <> '' do
  begin
    if (T.Low = KW_IMPLEMENTATION) and IsKeywordAfter(T, Before(AMap, T)) then
      Exit(T);
    T := NextTokenOnLineWith(AMap, T, KW_IMPLEMENTATION);
  end;
  Result := Default(TRdxToken);
end;

// Gilt die Deklaration ADecl am raise ARaise (rwE30 Stufe 2: Alcinoe.FBX.
// Lib.pas - 'Exception: EALFBXError' lokal in einer verschachtelten Prozedur
// einer ANDEREN Methode; Setup.MainFunc.pas - 'const Exception: AnsiString'
// Parameter einer anderen Routine)? Ein Parameter bzw. eine lokale
// Deklaration gilt nur in ihrer Routine samt deren lokalen Routinen; ein
// Parameter im interface-Teil gilt im implementation-Teil nie. Was
// ausserhalb jeder Routine steht (Typ, globale Variable, Feld, Property)
// oder in einer Routine mit unsicheren Grenzen, gilt - vorsichtig - in der
// ganzen Datei.
function DeclReaches(AMap: TRdxCodeMap; const ADecl, ARaise,
  AImpl: TRdxToken): Boolean;
var
  Head : TRdxToken;
  R    : TRdxRoutine;
begin
  Head := ParamHead(AMap, ADecl);
  if Head.Low <> '' then
  begin
    if (AImpl.Low <> '') and TokBefore(ADecl, AImpl)
       and TokBefore(AImpl, ARaise) then
      Exit(False);
    if TRdxBlocks.ReadRoutine(AMap, Head, R) <> '' then
      Exit(True);
    Exit(Encloses(R, ARaise));
  end;
  // Lokal heisst: zwischen Kopf und Rumpf einer Routine MIT Rumpf (eine
  // Methodendeklaration im Klassenrumpf hat keinen - ihr Feld gilt der
  // ganzen Klasse).
  if (RoutineAround(AMap, ADecl, R) = rbfFound) and (R.Body.Low <> '')
     and TokBefore(R.HeaderEnd, ADecl) and TokBefore(ADecl, R.Body) then
    Result := Encloses(R, ARaise)
  else
    Result := True;
end;

// Deklariert die Datei einen Namen ALow (klein) - als Typ, Variable,
// Konstante, Feld, Parameter, Property oder Routine? Ein Treffer zu viel
// ('if Exception = X') sperrt nur. Mit ARaise (Low <> '') zaehlen nur
// Deklarationen, die dort gelten (DeclReaches, rwE30 Stufe 2) - fuer
// 'Exception'; die Zielklasse fragt ohne (jede Deklaration sperrt).
function DeclaresOwn(AMap: TRdxCodeMap; const ALow: string;
  const ARaise: TRdxToken): Boolean;
var
  T, P, Impl : TRdxToken;
begin
  Result := False;
  Impl := Default(TRdxToken);
  if ARaise.Low <> '' then
    Impl := ImplementationTok(AMap);
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if T.Low = ALow then
    begin
      P := Before(AMap, T);
      if (P.Low <> '.')
         and (InList(After(AMap, T).Low, DECL_NEXT) or InList(P.Low, DECL_PREV))
         and ((ARaise.Low = '') or DeclReaches(AMap, T, ARaise, Impl))
      then
        Exit(True);
    end;
    T := NextTokenOnLineWith(AMap, T, ALow);
  end;
end;

{ TRdxRawExceptionFix }

class function TRdxRawExceptionFix.Retype(AMap: TRdxCodeMap; ALine: Integer;
  const AClass: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Site  : TRaiseSite;
  n, Li : Integer;
  Trace : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  n := SitesOnLine(AMap, ALine, Site);
  if n = 0 then
    AReason := MsgMovedSuffix(_(R_RAWEXC_MOVED))
  else if n > 1 then
    AReason := _(R_RAWEXC_MANY, [ALine, n])
  else if Site.CtorTok.Low = '' then
    AReason := _(R_RAWEXC_NO_CTOR)
  else if DirectiveBetween(AMap, Site.RaiseTok, Site.CtorTok.Line,
            Site.CtorTok.Col) then
    AReason := _(R_RAWEXC_DIRECTIVE)
  else if DeclaresOwn(AMap, EXC_LOW, Site.RaiseTok) then
    AReason := _(R_RAWEXC_OWN, ['Exception'])
  else if DeclaresOwn(AMap, LowerCase(AClass), Default(TRdxToken)) then
    AReason := _(R_RAWEXC_OWN, [AClass])
  else if not ProofCovers(ModernProof(AMap), FLOOR_DEFAULT_FN) then
  begin
    // Eine Inline-Variable bzw. ein RTL-Namensraum ausserhalb jeder Weiche
    // beweist Delphi ab XE2 - die Spur widerlegt (rwE30 Stufe 2).
    Trace := OldCompilerTrace(AMap, FLOOR_DEFAULT_FN, Li);
    if Trace <> '' then
      AReason := _(R_RAWEXC_OLD, [Trace, Li, AClass]);
  end;
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_127, Site.ExcTok.Line, Site.ExcTok.Col,
    Site.ExcTok.Line, Site.ExcTok.EndCol);
  AEdit.Expected := Copy(AMap.Raw(Site.ExcTok.Line), Site.ExcTok.Col,
    Site.ExcTok.Len);
  AEdit.NewText := AClass;
  Result := True;
end;

class function TRdxRawExceptionFix.ToArgumentException(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := Retype(AMap, ALine, RAWEXC_ARGUMENT, AEdit, AReason);
end;

class function TRdxRawExceptionFix.ToInvalidOpException(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
begin
  Result := Retype(AMap, ALine, RAWEXC_INVALID_OP, AEdit, AReason);
end;

end.
