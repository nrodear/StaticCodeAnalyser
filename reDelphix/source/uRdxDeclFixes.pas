unit uRdxDeclFixes;

// reDelphix - Editorhilfen an Deklarationen, OHNE ToolsAPI und ohne Parser
// (Konzept_Editorhilfen_Recherche_2026-10-11, Charge H1 "Doku"):
//   SCA117 PublicMemberWithoutDoc: ein XMLDoc-Geruest ueber die Deklaration
//          - <summary>, <typeparam> und <param> je Name, <returns> bei
//          function (Nicos Wunsch: der Kommentar mit den Parametern).
//   SCA197 InterfaceWithoutGuid: ['{neue GUID}'] hinter den Kopf.
//   SCA149 MissingOverride: 'override;' bzw. 'reintroduce;' hinter den Kopf.
// Baustein Signatur-Leser (ReadSignature): Name, Typparameter, Parameter-
// namen, Rueckgabe und das ';' hinter dem Kopf - genutzt von SCA117 (das
// Geruest) und SCA149 (die Form der Methode und ihrer Basis). Geplant war
// er auch fuer SCA121/SCA135; SCA121 (Charge H5, uRdxResultFixes) liest den
// Kopf aber ueber TRdxRoutine.HeaderEnd (uRdxBlocks), nicht hierueber
// (Review R3-08, Charge FC: hier stand "geteilt mit SCA121, SCA135").
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche -
// der Planer prueft den Fund am aktuellen Text nach.

interface

