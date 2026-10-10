unit uRdxDeclFixes;

// reDelphix - Editorhilfen an Deklarationen, OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Recherche_2026-10-11, Charge H1 "Doku"):
//   SCA117 PublicMemberWithoutDoc: ein XMLDoc-Geruest ueber die Deklaration
//          - <summary>, <typeparam> und <param> je Name, <returns> bei
//          function (Nicos Wunsch: der Kommentar mit den Parametern).
//   SCA197 InterfaceWithoutGuid: ['{neue GUID}'] hinter den Kopf.
//   SCA149 MissingOverride: 'override;' bzw. 'reintroduce;' hinter den Kopf.
// Baustein Signatur-Leser (ReadSignature): Name, Typparameter, Parameter-
// namen, Rueckgabe und das ';' hinter dem Kopf - geteilt mit spaeteren
// Hilfen (SCA121 Result := Default(T), SCA135).
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  System.SysUtils,
  uRefactorInfo, uRdxBufferMath, uRdxCodeMap;

const
  // SCA117: die Zeilen des Geruests (Platzhalter leer - der Nutzer fuellt
  // sie; ein 'TODO' riefe SCA019).
  DOC_SUMMARY  = '/// <summary></summary>';
  DOC_PARAM    = '/// <param name="%s"></param>';
  DOC_TYPEPARAM = '/// <typeparam name="%s"></typeparam>';
  DOC_RETURNS  = '/// <returns></returns>';
  // SCA149: die Direktive je Lage.
  DIRECTIVE_OVERRIDE    = 'override';
  DIRECTIVE_REINTRODUCE = 'reintroduce';

