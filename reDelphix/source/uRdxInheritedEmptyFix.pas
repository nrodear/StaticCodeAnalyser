unit uRdxInheritedEmptyFix;

// reDelphix - Editorhilfe fuer SCA125 InheritedMethodEmpty, OHNE ToolsAPI
// und ohne Parser (Charge A4, Todo Q14): ein Override, dessen Rumpf nur den
// Vorfahren mit denselben Argumenten ruft, verschwindet ganz -
//   Deklaration:      '    procedure Paint; override;'   -> weg
//   Implementierung:  'procedure TFoo.Paint; begin inherited; end;' -> weg
// Ohne Override erreicht die virtuelle Bindung die Methode des Vorfahren
// direkt; Aufrufe 'Obj.Paint' und 'inherited Paint' in Nachfahren bleiben
// gueltig. Zwei Ersetzungen in EINEM Schritt; Bereiche, Doku darueber, eine
// Leerzeile und die Marker-Pruefung wie bei SCA147
// (TRdxRoutineFixes.DeleteMethodEdits).
//
// WAS DER DETEKTOR MELDET (uInheritedMethodEmpty, seit Charge A4 mit der
// Deklaration): die Zeile des Implementierungskopfs, Meldung 'Override X
// contains only "inherited" ...'. Er sieht Vorfahren ausserhalb der Unit
// nicht und meldet dann mit niedriger Konfidenz.
//
// SICHTBARKEIT - die Bedingung, an der die Hilfe am haeufigsten sperrt: steht
// das Override in einem SICHTBAREREN Abschnitt als die Methode des Vorfahren
// (public ueber protected - TButton.Click hebt so an), bricht das Loeschen
// Aufrufer (E2361). Und schon protected ueber einem protected-Vorfahren in
// einer ANDEREN Unit kann brechen: protected-Member sind in der ganzen
// eigenen Unit sichtbar ("protected hack"). Deshalb hilft die Hilfe nur,
// wenn die Methode des naechsten Vorfahren in DIESER Datei steht und
// mindestens dieselben Aufrufer erreicht (Reach); sonst Sperre "von Hand
// pruefen" - auch fuer TObject.Destroy (Vorfahr nicht in der Datei).
//
// BEDINGUNGEN (lieber keine Hilfe als eine falsche - die Hilfe prueft
// schaerfer als der Detektor):
//   * genau ein Kopf der gemeldeten Methode auf der Zeile, die eine
//     Implementierung hinter implementation, keine Klassenmethode, keine
//     Direktive am Kopf, keine lokalen Deklarationen, Rumpf begin..end mit
//     genau 'inherited;' (nicht in Funktionen), 'inherited Name;' (ohne
//     Parameter), 'inherited Name(p1, .., pn)' (Parameter 1:1) bzw.
//     'Result := inherited [Name[(..)]]' in Funktionen;
//   * kein Kommentar und keine Direktive vom Kopf bis zum letzten ';' (der
//     Kommentar ginge still mit verloren);
//   * die Klasse genau einmal in der Datei, darin genau eine Deklaration,
//     gleiche Art (procedure/function ...), nur 'override', kein Attribut,
//     kein Default-Parameter, keine Direktive in ihren Zeilen;
//   * der naechste Vorfahr mit dieser Methode steht in der Datei, genau
//     eine Deklaration, nicht abstract, mindestens so sichtbar.
//
// OHNE ToolsAPI und ohne Delphi-only-Unit (FPC-Pruefstand): den Adapter
// (Form TRdxPlannerOf<TRdxRoutinePlan>) traegt die Tabelle uRdxFixTable.

interface

uses
  uRdxRoutineFixes,      // TRdxRoutinePlan
  uRdxCodeMap;           // TRdxCodeMap