uses
  uRdxBufferMath, uRdxCodeMap;

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
    IsClassMethod : Boolean;       // 'class' vor dem Kopfwort
    Keyword    : TRdxToken;        // procedure, function, ..., property
    Name       : string;
    TypeParams : TArray<string>;   // <T, U>
    Params     : TArray<string>;   // Namen in Reihenfolge (auch Index-Parameter)
    ParamShape : string;           // die Liste als Token-Folge, '_' je Name
    ResultShape : string;          // Token zwischen Liste und ';' (': T')
    HasResult  : Boolean;          // function oder operator mit ':'
    HeaderEnd  : TRdxToken;        // das ';' hinter dem Kopf (Routinen)
  end;

  // Die Planer an Deklarationen (SCA117, SCA197, SCA149) und der Signatur-
  // Leser: reine Textlogik auf der Code-Sicht, ohne Parser - den Vorfahren
  // sucht SCA149 im Text der Unit (wie der Detektor). Der Aufrufer
  // (uRdxFixTable, MapFix) setzt nur Kennzeichnung und Hinweis (SCA149:
  // override aendert das Verhalten); alle Sperren stehen hier.
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
    // endet oder ueber Attributzeilen ein Kommentar steht (beides sieht der
    // Detektor nicht - Doku steht dann schon da), bei einer Direktive im
    // Kopf und bei einem Kommentar VOR dem Kopf auf seiner Zeile (er
    // stuende sonst in jeder Geruestzeile).
    class function DocSkeleton(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA197: hinter den Kopf 'IFoo = interface(IBar)' auf ALine die Zeile
    // ['{...}'] mit einer frisch erzeugten GUID (CreateGUID). Keine Hilfe
    // bei generischen Interfaces (eine GUID gaelte fuer alle
    // Auspraegungen), bei stdcall/safecall/winapi/dispid im Rumpf (COM-
    // Import: die echte IID gehoert hinein, eine neue verschoebe den Fehler
    // in die Laufzeit), bei {$INTERFACES CORBA} oder {$CALLING STDCALL} in
    // der Datei, bei einer Direktive vom Kopf bis zum ersten Member (Kopf
    // unter {$IFDEF} doppelt: die GUID kaeme nur in einen Zweig).
    class function InterfaceGuid(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA149: die Direktive nach DirectiveFor(AMessage) hinter das ';' des
    // Kopfs auf ALine - in der Reihenfolge der Sprachreferenz
    // (reintroduce; overload; virtual/dynamic/override; abstract/final;
    // Aufrufkonvention; deprecated ...): 'reintroduce' direkt hinter den
    // Kopf, 'override' hinter ein vorhandenes 'overload', sonst ebenfalls
    // direkt hinter den Kopf. Keine Hilfe, wenn schon override/
    // reintroduce dasteht; 'override' nicht neben virtual/dynamic/static/
    // message/inline und nur, wenn im Rumpf der Elternklasse (der Detektor
    // sucht sie in derselben Unit) eine Methode gleichen Namens dieselbe
    // Form hat - class, Parameter ohne Namen, Rueckgabe, Aufrufkonvention
    // (der Detektor vergleicht nur Typen). 'reintroduce' nicht bei
    // generischem Vorfahren (TBase<Integer>: der Detektor haelt T und
    // Integer fuer verschieden, override waere dort der Fix).
    class function MethodDirective(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA149: der Rat aus der Meldung - 'override' bei 'missing
    // `override`' (gleiche Signatur), 'reintroduce' bei 'hides all
    // inherited' (override uebersetzte nicht), sonst '' (Meldung unbekannt).
    class function DirectiveFor(const AMessage: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo;   // TRefactorSpan.Make

const
  SPAN_117 = 'sca117';
  SPAN_197 = 'sca197';
  SPAN_149 = 'sca149';
  HEADER_WORDS: array[0..5] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', 'property');
  PARAM_MODIFIERS: array[0..3] of string = ('const', 'var', 'out', 'constref');
  // Direktiven hinter dem Kopf einer Methode (SCA149).
  METHOD_DIRECTIVES: array[0..22] of string = ('virtual', 'dynamic',
    'abstract', 'overload', 'override', 'reintroduce', 'stdcall', 'cdecl',
    'register', 'pascal', 'safecall', 'inline', 'static', 'message',
    'deprecated', 'platform', 'experimental', 'final', 'winapi', 'assembler',
    'library', 'varargs', 'noreturn');
  // Neben diesen Direktiven ist 'override' falsch bzw. nicht gemeint.
  NOT_WITH_OVERRIDE: array[0..4] of string = ('virtual', 'dynamic',
    'static', 'message', 'inline');
  // Aufrufkonventionen (Form der Methode, SCA149); ohne Angabe 'register'.
  CALL_CONVS: array[0..5] of string = ('register', 'pascal', 'cdecl',
    'stdcall', 'safecall', 'winapi');
  // Im Rumpf eines Interfaces: ein COM-Import (SCA197).
  COM_MARKERS: array[0..3] of string = ('stdcall', 'safecall', 'winapi',
    'dispid');
  // Womit der Rumpf eines Interfaces beginnt (SCA197).
  INTERFACE_BODY: array[0..3] of string = ('procedure', 'function',
    'property', 'end');
  KEY_MEMBER   = 'Public member ';
  KEY_SHADOWS  = 'missing `override`';
  KEY_HIDES    = 'hides all inherited';
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
// AShape: die ganze Liste als Token-Folge, '_' statt jedes Namens (die
// Form ohne Namen - SCA149 vergleicht sie mit der Basis).
function ParamNamesOf(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  const AClose: string; out AShape: string): TArray<string>;
var
  T    : TRdxToken;
  Scan : TRdxParamScan;
  SB   : TStringBuilder;
begin
  Result := nil;
  Scan := Default(TRdxParamScan);
  Scan.InParens := AOpen.Low = '(';
  SB := TStringBuilder.Create;
  try
    T := AOpen;
    while T.Low <> '' do
    begin
      if T.Low = AOpen.Low then
        Inc(Scan.Depth)
      else if T.Low = AClose then
        Dec(Scan.Depth);
      if ParamNameStep(Scan, T) then
      begin
        Result := Result + [Copy(AMap.Raw(T.Line), T.Col, T.Len)];
        SB.Append('_ ');
      end
      else
        SB.Append(T.Low + ' ');
      if Scan.Depth = 0 then
        Break;
      T := After(AMap, T);
    end;
    AShape := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Die Token von AFrom bis vor ATo, klein und mit ' ' verbunden.
function TokensBetween(AMap: TRdxCodeMap; const AFrom, ATo: TRdxToken): string;
var
  T  : TRdxToken;
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    T := AFrom;
    while (T.Low <> '') and ((T.Line < ATo.Line)
       or ((T.Line = ATo.Line) and (T.Col < ATo.Col))) do
    begin
      SB.Append(T.Low + ' ');
      T := After(AMap, T);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
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
  T, NameTok, Rest : TRdxToken;
begin
  Result := False;
  ASig := Default(TRdxSignature);
  AReason := R_DECL_MOVED;
  T := NextToken(AMap, ALine, 1);
  ASig.IsClassMethod := T.Low = 'class';
  if ASig.IsClassMethod then
    T := After(AMap, T);
  if (T.Line <> ALine) or not InList(T.Low, HEADER_WORDS) then Exit;
  ASig.Keyword := T;
  T := NameToken(AMap, ASig.Keyword, NameTok);
  if not NameTok.IsWord then Exit;
  ASig.Name := Copy(AMap.Raw(NameTok.Line), NameTok.Col, NameTok.Len);
  if T.Low = '<' then
  begin
    ASig.TypeParams := TypeParamsOf(AMap, T);
    T := AfterClose(AMap, T);
  end;
  if (T.Low = '(') and (ASig.Keyword.Low <> 'property') then
  begin
    ASig.Params := ParamNamesOf(AMap, T, ')', ASig.ParamShape);
    T := AfterClose(AMap, T);
  end
  else if (T.Low = '[') and (ASig.Keyword.Low = 'property') then
  begin
    ASig.Params := ParamNamesOf(AMap, T, ']', ASig.ParamShape);
    T := AfterClose(AMap, T);
  end;
  ASig.HasResult := (T.Low = ':')
    and InList(ASig.Keyword.Low, ['function', 'operator']);
  // Das ';' hinter dem Kopf (Rueckgabetyp auf Tiefe 0 dazwischen).
  Rest := T;
  while (T.Low <> '') and (T.Low <> ';') do
  begin
    if InList(T.Low, ['(', '[', '<']) then
      T := AfterClose(AMap, T)
    else
      T := After(AMap, T);
  end;
  if T.Low <> ';' then
  begin
    AReason := 'Ende des Kopfs nicht gefunden';
    Exit;
  end;
  ASig.HeaderEnd := T;
  ASig.ResultShape := TokensBetween(AMap, Rest, T);
  AReason := '';
  Result := True;
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
// weiter oben begann? Der Detektor haelt die Schlusszeile eines
// mehrzeiligen Kommentars fuer Code - vermutlich steht dort schon Doku.
function CommentEndsAbove(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Li : Integer;
begin
  Li := ALine - 1;
  while (Li >= 1) and (Trim(AMap.Raw(Li)) = '') do
    Dec(Li);
  Result := (Li >= 1) and AMap.StartsInside(Li);
end;

// Beginnt die Zeile ALine mit einem XMLDoc-Kommentar '///'?
function XmlDocLine(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  L   : string;
  Col : Integer;
begin
  L := AMap.Raw(ALine);
  Col := SkipBlanks(L, 1);
  Result := (AMap.LineCommentCol(ALine) = Col) and (Copy(L, Col, 3) = '///');
end;

// Steht ueber Attributzeilen ('[MVCPath(..)]' allein auf der Zeile) schon
// XMLDoc? Der Detektor bricht an der Attributzeile ab und meldet die
// Deklaration trotzdem (delphimvcframework) - ein Geruest gaebe einen
// zweiten summary-Block. Andere Kommentare darueber sind meist
// Abschnittsueberschriften ('// ==== Tests ===='); dort hilft das Geruest.
function DocAboveAttributes(AMap: TRdxCodeMap; ALine: Integer): Boolean;
var
  Li    : Integer;
  T     : string;
  Attrs : Boolean;
begin
  Attrs := False;
  Li := ALine - 1;
  while Li >= 1 do
  begin
    T := Trim(AMap.Raw(Li));
    if (T <> '') and ((T[1] <> '[') or AMap.StartsInside(Li)) then
      Break;
    Attrs := Attrs or (T <> '');
    Dec(Li);
  end;
  Result := Attrs and (Li >= 1) and XmlDocLine(AMap, Li);
end;

// Darf ueber ALine ein Geruest? '' oder der Grund; ASig ist der Kopf.
function DocReason(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  out ASig: TRdxSignature): string;
var
  R : string;
begin
  ASig := Default(TRdxSignature);
  if AMap.StartsInside(ALine) then
    Exit('die Zeile beginnt in einem Kommentar oder String');
  if not TRdxDeclFixes.ReadSignature(AMap, ALine, ASig, R) then
    Exit(R);
  if not SameText(ASig.Name, MemberNameOf(AMessage)) then
    Exit(R_DECL_MOVED);
  if CommentEndsAbove(AMap, ALine) then
    Exit('darueber endet ein Kommentar ueber Zeilen - der Detektor sieht '
      + 'dessen Schlusszeile als Code; Doku von Hand pruefen');
  if DocAboveAttributes(AMap, ALine) then
    Exit('ueber den Attributen steht schon XMLDoc (///) - der Detektor '
      + 'bricht an der Attributzeile ab und sieht sie nicht');
  if DirectiveBefore(AMap, ALine, ASig.HeaderEnd) then
    Exit(R_DIRECTIVE_IN_HEAD);
  Result := '';
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
  Sig    : TRdxSignature;
  L      : string;
  First  : TRdxToken;
  Indent : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := DocReason(AMap, ALine, AMessage, Sig);
  if AReason <> '' then Exit;
  L := AMap.Raw(ALine);
  First := NextToken(AMap, ALine, 1);
  // Die Einrueckung ist der Leerraum vor dem Kopf - nicht alles bis zum
  // ersten Token: ein Kommentar davor ('{ alt } procedure Run;') kaeme
  // sonst in jede Geruestzeile (Review Quick-Fix-Units 2026-10-14).
  Indent := IndentOf(L);
  if Length(Indent) + 1 <> First.Col then
  begin
    AReason := 'vor dem Kopf steht auf seiner Zeile ein Kommentar - das '
      + 'Geruest gehoert darueber, von Hand setzen';
    Exit;
  end;
  AEdit.Span := TRefactorSpan.Make(SPAN_117, ALine, 1, ALine, First.EndCol);
  AEdit.Expected := Copy(L, 1, First.EndCol - 1);
  AEdit.NewText := SkeletonText(Sig, Indent) + AEdit.Expected;
  Result := True;
end;

{ ---- SCA197 ---- }

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
    ANext := AfterClose(AMap, ANext);
    ALast := Before(AMap, ANext);
  end;
  if ANext.Low = ';' then
    Result := 'Vorwaertsdeklaration - sie traegt keine GUID'
  else if ANext.Low = '[' then
    Result := 'hinter dem Kopf steht schon ''['' (GUID oder Attribut) - Fund '
      + 'veraltet? Datei neu pruefen'
  else if not InList(ANext.Low, INTERFACE_BODY) then
    Result := 'hinter dem Kopf beginnt kein Interface-Rumpf (Kopf unter '
      + '{$IFDEF} doppelt?)';
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

// Der Text einer Direktive ab ihrem '$' bis vor '}' bzw. '*)'.
function DirectiveBody(const AFromDollar: string): string;
var
  P : Integer;
begin
  Result := AFromDollar;
  P := Pos('}', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  P := Pos('*)', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
end;

// Steht in der Datei die Direktive '{$AName ..AValue..}' (auch '(*$')?
// AName und AValue gross geschrieben.
function FileDirective(AMap: TRdxCodeMap; const AName, AValue: string): Boolean;
var
  Li, P, Start : Integer;
  U            : string;
begin
  Result := False;
  for Li := 1 to AMap.LineCount do
  begin
    // Ohne '$' keine Direktive - UpperCase nur fuer diese Zeilen (Review
    // R3-03, Charge FC: bis dahin je Zeile der Datei, zweimal je Fund).
    if Pos('$', AMap.Raw(Li)) = 0 then
      Continue;
    U := UpperCase(AMap.Raw(Li));
    P := Pos('$' + AName, U);
    if P < 2 then Continue;
    Start := P - 1;
    if (Start > 1) and (U[Start] = '*') then
      Dec(Start);
    if DirectiveAt(AMap, Li, Start)
       and (Pos(AValue, DirectiveBody(Copy(U, P, MaxInt))) > 0) then
      Exit(True);
  end;
end;

// Was in der Datei eine neue GUID verbietet: '' oder der Grund.
function FileReason(AMap: TRdxCodeMap): string;
begin
  Result := '';
  if FileDirective(AMap, 'INTERFACES', 'CORBA') then
    Result := '{$INTERFACES CORBA} in der Datei'
  else if FileDirective(AMap, 'CALLING', 'STDCALL') then
    Result := '{$CALLING STDCALL} in der Datei - ein COM-Import ist nicht '
      + 'auszuschliessen';
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
  // Der Name aus 'Interface "IFoo" has no GUID ...' (bis Charge B2S-a
  // eine eigene Kopie QuotedNameOf).
  AReason := InterfaceHeaderOn(AMap, ALine, QuotedText(AMessage, '"'), Kw);
  if AReason = '' then
    AReason := HeaderTail(AMap, Kw, Last, Next);
  if (AReason = '') and LooksLikeComImport(AMap, Next) then
    AReason := 'stdcall/safecall/winapi/dispid im Rumpf - ein COM-Import '
      + 'braucht die echte IID, keine neue GUID';
  if AReason = '' then
    AReason := FileReason(AMap);
  if (AReason = '') and DirectiveBefore(AMap, ALine, Next) then
    AReason := 'Compiler-Direktive vom Kopf bis zum ersten Member';
  if (AReason = '') and (CreateGUID(NewId) <> 0) then
    AReason := 'CreateGUID hat keine GUID geliefert';
  if AReason <> '' then Exit;
  G := '[''' + GUIDToString(NewId) + ''']';
  L := AMap.Raw(Last.Line);
  if (Next.Line > Last.Line) and not AMap.StartsInside(Last.Line + 1) then
  begin
    // Kopf am Zeilenende (ein Kommentar dahinter bleibt auf der Zeile): die
    // GUID in eine eigene Zeile, eingerueckt wie die Member darunter.
    Indent := IndentOf(AMap.Raw(ALine));
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
  Result := '';
  if Pos(KEY_SHADOWS, AMessage) > 0 then
    Result := DIRECTIVE_OVERRIDE
  else if Pos(KEY_HIDES, AMessage) > 0 then
    Result := DIRECTIVE_REINTRODUCE;
end;

// Das Wort hinter AKey in AMessage (bis zum naechsten ' '); '' ohne AKey.
function WordAfter(const AMessage, AKey: string): string;
var
  P, Q : Integer;
begin
  Result := '';
  P := Pos(AKey, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(AKey));
  Q := Pos(' ', AMessage + ' ', P);
  Result := Copy(AMessage, P, Q - P);
end;

// Die Klasse aus 'TOuter.TBase<T>.DoWork': 'TBase' (letztes Segment vor
// dem Methodennamen, ohne Typparameter).
function ClassPartOf(const AQualified: string): string;
var
  P : Integer;
begin
  Result := Copy(AQualified, 1, LastDelimiter('.', AQualified) - 1);
  P := LastDelimiter('.', Result);
  Result := Copy(Result, P + 1, MaxInt);
  P := Pos('<', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
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

// Das naechste ';' ab ATok einschliesslich; Low = '' am Dateiende.
function SemicolonFrom(AMap: TRdxCodeMap; const ATok: TRdxToken): TRdxToken;
begin
  Result := ATok;
  while (Result.Low <> '') and (Result.Low <> ';') do
    Result := After(AMap, Result);
end;

// Die Direktiven-Woerter hinter AEnd ('virtual; overload; ...') als Token.
// Liest, solange auf ein Direktivenwort (mit Argument bei message/
// deprecated) ein ';' folgt.
function DirectiveTokens(AMap: TRdxCodeMap; const AEnd: TRdxToken): TArray<TRdxToken>;
var
  T : TRdxToken;
begin
  Result := nil;
  T := After(AMap, AEnd);
  while InList(T.Low, METHOD_DIRECTIVES) do
  begin
    Result := Result + [T];
    T := SemicolonFrom(AMap, T);
    if T.Low = '' then Exit;
    T := After(AMap, T);
  end;
end;

// Die Direktiven hinter AEnd, klein (DirectiveTokens).
function DirectivesAfter(AMap: TRdxCodeMap; const AEnd: TRdxToken): TArray<string>;
var
  T : TRdxToken;
begin
  Result := nil;
  for T in DirectiveTokens(AMap, AEnd) do
    Result := Result + [T.Low];
end;

// Das ';', hinter das ADirective kommt. Reihenfolge laut Sprachreferenz
// (Methods: reintroduce; overload; virtual/dynamic/override; abstract/
// final; Aufrufkonvention; deprecated/platform ...): 'reintroduce' direkt
// hinter den Kopf AEnd (vor ein overload); 'override' hinter das ';' eines
// vorhandenen 'overload' (sonst ebenfalls hinter den Kopf) - so bleibt es
// vor abstract/final, der Aufrufkonvention und den Warn-Direktiven, die
// die Reihenfolge weiter hinten fuehrt (Review Quick-Fix-Units 2026-10-14:
// '; override; overload;' war die Form gegen die Referenz).
function DirectiveAnchor(AMap: TRdxCodeMap; const AEnd: TRdxToken;
  const ADirective: string): TRdxToken;
var
  T : TRdxToken;
begin
  Result := AEnd;
  if ADirective <> DIRECTIVE_OVERRIDE then Exit;
  for T in DirectiveTokens(AMap, AEnd) do
    if T.Low = 'overload' then
      Result := SemicolonFrom(AMap, T);
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
      Exit(Format('die Deklaration traegt %s - das passt nicht zu override '
        + '(virtual/dynamic fuehren einen eigenen Eintrag ein)', [D]));
  end;
end;

// 'AName [<..>] = class' ab T, kein Vorwaerts- ('class;') und kein
// Metaklassen-Typ ('class of'): AClass ist dann das Token 'class'.
function ClassHeadAt(AMap: TRdxCodeMap; const T: TRdxToken; const AName: string;
  out AClass: TRdxToken): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  AClass := Default(TRdxToken);
  if not (T.IsWord and SameText(T.Low, AName)) then Exit;
  N := After(AMap, T);
  if N.Low = '<' then
    N := AfterClose(AMap, N);
  if N.Low <> '=' then Exit;
  AClass := After(AMap, N);
  N := After(AMap, AClass);
  Result := (AClass.Low = 'class') and not InList(N.Low, [';', 'of']);
end;

// Der naechste Klassenkopf 'AName = class' ab Zeile ALine rueckwaerts.
function ClassHeaderBefore(AMap: TRdxCodeMap; ALine: Integer;
  const AName: string; out AClass: TRdxToken): Boolean;
var
  Li : Integer;
  T  : TRdxToken;
begin
  Result := False;
  for Li := ALine downto 1 do
  begin
    T := NextToken(AMap, Li, 1);
    while (T.Low <> '') and (T.Line = Li) do
    begin
      if ClassHeadAt(AMap, T, AName, AClass) then
        Exit(True);
      T := After(AMap, T);
    end;
  end;
end;

// Ist ein Vorfahr in der Klassenangabe hinter AClass generisch
// ('class(TBase<Integer>)')?
function GenericAncestor(AMap: TRdxCodeMap; const AClass: TRdxToken): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  T := After(AMap, AClass);
  while InList(T.Low, ['abstract', 'sealed']) do
    T := After(AMap, T);
  if T.Low <> '(' then Exit;
  while (T.Low <> '') and (T.Low <> ')') do
  begin
    if T.Low = '<' then
      Exit(True);
    T := After(AMap, T);
  end;
end;

// Tiefe im Klassenrumpf: 'end' schliesst, 'record' und geschachtelte
// Typen ('= class', '= interface' ...) oeffnen ('case' im Record hat kein
// eigenes end).
function BodyDepthStep(AMap: TRdxCodeMap; const T, APrev: TRdxToken): Integer;
begin
  Result := 0;
  if not IsKeywordAfter(T, APrev) then Exit;
  if T.Low = 'end' then
    Result := -1
  else if T.Low = 'record' then
    Result := 1
  else if (APrev.Low = '=')
     and InList(T.Low, ['class', 'object', 'interface', 'dispinterface'])
     and not InList(After(AMap, T).Low, [';', 'of']) then
    Result := 1;
end;

// Die Aufrufkonvention unter den Direktiven; ohne Angabe 'register'.
function CallConvOf(const AHave: TArray<string>): string;
var
  D : string;
begin
  Result := 'register';
  for D in AHave do
    if InList(D, CALL_CONVS) then
      Result := D;
  if Result = 'winapi' then
    Result := 'stdcall';
end;

// Die Form eines Kopfs ohne Parameternamen: class, Kopfwort, Liste,
// Rueckgabe, Aufrufkonvention.
function ShapeOf(AMap: TRdxCodeMap; const ASig: TRdxSignature): string;
begin
  Result := ASig.Keyword.Low + ' ' + ASig.ParamShape + ASig.ResultShape
    + CallConvOf(DirectivesAfter(AMap, ASig.HeaderEnd));
  if ASig.IsClassMethod then
    Result := 'class ' + Result;
end;

// Die Formen aller Methoden AName im Rumpf der Klasse ab AClass (nur Tiefe
// 1, Kopf am Zeilenanfang).
function MemberShapes(AMap: TRdxCodeMap; const AClass: TRdxToken;
  const AName: string): TArray<string>;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
  Sig     : TRdxSignature;
  R       : string;
begin
  Result := nil;
  Depth := 1;
  Prev := AClass;
  T := After(AMap, AClass);
  while (T.Low <> '') and (Depth > 0) do
  begin
    Inc(Depth, BodyDepthStep(AMap, T, Prev));
    if (Depth = 1) and (T.Col = SkipBlanks(AMap.Raw(T.Line), 1))
       and TRdxDeclFixes.ReadSignature(AMap, T.Line, Sig, R)
       and SameText(Sig.Name, AName) then
      Result := Result + [ShapeOf(AMap, Sig)];
    Prev := T;
    T := After(AMap, T);
  end;
end;

// override: im Rumpf der Elternklasse (Meldung: 'shadows virtual
// TBase.X') eine Methode X derselben Form? '' oder der Grund.
function OverrideReason(AMap: TRdxCodeMap; const AMessage: string;
  const ASig: TRdxSignature): string;
var
  Base : string;
  Cls  : TRdxToken;
  S    : string;
begin
  Base := ClassPartOf(WordAfter(AMessage, 'virtual '));
  if (Base = '') or not ClassHeaderBefore(AMap, ASig.Keyword.Line, Base, Cls) then
    Exit(Format('Elternklasse %s nicht im Text gefunden - override nicht '
      + 'pruefbar', [Base]));
  for S in MemberShapes(AMap, Cls, ASig.Name) do
    if S = ShapeOf(AMap, ASig) then
      Exit('');
  // Die Form vergleicht auch die Gruppierung: '(A, B: Integer)' und '(A:
  // Integer; B: Integer)' sind fuer den Compiler dieselbe Signatur, hier
  // zwei Formen. Die Ablehnung bleibt (lieber keine Hilfe), der Grund sagt
  // es - bis zur Review Woche G07-11 hiess es 'override uebersetzte
  // nicht', auch wenn es uebersetzte.
  Result := Format('%s.%s hat eine andere Form (class, Parameter-Modifier, '
    + 'Typen, Rueckgabe oder Aufrufkonvention) oder gruppiert nur die '
    + 'Parameter anders ("A, B: T" gegen "A: T; B: T") - override von Hand '
    + 'pruefen', [Base, ASig.Name]);
end;

// reintroduce: nicht bei generischem Vorfahren der eigenen Klasse
// (Meldung: 'Method TDerived.X ...'). '' oder der Grund.
function ReintroduceReason(AMap: TRdxCodeMap; const AMessage: string;
  const ASig: TRdxSignature): string;
var
  Own : string;
  Cls : TRdxToken;
begin
  Result := '';
  Own := ClassPartOf(WordAfter(AMessage, 'Method '));
  if (Own = '') or not ClassHeaderBefore(AMap, ASig.Keyword.Line, Own, Cls) then
    Result := Format('Klassenkopf %s nicht im Text gefunden', [Own])
  else if GenericAncestor(AMap, Cls) then
    Result := 'generischer Vorfahr - der Detektor vergleicht T mit dem '
      + 'eingesetzten Typ; override waere vielleicht der Fix, von Hand pruefen';
end;

// Der Kopf auf ALine fuer ADirective: '' oder der Grund; ASig ist der Kopf.
function HeadReason(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage, ADirective: string; out ASig: TRdxSignature): string;
var
  R : string;
begin
  ASig := Default(TRdxSignature);
  if ADirective = '' then
    Exit('Meldung unbekannt - weder "missing override" noch "hides all '
      + 'inherited"');
  if not TRdxDeclFixes.ReadSignature(AMap, ALine, ASig, R) then
    Exit(R);
  if not SameText(ASig.Name, MethodNameOf(AMessage))
     or (ASig.Keyword.Low = 'property') then
    Exit(R_DECL_MOVED);
  Result := DirectiveReason(DirectivesAfter(AMap, ASig.HeaderEnd), ADirective);
  if (Result = '') and DirectiveInLines(AMap, ALine, ASig.HeaderEnd.Line) then
    Result := R_DIRECTIVE_IN_HEAD;
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
  AReason := HeadReason(AMap, ALine, AMessage, Directive, Sig);
  if (AReason = '') and (Directive = DIRECTIVE_OVERRIDE) then
    AReason := OverrideReason(AMap, AMessage, Sig)
  else if AReason = '' then
    AReason := ReintroduceReason(AMap, AMessage, Sig);
  if AReason <> '' then Exit;
  E := DirectiveAnchor(AMap, Sig.HeaderEnd, Directive);
  AEdit.Span := TRefactorSpan.Make(SPAN_149, E.Line, E.Col, E.Line, E.EndCol);
  AEdit.Expected := ';';
  AEdit.NewText := '; ' + Directive + ';';
  Result := True;
end;

end.
