unit uTestRdxDeclFixes;

// Editorhilfen an Deklarationen (uRdxDeclFixes) auf Text - ohne Parser,
// ohne Detektor (laeuft in reDelphix.Test UND im FPC-Pruefstand):
//   Signatur-Leser (Gruppen, Defaults, untypisiert, Generika mit
//          Einschraenkungen, Property-Index, Kopf ueber Zeilen, '&Type'),
//   SCA117 Doku-Geruest (param/typeparam/returns, Attribut darueber;
//          Name veraltet, Kommentar ueber Zeilen darueber, XMLDoc ueber
//          den Attributen, Direktive im bzw. hinter dem Kopf),
//   SCA197 GUID (eigene Zeile, inline, Vorfahr, Kommentar dahinter;
//          generisch, Vorwaerts, '[' schon da, COM/winapi, CORBA,
//          CALLING, Kopf unter {$IFDEF} doppelt),
//   SCA149 override/reintroduce (Form gegen die Basis, vor vorhandene
//          Direktiven; schon da, neben virtual/inline, andere Form, Basis
//          fehlt, generischer Vorfahr, unbekannte Meldung).
// Die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (Fixture 8, nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDeclFixes = class
  public
    [Test] procedure Signature_Reader;
    [Test] procedure Sca117_Skeleton;
    [Test] procedure Sca117_Forms;
    [Test] procedure Sca117_Refusals;
    [Test] procedure Sca197_Guid;
    [Test] procedure Sca197_Refusals;
    [Test] procedure Sca149_Directive;
    [Test] procedure Sca149_Refusals;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxBufferMath, uRdxCodeMap, uRdxDeclFixes;

type
  TRdxDeclKind = (dkDoc, dkGuid, dkDirective);

const
  GUID_1 = '{11111111-2222-3333-4444-555555555555}';

// ---- Helfer ----

function Apply(const ASource: string; const AEdit: TRdxEdit): string;
var
  Bytes : TBytes;
  Edits : TArray<TRdxEdit>;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