const
  // Die Gruende der Ablehnung als englische msgids (die Tests pruefen sie
  // mit _()). Gleicher Wortlaut wie bei SCA148 heisst gleiche msgid.
  R_IE_MESSAGE = 'method name missing from the message';
  R_IE_NO_HEAD = 'no header of the method %s';
  R_IE_MANY_HEADS = 'the line has more than one header of the method %s';
  R_IE_BOUNDS = 'the bounds of the method %s are not safe to read';
  R_IE_CLASS_METHOD = 'class method - the quick fix removes only instance '
    + 'overrides';
  R_IE_NOT_IMPL = 'the header is not the one implementation of %s after '
    + '"implementation"';
  R_IE_IMPLS = '%d implementations of %s - overload?';
  R_IE_IMPL_DIRECTIVE = 'directive "%s" on the implementation header';
  R_IE_LOCALS = 'the method declares local variables, constants or routines';
  R_IE_BODY = 'the body does more than call the inherited method with the '
    + 'same arguments';
  R_IE_DIRECTIVES = 'compiler directive in the declaration or the '
    + 'implementation';
  R_IE_COMMENT = 'comment in line %d of the method - it would be deleted '
    + 'with it; %s';
  R_IE_NO_CLASS = 'no class %s with a body in this file (record, other '
    + 'unit?)';
  R_IE_CLASSES = '%d classes named %s in this file';
  R_IE_DECLS = '%d declarations of %s in the class - overload?';
  R_IE_DECL_READ = 'the declaration of %s is not safe to read';
  R_IE_DECL_KIND = 'declaration and implementation of %s differ (%s, %s)';
  R_IE_NO_OVERRIDE = 'the declaration of %s carries no "override"';
  R_IE_DIRECTIVE = 'directive "%s" on the declaration';
  R_IE_ATTR = 'attribute on the declaration - RTTI or a framework can use '
    + 'the override';
  R_IE_DEFAULT = 'default value on a parameter - it can differ from the '
    + 'ancestor';
  R_IE_PARAMS = 'declaration and implementation of %s have different '
    + 'parameter lists';
  R_IE_VIS_UNPROVEN = 'visibility of the ancestor not proven - %s is not '
    + 'declared in this file; %s';
  R_IE_ANC_DECLS = '%d declarations of %s in the ancestor %s - overload?';
  R_IE_ANC_ABSTRACT = 'the method of the ancestor %s is abstract - without '
    + 'the override a call raises EAbstractError';
  R_IE_ANC_CHAIN = 'ancestor chain too long - boundaries not certain';
  R_IE_VIS_WIDENS = 'the override is under "%s", the method of the ancestor '
    + '%s under "%s" - the override widens the visibility, removing it '
    + 'breaks callers';
  R_IE_VIS_DEFAULT = 'the override or the method of the ancestor %s stands '
    + 'before any visibility section - the visibility is not certain; %s';

