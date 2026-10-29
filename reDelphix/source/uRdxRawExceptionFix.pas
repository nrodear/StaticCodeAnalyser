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
//     aus SysUtils, und die neue haette eine andere Hierarchie) oder die
//     Zielklasse (dann bande der neue Name an die eigene),
//   - die Datei fragt nach Compilern vor Delphi 2009 (uRdxCompilerTraces,
//     FLOOR_DEFAULT_FN - dieselbe Schwelle wie Default(T) bei SCA121; die
//     Schwelle selbst zaehlt mit: wer nach 2009 fragt, baut auch davor).
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
  uRdxCompilerTraces, // OldCompilerTrace, FLOOR_DEFAULT_FN (Delphi 2009)
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

// Deklariert die Datei einen Namen ALow (klein) - als Typ, Variable,
// Konstante, Feld, Parameter, Property oder Routine? Ein Treffer zu viel
// ('if Exception = X') sperrt nur.
function DeclaresOwn(AMap: TRdxCodeMap; const ALow: string): Boolean;
var
  T, P : TRdxToken;
begin
  Result := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), ALow);
  while T.Low <> '' do
  begin
    if T.Low = ALow then
    begin
      P := Before(AMap, T);
      if (P.Low <> '.')
         and (InList(After(AMap, T).Low, DECL_NEXT) or InList(P.Low, DECL_PREV))
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
  else if DeclaresOwn(AMap, EXC_LOW) then
    AReason := _(R_RAWEXC_OWN, ['Exception'])
  else if DeclaresOwn(AMap, LowerCase(AClass)) then
    AReason := _(R_RAWEXC_OWN, [AClass])
  else
  begin
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