begin
  SetLength(Edits, 1);
  Edits[0] := AEdit;
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  Assert.IsTrue(PlanByteEdits(Bytes, Edits, Plan, Err), Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

// Teile mit ASep verbunden (TStringBuilder: string.Join kennt FPC nicht).
function JoinWith(const ASep: string; const AParts: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AParts) do
    begin
      if i > 0 then SB.Append(ASep);
      SB.Append(AParts[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Zeilen mit CRLF verbunden.
function Join(const ALines: array of string): string;
begin
  Result := JoinWith(#13#10, ALines);
end;

// Die frisch erzeugte GUID hinter '[''' als GUID geprueft und durch GUID_1
// ersetzt - so bleiben die Vergleiche fest.
function FixedGuid(const AText: string): string;
var
  P : Integer;
  G : string;
begin
  Result := AText;
  P := Pos('[''{', AText);
  if P = 0 then Exit;
  G := Copy(AText, P + 2, Length(GUID_1));
  Assert.AreEqual(G, GUIDToString(StringToGUID(G)), 'eine GUID');
  Result := StringReplace(AText, G, GUID_1, []);
end;

// Die Hilfe AKind fuer Zeile ALine: neuer Text oder '' bei Ablehnung.
function Fix(AKind: TRdxDeclKind; const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    case AKind of
      dkDoc:
        Ok := TRdxDeclFixes.DocSkeleton(Map, ALine, AMessage, E, AReason);
      dkGuid:
        Ok := TRdxDeclFixes.InterfaceGuid(Map, ALine, AMessage, E, AReason);
    else
      Ok := TRdxDeclFixes.MethodDirective(Map, ALine, AMessage, E, AReason);
    end;
    if Ok then
      Result := FixedGuid(Apply(ASource, E));
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Namen mit ',' verbunden.
function Commas(const ANames: TArray<string>): string;
begin
  Result := JoinWith(',', ANames);
end;

// Signatur der Zeile ALine als 'Name|T1,T2|P1,P2|R' ('R' = mit Rueckgabe).
function SigText(const ASource: string; ALine: Integer): string;
var
  SL     : TStringList;
  Map    : TRdxCodeMap;
  Sig    : TRdxSignature;
  Reason : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if not TRdxDeclFixes.ReadSignature(Map, ALine, Sig, Reason) then
      Exit('FEHLER ' + Reason);
    Result := Sig.Name + '|' + Commas(Sig.TypeParams) + '|'
      + Commas(Sig.Params) + '|';
    if Sig.HasResult then
      Result := Result + 'R';
  finally
    Map.Free;
    SL.Free;
  end;
end;

function DocMsg(const AName: string): string;
begin
  Result := Format('Public member %s has no documentation comment above its '
    + 'declaration. Recommended: a /// XMLDoc block, a { ... } or (* ... *) '
    + 'descriptive comment, or one or more // lines directly above '
    + 'explaining purpose + contract.', [AName]);
end;

function GuidMsg(const AName: string): string;
begin
  Result := Format('Interface "%s" has no GUID - Supports() and '
    + 'QueryInterface() cannot ask for it at run time. Add one with '
    + 'Ctrl+Shift+G.', [AName]);
end;

function ShadowMsg(const AName: string): string;
begin
  Result := Format('Method TDerived.%s shadows virtual TBase.%s - missing '
    + '`override` (W1010)', [AName, AName]);
end;

function HidesMsg(const AName: string): string;
begin
  Result := Format('Method TDerived.%s hides all inherited TBase.%s overloads '
    + '(W1010) - signatures differ, so use `overload` or `reintroduce`; '
    + '`override` would not compile', [AName, AName]);
end;

// Eine Klasse im interface-Teil; ALines sind die Member (ab Zeile 6).
function InClass(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type', '  TFoo = class', '  public'])
    + #13#10 + Join(ALines) + #13#10
    + Join(['  end;', 'implementation', 'end.']);
end;

const
  DERIVED = '  TDerived = class(TBase)';

// TBase mit den Membern ABase, darunter die Klasse ADerivedHead mit
// ADerived - deren erste Zeile ist Zeile 9 + Length(ABase).
function Hierarchy(const ABase: array of string; const ADerivedHead: string;
  const ADerived: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'type', '  TBase = class', '  public'])
    + #13#10 + Join(ABase) + #13#10
    + Join(['  end;', ADerivedHead, '  public']) + #13#10 + Join(ADerived)
    + #13#10 + Join(['  end;', 'implementation', 'end.']);
end;

// ---- Signatur-Leser ----

procedure TTestRdxDeclFixes.Signature_Reader;
begin
  Assert.AreEqual('Run|||', SigText(InClass(['    procedure Run;']), 6));
  Assert.AreEqual('Find||AId,AUser|R', SigText(InClass(['    function Find('
    + 'const AId: Integer; out AUser: TUser): Boolean;']), 6));
  // Gruppen, Default, untypisiert, Attribut am Parameter.
  Assert.AreEqual('SetRange||A,B,S,Buf,P|', SigText(InClass(['    procedure '
    + 'SetRange(A, B: Integer; const S: string = ''x''; var Buf; '
    + '[ref] const P: TPoint);']), 6));
  // Generika, Kopf ueber zwei Zeilen.
  Assert.AreEqual('Map|T,U|AItem|R', SigText(InClass(['    function Map<T: '
    + 'class; U>(', '      const AItem: T): TList<U>;']), 6));
  // Einschraenkungen durch ',' (Korpus: delphimvcframework BodyAs<T: class,
  // constructor>) sind keine Typparameter; ',' ohne ':' trennt Parameter.
  Assert.AreEqual('Pick|T,U,V||R', SigText(InClass(['    function Pick<T, U: '
    + 'class, constructor; V>: T;']), 6));
  // Escapte Bezeichner: der Name ohne '&'.
  Assert.AreEqual('Log||Type,E|', SigText(InClass(['    procedure Log(const '
    + '&Type: Integer; E: TObject);']), 6));
  // Property mit Index bzw. ohne.
  Assert.AreEqual('Items||Index|', SigText(InClass(['    property Items[Index: '
    + 'Integer]: string read GetItem; default;']), 6));
  Assert.AreEqual('Count|||', SigText(InClass(['    property Count: Integer '
    + 'read FCount;']), 6));
  Assert.AreEqual('Create||AOwner|', SigText(InClass(['    class constructor '
    + 'Create(AOwner: TObject);']), 6));
end;

// ---- SCA117 ----

procedure TTestRdxDeclFixes.Sca117_Skeleton;
var
  R : string;
begin
  // Das Katalog-Beispiel (ohne Text im summary).
  Assert.AreEqual(InClass(['    /// <summary></summary>', '    procedure Run;']),
    Fix(dkDoc, InClass(['    procedure Run;']), 6, DocMsg('Run'), R), R);
  Assert.AreEqual(InClass(['    /// <summary></summary>',
      '    /// <param name="AId"></param>', '    /// <param name="AUser"></param>',
      '    /// <returns></returns>',
      '    function Find(const AId: Integer; out AUser: TUser): Boolean;']),
    Fix(dkDoc, InClass(['    function Find(const AId: Integer; out AUser: TUser): '
      + 'Boolean;']), 6, DocMsg('Find'), R), R);
end;

procedure TTestRdxDeclFixes.Sca117_Forms;
var
  R : string;
begin
  // Generika und Kopf ueber zwei Zeilen.
  Assert.AreEqual(InClass(['    /// <summary></summary>',
      '    /// <typeparam name="T"></typeparam>',
      '    /// <param name="AItem"></param>', '    /// <returns></returns>',
      '    function Map<T>(', '      const AItem: T): T;']),
    Fix(dkDoc, InClass(['    function Map<T>(', '      const AItem: T): T;']), 6,
      DocMsg('Map'), R), R);
  // Property mit Index: summary + param.
  Assert.AreEqual(InClass(['    /// <summary></summary>',
      '    /// <param name="Index"></param>',
      '    property Items[Index: Integer]: string read GetItem;']),
    Fix(dkDoc, InClass(['    property Items[Index: Integer]: string read GetItem;']),
      6, DocMsg('Items'), R), R);
  // Ein Attribut darueber bleibt darueber - der Detektor liest nur die Zeile
  // direkt ueber der Deklaration.
  Assert.AreEqual(InClass(['    [Weak]', '    /// <summary></summary>',
      '    procedure Run;']),
    Fix(dkDoc, InClass(['    [Weak]', '    procedure Run;']), 7, DocMsg('Run'), R),
      R);
  // Tabs.
  Assert.AreEqual(InClass([#9#9'/// <summary></summary>', #9#9'procedure Run;']),
    Fix(dkDoc, InClass([#9#9'procedure Run;']), 6, DocMsg('Run'), R), R);
end;

procedure TTestRdxDeclFixes.Sca117_Refusals;
var
  R : string;
begin
  // Die Meldung nennt einen anderen Namen.
  Assert.AreEqual('', Fix(dkDoc, InClass(['    procedure Run;']), 6, DocMsg('Stop'),
    R));
  Assert.IsTrue(Pos('verschoben', R) > 0, R);
  // Darueber endet ein Kommentar ueber Zeilen - Doku steht schon da.
  Assert.AreEqual('', Fix(dkDoc, InClass(['    { Startet', '      den Lauf }',
    '    procedure Run;']), 8, DocMsg('Run'), R));
  Assert.IsTrue(Pos('Kommentar ueber Zeilen', R) > 0, R);
  // Direktive im Kopf; hinter dessen ';' sperrt sie nicht.
  Assert.AreEqual('', Fix(dkDoc, InClass(['    procedure Run({$IFDEF X}A: '
    + 'Integer{$ENDIF});']), 6, DocMsg('Run'), R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
  Assert.AreEqual(InClass(['    /// <summary></summary>',
      '    procedure Run; {$IFDEF X} override; {$ENDIF}']),
    Fix(dkDoc, InClass(['    procedure Run; {$IFDEF X} override; {$ENDIF}']),
      6, DocMsg('Run'), R), R);
  // Kein Kopf auf der Zeile.
  Assert.AreEqual('', Fix(dkDoc, InClass(['    FCount: Integer;']), 6,
    DocMsg('FCount'), R));
  Assert.IsTrue(Pos('verschoben', R) > 0, R);
  // Ein Kommentar VOR dem Kopf auf seiner Zeile kaeme sonst in jede
  // Geruestzeile (Review Quick-Fix-Units 2026-10-14).
  Assert.AreEqual('', Fix(dkDoc, InClass(['    { alt } procedure Run;']), 6,
    DocMsg('Run'), R));
  Assert.IsTrue(Pos('vor dem Kopf', R) > 0, R);
  Assert.AreEqual(InClass(['    /// <summary></summary>',
      '    procedure Run; { alt }']),
    Fix(dkDoc, InClass(['    procedure Run; { alt }']), 6, DocMsg('Run'), R),
    'hinter dem Kopf stoert er nicht: ' + R);
  // XMLDoc ueber den Attributen (auch mit Leerzeile dazwischen) sieht der
  // Detektor nicht - kein zweiter summary-Block.
  Assert.AreEqual('', Fix(dkDoc, InClass(['    /// <summary>Lauf</summary>',
    '    [Weak]', '', '    [Volatile]', '    procedure Run;']), 10,
    DocMsg('Run'), R));
  Assert.IsTrue(Pos('Attribut', R) > 0, R);
  // Eine Abschnittsueberschrift bzw. Direktive ueber dem Attribut ist keine
  // Doku des Members - das Geruest kommt.
  Assert.AreEqual(InClass(['    // ==== Tests ====', '    [Test]',
      '    /// <summary></summary>', '    procedure Run;']),
    Fix(dkDoc, InClass(['    // ==== Tests ====', '    [Test]',
      '    procedure Run;']), 8, DocMsg('Run'), R), R);
  Assert.AreEqual(InClass(['    {$IFDEF X}', '    [Weak]',
      '    /// <summary></summary>', '    procedure Run;', '    {$ENDIF}']),
    Fix(dkDoc, InClass(['    {$IFDEF X}', '    [Weak]', '    procedure Run;',
      '    {$ENDIF}']), 8, DocMsg('Run'), R), R);
end;

// ---- SCA197 ----

procedure TTestRdxDeclFixes.Sca197_Guid;
var
  R : string;
begin
  // Eigene Zeile, eingerueckt wie die Member.
  Assert.AreEqual(Join(['type', '  IFoo = interface', '    [''' + GUID_1 + ''']',
      '    procedure Run;', '  end;']),
    Fix(dkGuid, Join(['type', '  IFoo = interface', '    procedure Run;',
      '  end;']), 2, GuidMsg('IFoo'), R), R);
  // Mit Vorfahr und Kommentar dahinter (er bleibt auf der Kopfzeile).
  Assert.AreEqual(Join(['type', '  IFoo = interface(IInterface) // Kern',
      '    [''' + GUID_1 + ''']', '    procedure Run;', '  end;']),
    Fix(dkGuid, Join(['type', '  IFoo = interface(IInterface) // Kern',
      '    procedure Run;', '  end;']), 2, GuidMsg('IFoo'), R), R);
  // Member auf der Kopfzeile: inline.
  Assert.AreEqual(Join(['type', '  IFoo = interface [''' + GUID_1 + ''']'
      + ' procedure Run; end;']),
    Fix(dkGuid, Join(['type', '  IFoo = interface procedure Run; end;']), 2,
      GuidMsg('IFoo'), R), R);
end;

procedure TTestRdxDeclFixes.Sca197_Refusals;
var
  R : string;
begin
  Assert.AreEqual('', Fix(dkGuid, Join(['type', '  IList<T> = interface',
    '    function Get: T;', '  end;']), 2, GuidMsg('IList'), R));
  Assert.IsTrue(Pos('generisch', R) > 0, R);
  Assert.AreEqual('', Fix(dkGuid, Join(['type', '  IFoo = interface;']), 2,
    GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('Vorwaerts', R) > 0, R);
  Assert.AreEqual('', Fix(dkGuid, Join(['type', '  IFoo = interface',
    '    [''' + GUID_1 + ''']', '  end;']), 2, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('GUID oder Attribut', R) > 0, R);
  // COM-Import: safecall bzw. winapi im Rumpf.
  Assert.AreEqual('', Fix(dkGuid, Join(['type', '  IFoo = interface(IDispatch)',
    '    function Get: Integer; safecall;', '  end;']), 2, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('COM', R) > 0, R);
  Assert.AreEqual('', Fix(dkGuid, Join(['type', '  IFoo = interface',
    '    function Get: Integer; winapi;', '  end;']), 2, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('COM', R) > 0, R);
  // Datei-Direktiven, auch in der Form '(*$..*)'; CORBA nur IN der
  // Direktive (nicht im Kommentar dahinter).
  Assert.AreEqual('', Fix(dkGuid, Join(['{$INTERFACES CORBA}', 'type',
    '  IFoo = interface', '    procedure Run;', '  end;']), 3, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('CORBA', R) > 0, R);
  Assert.AreEqual('', Fix(dkGuid, Join(['(*$INTERFACES CORBA*)', 'type',
    '  IFoo = interface', '    procedure Run;', '  end;']), 3, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('CORBA', R) > 0, R);
  Assert.AreEqual('', Fix(dkGuid, Join(['{$CALLING STDCALL}', 'type',
    '  IFoo = interface', '    procedure Run;', '  end;']), 3, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('CALLING', R) > 0, R);
  Assert.AreEqual(Join(['{$INTERFACES COM} // nicht CORBA', 'type',
      '  IFoo = interface', '    [''' + GUID_1 + ''']', '    procedure Run;',
      '  end;']),
    Fix(dkGuid, Join(['{$INTERFACES COM} // nicht CORBA', 'type',
      '  IFoo = interface', '    procedure Run;', '  end;']), 3, GuidMsg('IFoo'),
      R), R);
  // Kopf unter {$IFDEF} doppelt: die GUID kaeme nur in einen Zweig.
  Assert.AreEqual('', Fix(dkGuid, Join(['type', '  {$IFDEF A}',
    '  IFoo = interface(IBar)', '  {$ELSE}', '  IFoo = interface(IBaz)',
    '  {$ENDIF}', '    procedure Run;', '  end;']), 3, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('kein Interface-Rumpf', R) > 0, R);
  Assert.AreEqual('', Fix(dkGuid, Join(['type', '  {$IFDEF A}',
    '  IFoo = interface(IBar)', '  {$ELSE}', '  IFoo = interface(IBaz)',
    '  {$ENDIF}', '    procedure Run;', '  end;']), 5, GuidMsg('IFoo'), R));
  Assert.IsTrue(Pos('Direktive', R) > 0, R);
end;

// ---- SCA149 ----

procedure TTestRdxDeclFixes.Sca149_Directive;
var
  R : string;
begin
  // Die Meldung waehlt: 'shadows' -> override, wenn die Basis dieselbe Form
  // hat (Parameternamen duerfen abweichen, Defaults nicht).
  Assert.AreEqual(Hierarchy(['    procedure DoWork(const A: string; '
      + 'B: Integer = 0); virtual;'], DERIVED, ['    procedure DoWork(const X: '
      + 'string; Y: Integer = 0); override;']),
    Fix(dkDirective, Hierarchy(['    procedure DoWork(const A: string; '
      + 'B: Integer = 0); virtual;'], DERIVED, ['    procedure DoWork(const X: '
      + 'string; Y: Integer = 0);']), 10, ShadowMsg('DoWork'), R), R);
  // class-Methode; die Basis ueberlaedt (eine Form passt), ein Record im
  // Rumpf der Basis stoert die Tiefe nicht.
  Assert.AreEqual(Hierarchy(['    type TPair = record A, B: Integer; end;',
      '    class function DoWork: TObject; overload; virtual;',
      '    class function DoWork(A: Integer): TObject; overload; virtual;'],
      DERIVED, ['    class function DoWork: TObject; override;']),
    Fix(dkDirective, Hierarchy(['    type TPair = record A, B: Integer; end;',
      '    class function DoWork: TObject; overload; virtual;',
      '    class function DoWork(A: Integer): TObject; overload; virtual;'],
      DERIVED, ['    class function DoWork: TObject;']), 12,
      ShadowMsg('DoWork'), R), R);
  // 'hides' -> reintroduce vor vorhandene Direktiven (vor overload ist
  // Pflicht), auch neben virtual (eine neue virtuelle Methode).
  Assert.AreEqual(Hierarchy(['    procedure DoWork; virtual;'], DERIVED,
      ['    procedure DoWork(A: Integer); reintroduce; overload; // x']),
    Fix(dkDirective, Hierarchy(['    procedure DoWork; virtual;'], DERIVED,
      ['    procedure DoWork(A: Integer); overload; // x']), 10,
      HidesMsg('DoWork'), R), R);
  Assert.AreEqual(Hierarchy(['    procedure DoWork; virtual;'], DERIVED,
      ['    procedure DoWork(A: Integer); reintroduce; virtual;']),
    Fix(dkDirective, Hierarchy(['    procedure DoWork; virtual;'], DERIVED,
      ['    procedure DoWork(A: Integer); virtual;']), 10, HidesMsg('DoWork'),
      R), R);
  Assert.AreEqual(DIRECTIVE_OVERRIDE, TRdxDeclFixes.DirectiveFor(ShadowMsg('X')));
  Assert.AreEqual(DIRECTIVE_REINTRODUCE,
    TRdxDeclFixes.DirectiveFor(HidesMsg('X')));
  Assert.AreEqual('', TRdxDeclFixes.DirectiveFor('Method TDerived.X is odd'));
  // 'override' neben 'overload': hinter das overload (Reihenfolge der
  // Sprachreferenz: overload vor der Bindung; Review Quick-Fix-Units
  // 2026-10-14), vor deprecated/stdcall dagegen direkt hinter den Kopf.
  Assert.AreEqual(Hierarchy(['    procedure DoWork; overload; virtual;'],
      DERIVED, ['    procedure DoWork; overload; override; // x']),
    Fix(dkDirective, Hierarchy(['    procedure DoWork; overload; virtual;'],
      DERIVED, ['    procedure DoWork; overload; // x']), 10,
      ShadowMsg('DoWork'), R), R);
  Assert.AreEqual(Hierarchy(['    procedure DoWork; virtual;'], DERIVED,
      ['    procedure DoWork; override; deprecated;']),
    Fix(dkDirective, Hierarchy(['    procedure DoWork; virtual;'], DERIVED,
      ['    procedure DoWork; deprecated;']), 10, ShadowMsg('DoWork'), R), R);
  Assert.AreEqual(Hierarchy(['    procedure DoWork; overload; stdcall; virtual;'],
      DERIVED, ['    procedure DoWork; overload; override; stdcall;']),
    Fix(dkDirective, Hierarchy(['    procedure DoWork; overload; stdcall; virtual;'],
      DERIVED, ['    procedure DoWork; overload; stdcall;']), 10,
      ShadowMsg('DoWork'), R), R);
end;

procedure TTestRdxDeclFixes.Sca149_Refusals;
var
  R : string;
begin
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    procedure DoWork; '
    + 'virtual;'], DERIVED, ['    procedure DoWork; override;']), 10,
    ShadowMsg('DoWork'), R));
  Assert.IsTrue(Pos('schon override', R) > 0, R);
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    procedure DoWork; '
    + 'virtual;'], DERIVED, ['    procedure DoWork; virtual;']), 10,
    ShadowMsg('DoWork'), R));
  Assert.IsTrue(Pos('virtual', R) > 0, R);
  // inline und override schliessen sich aus.
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    function Get: Integer; '
    + 'virtual;'], DERIVED, ['    function Get: Integer; inline;']), 10,
    ShadowMsg('Get'), R));
  Assert.IsTrue(Pos('inline', R) > 0, R);
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    procedure DoWork; '
    + 'virtual;'], DERIVED, ['    procedure Other;']), 10, ShadowMsg('DoWork'),
    R));
  Assert.IsTrue(Pos('verschoben', R) > 0, R);
  // Der Detektor vergleicht nur Typen: Modifier, class und Aufrufkonvention
  // pruefen erst wir - sonst uebersetzte override nicht.
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    procedure DoWork(A: '
    + 'string); virtual;'], DERIVED, ['    procedure DoWork(const A: string);']),
    10, ShadowMsg('DoWork'), R));
  Assert.IsTrue(Pos('andere Form', R) > 0, R);
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    class procedure DoWork; '
    + 'virtual;'], DERIVED, ['    procedure DoWork;']), 10, ShadowMsg('DoWork'),
    R));
  Assert.IsTrue(Pos('andere Form', R) > 0, R);
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    procedure DoWork; '
    + 'virtual;'], DERIVED, ['    procedure DoWork; stdcall;']), 10,
    ShadowMsg('DoWork'), R));
  Assert.IsTrue(Pos('andere Form', R) > 0, R);
  // Ohne Basis im Text kein override.
  Assert.AreEqual('', Fix(dkDirective, InClass(['    procedure DoWork;']), 6,
    ShadowMsg('DoWork'), R));
  Assert.IsTrue(Pos('nicht im Text', R) > 0, R);
  // Generischer Vorfahr: T gegen Integer haelt der Detektor fuer
  // verschieden - reintroduce deckte dort den Fehler zu.
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    procedure DoWork(A: '
    + 'Integer); virtual;'], '  TDerived = class(TBase<Integer>)',
    ['    procedure DoWork(A: Integer);']), 10, HidesMsg('DoWork'), R));
  Assert.IsTrue(Pos('generisch', R) > 0, R);
  // Unbekannte Meldung.
  Assert.AreEqual('', Fix(dkDirective, Hierarchy(['    procedure DoWork; '
    + 'virtual;'], DERIVED, ['    procedure DoWork;']), 10,
    'Method TDerived.DoWork is odd', R));
  Assert.IsTrue(Pos('unbekannt', R) > 0, R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDeclFixes);

end.