type
  // Der Planer von SCA125 (Form TRdxPlannerOf<TRdxRoutinePlan> der
  // Tabelle): Name = der Methodenname aus der Meldung (Menuetext), auch
  // wenn er ablehnt; Includes bleibt leer.
  TRdxInheritedEmptyFix = class
  public
    // ALine ist die Zeile des Implementierungskopfs, AMessage die Meldung
    // ('Override X contains only "inherited" ...'). Liefert die beiden
    // Ersetzungen (Deklaration, Implementierung) oder den Grund.
    class function DeleteOverride(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out APlan: TRdxRoutinePlan;
      out AReason: string): Boolean; static;
    // Der Methodenname aus der Meldung, '' ohne.
    class function MethodNameOf(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRdxBlocks,        // TRdxBlocks (Finder, ReadRoutine), TRdxRoutine
  uRdxDeclFixes,     // ParamNamesOf
  uRdxText;          // _(): in die reDelphix-Sprache (E29), nie uLocalization

const
  SPAN_125 = 'sca125';
  KEY_OVERRIDE = 'Override ';
  KEY_ONLY     = ' contains only';
  KW_CLASS     = 'class';
  KW_OVERRIDE  = 'override';
  MAX_ANCESTORS = 32;

type
  // Was der Planer ueber die Methode weiss.
  TRdxIeCtx = record
    Meth      : string;            // 'Paint' wie in der Meldung
    LowMeth   : string;
    ClassPath : string;            // 'tfoo' bzw. 'touter.tinner' (klein)
    Impl      : TRdxRoutine;       // die Implementierung
    Decl      : TRdxRoutine;       // die Deklaration im Klassenrumpf
    ClassTok  : TRdxToken;         // 'class' des Klassenkopfs
    Vis       : string;            // Abschnitt der Deklaration
    Params    : TArray<string>;    // Parameternamen (Kopf, sonst Deklaration)
  end;

// Wer eine Methode unter dem Abschnitt AVis erreicht, ausser der Klasse
// selbst: 'u' die Unit, 'd' Nachfahren, 'a' alle, 'r' RTTI (published).
function Reach(const AVis: string): string;
begin
  if AVis = 'strict private' then
    Result := ''
  else if AVis = 'private' then
    Result := 'u'
  else if AVis = 'strict protected' then
    Result := 'd'
  else if AVis = 'protected' then
    Result := 'ud'
  else if AVis = 'public' then
    Result := 'uda'
  else
    Result := 'udar';   // published, automated
end;

// Erreicht AAnc mindestens alle, die AOwn erreicht?
function ReachCovered(const AOwn, AAnc: string): Boolean;
var
  C : Char;
begin
  for C in Reach(AOwn) do
    if Pos(C, Reach(AAnc)) = 0 then
      Exit(False);
  Result := True;
end;

{ ---- Die Implementierung ---- }

// Der eine Kopf der Methode auf ALine (letztes Glied = Methodenname, davor
// mindestens eine Klasse), gelesen bis zum Ende der Routine. '' oder der
// Grund.
function HeadReason(AMap: TRdxCodeMap; ALine: Integer;
  var C: TRdxIeCtx): string;
var
  T   : TRdxToken;
  R   : TRdxRoutine;
  n   : Integer;
  Bad : Boolean;
begin
  n := 0;
  Bad := False;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if IsRoutineHead(AMap, T) then
    begin
      R := Default(TRdxRoutine);
      if TRdxBlocks.ReadRoutine(AMap, HeadStart(AMap, T), R) <> '' then
        Bad := True
      else if (Length(R.Parts) >= 2)
         and SameIdent(R.Parts[High(R.Parts)], C.LowMeth) then
      begin
        Inc(n);
        C.Impl := R;
      end;
    end;
    T := After(AMap, T);
  end;
  if n > 1 then
    Exit(_(R_IE_MANY_HEADS, [C.Meth]));
  if n = 0 then
  begin
    if Bad then
      Exit(_(R_IE_BOUNDS, [C.Meth]));
    Exit(MsgMovedSuffix(_(R_IE_NO_HEAD, [C.Meth])));
  end;
  C.ClassPath := JoinStrings(Copy(C.Impl.Parts, 0, Length(C.Impl.Parts) - 1),
    '.');
  Result := '';
end;

// Die Parameternamen hinter dem Namen ANameTok ('(' nach optionalen
// Typparametern), leer ohne Liste; AShape die Liste als Token-Folge.
function ParamsAfter(AMap: TRdxCodeMap; const ANameTok: TRdxToken;
  out AShape: string): TArray<string>;
var
  T : TRdxToken;
begin
  Result := nil;
  AShape := '';
  T := After(AMap, ANameTok);
  if T.Low = '<' then
    T := AfterClose(AMap, T);
  if T.Low = '(' then
    Result := ParamNamesOf(AMap, T, ')', AShape);
end;

// Steht in der Token-Folge AShape ein '=' (Default-Wert)?
function HasDefault(const AShape: string): Boolean;
begin
  Result := Pos(' = ', ' ' + AShape) > 0;
end;

// Kopf der Implementierung: keine Klassenmethode, die eine Implementierung,
// keine Direktive, keine lokalen Deklarationen, begin-Rumpf. '' oder der
// Grund.
function ImplReason(AMap: TRdxCodeMap; var C: TRdxIeCtx): string;
var
  Heads : TArray<TRdxToken>;
begin
  if C.Impl.Head.Low = KW_CLASS then
    Exit(_(R_IE_CLASS_METHOD));
  Heads := TRdxBlocks.FindMethodImpls(AMap, C.ClassPath, C.Meth);
  if Length(Heads) > 1 then
    Exit(_(R_IE_IMPLS, [Length(Heads), C.Meth]));
  if (Length(Heads) = 0) or not SameTok(Heads[0], C.Impl.Head) then
    Exit(_(R_IE_NOT_IMPL, [C.Meth]));
  if Length(C.Impl.Directives) > 0 then
    Exit(_(R_IE_IMPL_DIRECTIVE, [C.Impl.Directives[0]]));
  if C.Impl.Body.Low <> 'begin' then
    Exit(MsgStaleSuffix(_(R_IE_BODY)));
  if not SameTok(After(AMap, C.Impl.HeaderEnd), C.Impl.Body) then
    Exit(_(R_IE_LOCALS));
  Result := '';
end;

// Kommentar oder Direktive vom Kopf bis zum letzten ';' der Routine R?
// 0 oder die erste Zeile mit einem.
function CommentLine(AMap: TRdxCodeMap; const R: TRdxRoutine): Integer;
var
  Li, F, L : Integer;
begin
  for Li := R.Head.Line to R.Last.Line do
  begin
    F := 1;
    L := Length(AMap.Raw(Li));
    if Li = R.Head.Line then
      F := R.Head.Col;
    if Li = R.Last.Line then
      L := R.Last.EndCol - 1;
    if (F <= L) and AMap.HasComment(Li, F, L) then
      Exit(Li);
  end;
  Result := 0;
end;

// Die Argumente ab '(' AOpen: je Argument genau ein Wort, gleich dem
// Parameter an derselben Stelle. T wird das Token hinter ')'.
function ArgsPassThrough(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  const AParams: TArray<string>; out T: TRdxToken): Boolean;
var
  Close : TRdxToken;
  k     : Integer;
begin
  Result := False;
  T := Default(TRdxToken);
  Close := MatchClose(AMap, AOpen);
  if Close.Low = '' then Exit;
  T := After(AMap, AOpen);
  k := 0;
  while not SameTok(T, Close) do
  begin
    if (k >= Length(AParams)) or not T.IsWord
       or not SameIdent(T.Low, LowerCase(AParams[k])) then
      Exit;
    Inc(k);
    T := After(AMap, T);
    if T.Low = ',' then
    begin
      T := After(AMap, T);
      if SameTok(T, Close) then Exit;     // ',' vor ')'
    end
    else if not SameTok(T, Close) then
      Exit;
  end;
  if k <> Length(AParams) then Exit;
  T := After(AMap, Close);
  Result := True;
end;

// Der Rumpf ist genau die Durchreichung an den Vorfahren (s. Kopf der
// Unit)? '' oder der Grund.
function BodyReason(AMap: TRdxCodeMap; const C: TRdxIeCtx): string;
var
  T      : TRdxToken;
  Open   : TRdxToken;
  IsFunc : Boolean;
  Assign : Boolean;
  Ok     : Boolean;
begin
  Result := MsgStaleSuffix(_(R_IE_BODY));
  IsFunc := C.Impl.Keyword.Low = 'function';
  T := After(AMap, C.Impl.Body);
  Assign := T.Low = 'result';
  if Assign then
  begin
    T := After(AMap, T);
    if T.Low <> ':=' then Exit;
    T := After(AMap, T);
  end;
  if Assign <> IsFunc then Exit;     // Funktion ohne Zuweisung und umgekehrt
  if T.Low <> 'inherited' then Exit;
  T := After(AMap, T);
  if SameTok(T, C.Impl.EndTok) then
    Exit('');                        // 'inherited end;' ohne ';' davor
  if T.IsWord and SameIdent(T.Low, C.LowMeth) then
  begin
    T := After(AMap, T);
    if T.Low = '(' then
    begin
      // Eigene Variable fuer '(': AOpen (const, als Referenz) und das
      // out-T duerfen nicht dieselbe sein - out leert sie beim Eintritt.
      Open := T;
      Ok := ArgsPassThrough(AMap, Open, C.Params, T);
    end
    else
      Ok := Length(C.Params) = 0;    // 'inherited Name;' ruft ohne Argumente
    if not Ok then Exit;
  end
  else if T.IsWord then
    Exit;                            // eine andere Methode des Vorfahren
  if T.Low = ';' then
    T := After(AMap, T);
  if not SameTok(T, C.Impl.EndTok) then Exit;
  Result := '';
end;

{ ---- Die Klasse und die Deklaration ---- }

// Die eine Klasse mit Rumpf und darin die eine Deklaration: gleiche Art,
// nur 'override', kein Attribut, kein Default, gleiche Parameterzahl.
// '' oder der Grund.
function DeclReason(AMap: TRdxCodeMap; var C: TRdxIeCtx): string;
var
  Heads      : TArray<TRdxToken>;
  CH         : TRdxClassHead;
  W          : string;
  ImplParams : TArray<string>;
  DeclParams : TArray<string>;
  ImplShape  : string;
  DeclShape  : string;
begin
  Heads := TRdxBlocks.FindClassHeads(AMap, C.ClassPath);
  if Length(Heads) = 0 then
    Exit(_(R_IE_NO_CLASS, [LastPart(C.ClassPath)]));
  if Length(Heads) > 1 then
    Exit(_(R_IE_CLASSES, [Length(Heads), LastPart(C.ClassPath)]));
  C.ClassTok := Heads[0];
  Heads := TRdxBlocks.MemberHeads(AMap, C.ClassTok, C.Meth);
  if Length(Heads) <> 1 then
    Exit(_(R_IE_DECLS, [Length(Heads), C.Meth]));
  if TRdxBlocks.MethodDecl(AMap, Heads[0], C.Decl) <> '' then
    Exit(_(R_IE_DECL_READ, [C.Meth]));
  if C.Decl.Head.Low = KW_CLASS then
    Exit(_(R_IE_CLASS_METHOD));
  if C.Decl.Keyword.Low <> C.Impl.Keyword.Low then
    Exit(_(R_IE_DECL_KIND, [C.Meth, C.Decl.Keyword.Low, C.Impl.Keyword.Low]));
  if not HasDirective(C.Decl, [KW_OVERRIDE], W) then
    Exit(MsgStaleSuffix(_(R_IE_NO_OVERRIDE, [C.Meth])));
  for W in C.Decl.Directives do
    if W <> KW_OVERRIDE then
      Exit(_(R_IE_DIRECTIVE, [W]));
  if Before(AMap, C.Decl.Head).Low = ']' then
    Exit(_(R_IE_ATTR));
  if not EnclosingClass(AMap, C.Decl.Head, LowerCase(LastPart(C.ClassPath)),
     CH) then
    Exit(_(R_IE_DECL_READ, [C.Meth]));
  C.Vis := CH.Vis;
  DeclParams := ParamsAfter(AMap, C.Decl.NameTok, DeclShape);
  ImplParams := ParamsAfter(AMap, C.Impl.NameTok, ImplShape);
  if HasDefault(DeclShape) or HasDefault(ImplShape) then
    Exit(_(R_IE_DEFAULT));
  if (Length(ImplParams) > 0) and (Length(ImplParams) <> Length(DeclParams)) then
    Exit(_(R_IE_PARAMS, [C.Meth]));
  // Ein Kopf ohne Parameterliste uebernimmt die der Deklaration.
  if Length(ImplParams) > 0 then
    C.Params := ImplParams
  else
    C.Params := DeclParams;
  Result := '';
end;

{ ---- Der Vorfahr ---- }

// Der erste Eintrag der Vorfahrenliste hinter AClass, '' ohne Liste (dann
// TObject).
function FirstAncestor(AMap: TRdxCodeMap; const AClass: TRdxToken): string;
var
  Names : TArray<string>;
begin
  Names := TRdxBlocks.HeritageOf(AMap, AClass);
  if Length(Names) = 0 then
    Result := 'TObject'
  else
    Result := Names[0];
end;

// Vergleicht die Abschnitte von Override (C.Vis) und Vorfahr (AVis). ''
// oder der Grund.
function CompareVis(const C: TRdxIeCtx; const AAnc, AVis: string): string;
begin
  Result := '';
  if (C.Vis = '') or (AVis = '') then
  begin
    // Ohne Abschnitt nur, wenn beide gleich ohne stehen oder der Vorfahr
    // published ist - sonst haengt es an {$M+} und am Vorfahren.
    if not (((C.Vis = '') and (AVis = '')) or (AVis = 'published')) then
      Result := _(R_IE_VIS_DEFAULT, [AAnc, MsgCheckByHand]);
  end
  else if not ReachCovered(C.Vis, AVis) then
    Result := _(R_IE_VIS_WIDENS, [C.Vis, AAnc, AVis]);
end;

// Der naechste Vorfahr mit einer Methode des Namens: in der Datei, genau
// eine Deklaration, nicht abstract, mindestens so sichtbar wie das
// Override. '' oder der Grund.
function AncestorReason(AMap: TRdxCodeMap; const C: TRdxIeCtx): string;
var
  Anc     : string;
  Classes : TArray<TRdxToken>;
  Heads   : TArray<TRdxToken>;
  D       : TRdxRoutine;
  CH      : TRdxClassHead;
  W       : string;
  Steps   : Integer;
begin
  Anc := FirstAncestor(AMap, C.ClassTok);
  for Steps := 1 to MAX_ANCESTORS do
  begin
    Classes := TRdxBlocks.FindClassHeads(AMap, Anc);
    if Length(Classes) <> 1 then
      Exit(_(R_IE_VIS_UNPROVEN, [Anc, MsgCheckByHand]));
    Heads := TRdxBlocks.MemberHeads(AMap, Classes[0], C.Meth);
    if Length(Heads) > 1 then
      Exit(_(R_IE_ANC_DECLS, [Length(Heads), C.Meth, Anc]));
    if Length(Heads) = 1 then
    begin
      D := Default(TRdxRoutine);
      if (TRdxBlocks.MethodDecl(AMap, Heads[0], D) <> '')
         or not EnclosingClass(AMap, D.Head, LowerCase(LastPart(Anc)), CH) then
        Exit(_(R_IE_DECL_READ, [Anc + '.' + C.Meth]));
      if HasDirective(D, ['abstract'], W) then
        Exit(_(R_IE_ANC_ABSTRACT, [Anc]));
      Exit(CompareVis(C, Anc, CH.Vis));
    end;
    Anc := FirstAncestor(AMap, Classes[0]);
  end;
  Result := _(R_IE_ANC_CHAIN);
end;

{ TRdxInheritedEmptyFix }

class function TRdxInheritedEmptyFix.MethodNameOf(
  const AMessage: string): string;
var
  E : Integer;
begin
  Result := '';
  E := Pos(KEY_ONLY, AMessage);
  if (Pos(KEY_OVERRIDE, AMessage) = 1) and (E > Length(KEY_OVERRIDE) + 1) then
    Result := Trim(Copy(AMessage, Length(KEY_OVERRIDE) + 1,
      E - Length(KEY_OVERRIDE) - 1));
end;

class function TRdxInheritedEmptyFix.DeleteOverride(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out APlan: TRdxRoutinePlan;
  out AReason: string): Boolean;
var
  C    : TRdxIeCtx;
  Line : Integer;
begin
  APlan := Default(TRdxRoutinePlan);
  C := Default(TRdxIeCtx);
  C.Meth := MethodNameOf(AMessage);
  C.LowMeth := LowerCase(C.Meth);
  APlan.Name := C.Meth;
  if (C.Meth = '') or (Pos('.', C.Meth) > 0) then
    AReason := _(R_IE_MESSAGE)
  else
    AReason := HeadReason(AMap, ALine, C);
  if AReason = '' then
    AReason := ImplReason(AMap, C);
  if AReason = '' then
    AReason := DeclReason(AMap, C);
  if AReason = '' then
    AReason := BodyReason(AMap, C);
  if (AReason = '')
     and (DirectiveInLines(AMap, C.Impl.Head.Line, C.Impl.Last.Line)
          or DirectiveInLines(AMap, C.Decl.Head.Line, C.Decl.Last.Line)) then
    AReason := _(R_IE_DIRECTIVES);
  if AReason = '' then
  begin
    Line := CommentLine(AMap, C.Impl);
    if Line > 0 then
      AReason := _(R_IE_COMMENT, [Line, MsgDeleteByHand]);
  end;
  if AReason = '' then
    AReason := AncestorReason(AMap, C);
  if AReason = '' then
    AReason := TRdxRoutineFixes.DeleteMethodEdits(AMap, C.Decl, C.Impl,
      SPAN_125, APlan.Edits);
  if AReason <> '' then
    APlan.Edits := nil;
  Result := AReason = '';
end;

end.