type
  // Ein Routinen- oder Property-Kopf (ReadSignature).
  TRdxSignature = record
    Keyword    : TRdxToken;        // procedure, function, ..., property
    Name       : string;
    TypeParams : TArray<string>;   // <T, U>
    Params     : TArray<string>;   // Namen in Reihenfolge (auch Index-Parameter)
    HasResult  : Boolean;          // function (bzw. Property mit Typ)
    HeaderEnd  : TRdxToken;        // das ';' hinter dem Kopf (Routinen)
  end;

  TRdxDeclFixes = class
  public
    // Der Kopf, der auf ALine beginnt ('class' davor erlaubt): procedure,
    // function, constructor, destructor, operator oder property. Liest bis
    // zum ';' auf Klammertiefe 0 (bei property bis zum Ende der Typangabe).
    class function ReadSignature(AMap: TRdxCodeMap; ALine: Integer;
      out ASig: TRdxSignature; out AReason: string): Boolean; static;

    // SCA117: das Geruest ueber die Zeile ALine, eingerueckt wie sie. Der
    // Name muss der aus der Meldung ('Public member X has no ...') sein.
    // Keine Hilfe, wenn die Zeile davor in einem Kommentar ueber Zeilen
    // endet (die Schlusszeile haelt der Detektor fuer Code - Doku steht
    // dann schon da), bei einer Direktive im Kopf.
    class function DocSkeleton(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA197: hinter den Kopf 'IFoo = interface(IBar)' auf ALine die Zeile
    // ['{...}'] mit einer frisch erzeugten GUID (CreateGUID). Keine Hilfe
    // bei generischen Interfaces (eine GUID gaelte fuer alle
    // Auspraegungen), bei stdcall/safecall/dispid im Rumpf (COM-Import:
    // die echte IID gehoert hinein, eine neue verschoebe den Fehler in die
    // Laufzeit), bei {$INTERFACES CORBA} in der Datei.
    class function InterfaceGuid(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA149: die Direktive nach DirectiveFor(AMessage) direkt hinter das
    // ';' des Kopfs auf ALine (vor vorhandene Direktiven - 'reintroduce'
    // muss vor 'overload' stehen). Keine Hilfe, wenn schon override/
    // reintroduce dasteht; 'override' nicht neben virtual/dynamic/static/
    // message.
    class function MethodDirective(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA149: der Rat aus der Meldung - 'override' bei 'missing
    // `override`' (gleiche Signatur), sonst 'reintroduce' ('signatures
    // differ': override uebersetzte nicht).
    class function DirectiveFor(const AMessage: string): string; static;
  end;

implementation

const
  SPAN_117 = 'sca117';
  SPAN_197 = 'sca197';
  SPAN_149 = 'sca149';
  HEADER_WORDS: array[0..5] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', 'property');
  PARAM_MODIFIERS: array[0..3] of string = ('const', 'var', 'out', 'constref');
  // Direktiven hinter dem Kopf einer Methode (SCA149).
  METHOD_DIRECTIVES: array[0..18] of string = ('virtual', 'dynamic',
    'abstract', 'overload', 'override', 'reintroduce', 'stdcall', 'cdecl',
    'register', 'pascal', 'safecall', 'inline', 'static', 'message',
    'deprecated', 'platform', 'experimental', 'final', 'winapi');
  // Neben diesen Direktiven ist 'override' falsch bzw. nicht gemeint.
  NOT_WITH_OVERRIDE: array[0..3] of string = ('virtual', 'dynamic',
    'static', 'message');
  // Im Rumpf eines Interfaces: ein COM-Import (SCA197).
  COM_MARKERS: array[0..2] of string = ('stdcall', 'safecall', 'dispid');
  KEY_MEMBER   = 'Public member ';
  KEY_SHADOWS  = 'missing `override`';
  R_DECL_MOVED = 'keine passende Deklaration auf der gemeldeten Zeile - '
    + 'Zeile verschoben? Datei neu pruefen';
  R_DIRECTIVE_IN_HEAD = 'Compiler-Direktive im Kopf';

type
  // Zustand der Leser ParamNamesOf und TypeParamsOf auf Klammertiefe 1.
  TRdxParamScan = record
    InParens : Boolean;    // Liste in '(...)' - dort ist '[' ein Attribut
    Depth    : Integer;
    Brackets : Integer;    // Attribut '[ref]' in '(...)'
    InType   : Boolean;    // hinter ':' bis zum naechsten ';' (Typ bzw.
                           // Einschraenkungen)
  end;

{ ---- Signatur-Leser ---- }

// Das Token hinter der schliessenden Klammer zu AOpen ('(' oder '[' oder
// '<'); Low = '' am Dateiende.
function AfterGroup(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  const AClose: string): TRdxToken;
var
  Depth : Integer;
begin
  Depth := 0;
  Result := AOpen;
  while Result.Low <> '' do
  begin
    if Result.Low = AOpen.Low then
      Inc(Depth)
    else if Result.Low = AClose then
      Dec(Depth);
    Result := After(AMap, Result);
    if Depth = 0 then
      Exit;
  end;
end;

// Ein Token auf Tiefe 1 der Typparameter (hinter APrev): True, wenn es ein
// Name ist. Hinter ':' bis zum naechsten ';' stehen Einschraenkungen, auch
// durch ',' getrennt ('<T: class, constructor>').
function TypeParamStep(var AScan: TRdxParamScan;
  const T, APrev: TRdxToken): Boolean;
begin
  Result := False;
  if AScan.Depth <> 1 then Exit;
  if T.Low = ':' then
    AScan.InType := True
  else if T.Low = ';' then
    AScan.InType := False
  else
    Result := not AScan.InType and T.IsWord
      and InList(APrev.Low, ['<', ',', ';']);
end;

// Namen einer Gruppe von Typparametern '<T, U: class, constructor; V>' ab
// AOpen: die Woerter direkt hinter '<', ',' und ';' ausserhalb der
// Einschraenkungen.
function TypeParamsOf(AMap: TRdxCodeMap; const AOpen: TRdxToken): TArray<string>;
var
  T, Prev : TRdxToken;
  Scan    : TRdxParamScan;
begin
  Result := nil;
  Scan := Default(TRdxParamScan);
  Prev := Default(TRdxToken);
  T := AOpen;
  while T.Low <> '' do
  begin
    if T.Low = '<' then
      Inc(Scan.Depth)
    else if T.Low = '>' then
      Dec(Scan.Depth)
    else if TypeParamStep(Scan, T, Prev) then
      Result := Result + [Copy(AMap.Raw(T.Line), T.Col, T.Len)];
    if Scan.Depth = 0 then
      Exit;
    Prev := T;
    T := After(AMap, T);
  end;
end;

// Ein Token auf Tiefe 1 der Parameterliste: True, wenn es ein Name ist.
function ParamNameStep(var AScan: TRdxParamScan; const T: TRdxToken): Boolean;
begin
  Result := False;
  if AScan.Depth <> 1 then Exit;
  if T.Low = ';' then
    AScan.InType := False
  else if T.Low = ':' then
    AScan.InType := True
  else if AScan.InParens and (T.Low = '[') then
    Inc(AScan.Brackets)
  else if AScan.InParens and (T.Low = ']') then
    Dec(AScan.Brackets)
  else
    Result := not AScan.InType and (AScan.Brackets = 0) and T.IsWord
      and not InList(T.Low, PARAM_MODIFIERS);
end;

// Parameternamen in '(...)' bzw. '[...]' ab AOpen: je Gruppe (getrennt
// durch ';' auf Tiefe 1) die Woerter vor dem ':' - ohne const/var/out/
// constref und ohne Attribute '[ref]'. Ohne ':' (untypisiert) alle Woerter.
function ParamNamesOf(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  const AClose: string): TArray<string>;
var
  T    : TRdxToken;
  Scan : TRdxParamScan;
begin
  Result := nil;
  Scan := Default(TRdxParamScan);
  Scan.InParens := AOpen.Low = '(';
  T := AOpen;
  while T.Low <> '' do
  begin
    if T.Low = AOpen.Low then
      Inc(Scan.Depth)
    else if T.Low = AClose then
      Dec(Scan.Depth);
    if Scan.Depth = 0 then
      Exit;
    if ParamNameStep(Scan, T) then
      Result := Result + [Copy(AMap.Raw(T.Line), T.Col, T.Len)];
    T := After(AMap, T);
  end;
end;

// Der Name hinter dem Kopfwort und was direkt darauf folgt.
function NameToken(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
  out AName: TRdxToken): TRdxToken;
begin
  AName := After(AMap, AKeyword);
  Result := After(AMap, AName);
end;

class function TRdxDeclFixes.ReadSignature(AMap: TRdxCodeMap; ALine: Integer;
  out ASig: TRdxSignature; out AReason: string): Boolean;
var
  T, NameTok : TRdxToken;
begin
  Result := False;
  ASig := Default(TRdxSignature);
  AReason := R_DECL_MOVED;
  T := NextToken(AMap, ALine, 1);
  if T.Low = 'class' then
    T := After(AMap, T);
  if (T.Line <> ALine) or not InList(T.Low, HEADER_WORDS) then Exit;
  ASig.Keyword := T;
  T := NameToken(AMap, ASig.Keyword, NameTok);
  if not NameTok.IsWord then Exit;
  ASig.Name := Copy(AMap.Raw(NameTok.Line), NameTok.Col, NameTok.Len);
  if T.Low = '<' then
  begin
    ASig.TypeParams := TypeParamsOf(AMap, T);
    T := AfterGroup(AMap, T, '>');
  end;
  if (T.Low = '(') and (ASig.Keyword.Low <> 'property') then
  begin
    ASig.Params := ParamNamesOf(AMap, T, ')');
    T := AfterGroup(AMap, T, ')');
  end
  else if (T.Low = '[') and (ASig.Keyword.Low = 'property') then
  begin
    ASig.Params := ParamNamesOf(AMap, T, ']');
    T := AfterGroup(AMap, T, ']');
  end;
  ASig.HasResult := (T.Low = ':')
    and InList(ASig.Keyword.Low, ['function', 'operator']);
  // Das ';' hinter dem Kopf (Rueckgabetyp auf Tiefe 0 dazwischen).
  while (T.Low <> '') and (T.Low <> ';') do
  begin
    if InList(T.Low, ['(', '[', '<']) then
      T := AfterGroup(AMap, T, Copy(')]>', Pos(T.Low, '([<'), 1))
    else
      T := After(AMap, T);
  end;
  if T.Low <> ';' then
  begin
    AReason := 'Ende des Kopfs nicht gefunden';
    Exit;
  end;
  ASig.HeaderEnd := T;
  AReason := '';
  Result := True;
end;

// Eine Direktive zwischen den Zeilen AFrom und ATo?
function DirectiveInLines(AMap: TRdxCodeMap; AFrom, ATo: Integer): Boolean;
var
  Li, Co : Integer;
begin
  Result := False;
  for Li := AFrom to ATo do
    for Co := 1 to Length(AMap.Raw(Li)) do
      if DirectiveAt(AMap, Li, Co) then
        Exit(True);
end;

// Eine Direktive ab Zeile ALine bis vor das Token AEnd? Dahinter zaehlt
// nicht ('...; {$IFDEF X} override; {$ENDIF}' laesst den Kopf gleich).
function DirectiveBefore(AMap: TRdxCodeMap; ALine: Integer;
  const AEnd: TRdxToken): Boolean;
var
  Li, Co, Last : Integer;
begin
  Result := False;
  for Li := ALine to AEnd.Line do
  begin
    Last := Length(AMap.Raw(Li));
    if Li = AEnd.Line then
      Last := AEnd.Col - 1;
    for Co := 1 to Last do
      if DirectiveAt(AMap, Li, Co) then
        Exit(True);
  end;
end;

{ ---- SCA117 ---- }

// Den Namen aus 'Public member X has no documentation ...'.
function MemberNameOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(KEY_MEMBER, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(KEY_MEMBER));
  Q := P;
  while (Q <= Length(AMessage)) and (AMessage[Q] <> ' ') do
    Inc(Q);
  Result := Copy(AMessage, P, Q - P);
end;

// Endet die naechste nicht leere Zeile ueber ALine in einem Kommentar, der
// weiter oben begann? Dann steht dort schon Doku (der Detektor haelt die
// Schlusszeile eines mehrzeiligen Kommentars fuer Code).
function CommentEndsAbove(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Li : Integer;
begin
  Li := ALine - 1;
  while (Li >= 1) and (Trim(AMap.Raw(Li)) = '') do
    Dec(Li);
  Result := (Li >= 1) and AMap.StartsInside(Li);
end;

// Das Geruest als Text: je Zeile AIndent, die Zeile und #10.
function SkeletonText(const ASig: TRdxSignature; const AIndent: string): string;
var
  SB : TStringBuilder;
  S  : string;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(AIndent + DOC_SUMMARY + #10);
    for S in ASig.TypeParams do
      SB.Append(AIndent + Format(DOC_TYPEPARAM, [S]) + #10);
    for S in ASig.Params do
      SB.Append(AIndent + Format(DOC_PARAM, [S]) + #10);
    if ASig.HasResult then
      SB.Append(AIndent + DOC_RETURNS + #10);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRdxDeclFixes.DocSkeleton(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Sig   : TRdxSignature;
  L     : string;
  First : TRdxToken;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if AMap.StartsInside(ALine) then
    AReason := 'die Zeile beginnt in einem Kommentar oder String'
  else if ReadSignature(AMap, ALine, Sig, AReason)
     and not SameText(Sig.Name, MemberNameOf(AMessage)) then
    AReason := R_DECL_MOVED;
  if (AReason = '') and CommentEndsAbove(AMap, ALine) then
    AReason := 'darueber endet ein Kommentar ueber Zeilen - die Doku steht '
      + 'schon da (der Detektor sieht deren Schlusszeile als Code)';
  if (AReason = '') and DirectiveBefore(AMap, ALine, Sig.HeaderEnd) then
    AReason := R_DIRECTIVE_IN_HEAD;
  if AReason <> '' then Exit;
  L := AMap.Raw(ALine);
  First := NextToken(AMap, ALine, 1);
  AEdit.Span := TRefactorSpan.Make(SPAN_117, ALine, 1, ALine, First.EndCol);
  AEdit.Expected := Copy(L, 1, First.EndCol - 1);
  AEdit.NewText := SkeletonText(Sig, Copy(L, 1, First.Col - 1))
    + AEdit.Expected;
  Result := True;
end;

{ ---- SCA197 ---- }

// Den Namen aus 'Interface "IFoo" has no GUID ...'.
function QuotedNameOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos('"', AMessage);
  Q := Pos('"', AMessage, P + 1);
  if (P > 0) and (Q > P + 1) then
    Result := Copy(AMessage, P + 1, Q - P - 1);
end;

// 'AName = interface' auf ALine: das Token 'interface'. '' oder der Grund.
function InterfaceHeaderOn(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string; out AKeyword: TRdxToken): string;
var
  T, Eq, Kw : TRdxToken;
begin
  AKeyword := Default(TRdxToken);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    Eq := After(AMap, T);
    Kw := After(AMap, Eq);
    if SameText(T.Low, AName) and (Eq.Low = '<') then
      Exit('generisches Interface - eine GUID gaelte fuer alle '
        + 'Auspraegungen (Supports verwechselte sie)');
    if SameText(T.Low, AName) and (Eq.Low = '=') and (Kw.Low = 'interface') then
    begin
      AKeyword := Kw;
      Exit('');
    end;
    T := Eq;
  end;
  Result := R_DECL_MOVED;
end;

// Das letzte Token des Kopfs (interface oder die ')' der Vorfahren) und
// das Token dahinter. '' oder der Grund.
function HeaderTail(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
  out ALast, ANext: TRdxToken): string;
begin
  Result := '';
  ALast := AKeyword;
  ANext := After(AMap, AKeyword);
  if ANext.Low = '(' then
  begin
    ANext := AfterGroup(AMap, ANext, ')');
    ALast := Before(AMap, ANext);
  end;
  if ANext.Low = ';' then
    Result := 'Vorwaertsdeklaration - sie traegt keine GUID'
  else if ANext.Low = '[' then
    Result := 'das Interface hat schon eine GUID - Fund veraltet? Datei neu '
      + 'pruefen';
end;

// Steht im Rumpf (bis zum ersten 'end') ein COM-Merkmal?
function LooksLikeComImport(AMap: TRdxCodeMap; const AFrom: TRdxToken): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := AFrom;
  while (T.Low <> '') and (T.Low <> 'end') do
  begin
    if InList(T.Low, COM_MARKERS) then
      Exit(True);
    T := After(AMap, T);
  end;
end;

// {$INTERFACES CORBA} irgendwo in der Datei?
function CorbaInterfaces(AMap: TRdxCodeMap): Boolean;
var
  Li, P : Integer;
begin
  Result := False;
  for Li := 1 to AMap.LineCount do
  begin
    P := Pos('{$INTERFACES', UpperCase(AMap.Raw(Li)));
    if (P > 0) and DirectiveAt(AMap, Li, P)
       and (Pos('CORBA', UpperCase(AMap.Raw(Li))) > P) then
      Exit(True);
  end;
end;

class function TRdxDeclFixes.InterfaceGuid(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Kw, Last, Next : TRdxToken;
  L, Indent, G   : string;
  NewId          : TGUID;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := InterfaceHeaderOn(AMap, ALine, QuotedNameOf(AMessage), Kw);
  if AReason = '' then
    AReason := HeaderTail(AMap, Kw, Last, Next);
  if (AReason = '') and LooksLikeComImport(AMap, Next) then
    AReason := 'stdcall/safecall/dispid im Rumpf - ein COM-Import braucht die '
      + 'echte IID, keine neue GUID';
  if (AReason = '') and CorbaInterfaces(AMap) then
    AReason := '{$INTERFACES CORBA} in der Datei';
  if (AReason = '') and DirectiveInLines(AMap, ALine, Last.Line) then
    AReason := R_DIRECTIVE_IN_HEAD;
  if (AReason = '') and (CreateGUID(NewId) <> 0) then
    AReason := 'CreateGUID hat keine GUID geliefert';
  if AReason <> '' then Exit;
  G := '[''' + GUIDToString(NewId) + ''']';
  L := AMap.Raw(Last.Line);
  if (Next.Line > Last.Line) and not AMap.StartsInside(Last.Line + 1) then
  begin
    // Kopf am Zeilenende (ein Kommentar dahinter bleibt auf der Zeile): die
    // GUID in eine eigene Zeile, eingerueckt wie die Member darunter.
    Indent := Copy(AMap.Raw(ALine), 1, SkipBlanks(AMap.Raw(ALine), 1) - 1);
    AEdit.Span := TRefactorSpan.Make(SPAN_197, Last.Line, Last.Col, Last.Line,
      Length(L) + 1);
    AEdit.Expected := Copy(L, Last.Col, MaxInt);
    AEdit.NewText := AEdit.Expected + #10 + Indent
      + IndentStep(Indent, AMap.Raw(Next.Line)) + G;
  end
  else
  begin
    AEdit.Span := TRefactorSpan.Make(SPAN_197, Last.Line, Last.Col, Last.Line,
      Last.EndCol);
    AEdit.Expected := Copy(L, Last.Col, Last.Len);
    AEdit.NewText := AEdit.Expected + ' ' + G;
  end;
  Result := True;
end;

{ ---- SCA149 ---- }

class function TRdxDeclFixes.DirectiveFor(const AMessage: string): string;
begin
  if Pos(KEY_SHADOWS, AMessage) > 0 then
    Result := DIRECTIVE_OVERRIDE
  else
    Result := DIRECTIVE_REINTRODUCE;
end;

// Den Methodennamen aus 'Method TDerived.DoWork shadows ...' bzw.
// '... hides ...'.
function MethodNameOf(const AMessage: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos('Method ', AMessage);
  if P <> 1 then Exit;
  Q := Pos(' ', AMessage, P + 7);
  if Q = 0 then Exit;
  Result := Copy(AMessage, P + 7, Q - P - 7);
  P := LastDelimiter('.', Result);
  Result := Copy(Result, P + 1, MaxInt);
end;

// Die Direktiven hinter AEnd ('virtual; overload; ...'), klein. Liest,
// solange auf ein Direktivenwort (mit Argument bei message/deprecated)
// ein ';' folgt.
function DirectivesAfter(AMap: TRdxCodeMap; const AEnd: TRdxToken): TArray<string>;
var
  T : TRdxToken;
begin
  Result := nil;
  T := After(AMap, AEnd);
  while InList(T.Low, METHOD_DIRECTIVES) do
  begin
    Result := Result + [T.Low];
    while (T.Low <> '') and (T.Low <> ';') do
      T := After(AMap, T);
    if T.Low = '' then Exit;
    T := After(AMap, T);
  end;
end;

// Darf ADirective zu den vorhandenen? '' oder der Grund.
function DirectiveReason(const AHave: TArray<string>;
  const ADirective: string): string;
var
  D : string;
begin
  Result := '';
  for D in AHave do
  begin
    if (D = DIRECTIVE_OVERRIDE) or (D = DIRECTIVE_REINTRODUCE) then
      Exit(Format('die Deklaration traegt schon %s - Fund veraltet? Datei neu '
        + 'pruefen', [D]));
    if (ADirective = DIRECTIVE_OVERRIDE) and InList(D, NOT_WITH_OVERRIDE) then
      Exit(Format('%s neben override - die Methode fuehrt bewusst einen '
        + 'eigenen Eintrag ein', [D]));
  end;
end;

class function TRdxDeclFixes.MethodDirective(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Sig       : TRdxSignature;
  E         : TRdxToken;
  Directive : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Directive := DirectiveFor(AMessage);
  if ReadSignature(AMap, ALine, Sig, AReason)
     and (not SameText(Sig.Name, MethodNameOf(AMessage))
          or (Sig.Keyword.Low = 'property')) then
    AReason := R_DECL_MOVED;
  if AReason = '' then
    AReason := DirectiveReason(DirectivesAfter(AMap, Sig.HeaderEnd), Directive);
  if (AReason = '') and DirectiveInLines(AMap, ALine, Sig.HeaderEnd.Line) then
    AReason := R_DIRECTIVE_IN_HEAD;
  if AReason <> '' then Exit;
  E := Sig.HeaderEnd;
  AEdit.Span := TRefactorSpan.Make(SPAN_149, E.Line, E.Col, E.Line, E.EndCol);
  AEdit.Expected := ';';
  AEdit.NewText := '; ' + Directive + ';';
  Result := True;
end;

end.
