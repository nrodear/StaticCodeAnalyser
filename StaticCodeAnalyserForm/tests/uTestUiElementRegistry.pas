unit uTestUiElementRegistry;

// Tests fuer uUiElementRegistry - Arbeitsplan UiArchitektur, Punkte T.2/T.3.
//
// WARUM DAS UEBERHAUPT GEHT: Die Registry kennt keine ToolsAPI. Sie haelt
// eine geordnete Liste und ruft zwei Methoden - reine Delphi-Logik, damit
// im Suchpfad des Testprojekts und pruefbar. Das ist der belegte Vorteil
// von DelphiLints Fassade gegenueber GExperts und CnWizards: dort laesst
// sich die Abbausymmetrie testen, hier nur lesen.
//
// WAS HIER GEPRUEFT WIRD, ist genau das, was am laufenden Plugin teuer
// waere und was die Messung vom 2026-08-10 als Problem belegt hat: dass
// abgemeldet wird, was angemeldet wurde, in exakt umgekehrter Folge, und
// dass ein defektes Element die uebrigen nicht mitreisst.
//
// UNGEDECKT bleibt der echte ToolsAPI-Kontakt der einzelnen Elemente - das
// steht so auch im Arbeitsplan und wird durch Messungen kompensiert, nicht
// durch Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUiElementRegistry = class
  public
    // Die Reihenfolge kommt aus SortKey, nicht aus der Aufrufreihenfolge.
    [Test] procedure RegisterOrderFollowsSortKeyNotInsertion;
    // Der Kern: abgemeldet wird exakt rueckwaerts.
    [Test] procedure UnregisterRunsInExactReverseOrder;
    // Abgeschaltete Elemente werden weder an- noch abgemeldet.
    [Test] procedure DisabledElementIsSkippedEntirely;
    // Ein defektes Element darf die uebrigen nicht mitreissen.
    [Test] procedure FailingRegistrationDoesNotStopTheOthers;
    // Und es darf hinterher nicht abgemeldet werden.
    [Test] procedure ElementThatFailedToRegisterIsNotUnregistered;
    // Auch beim Abmelden laeuft der Rest weiter.
    [Test] procedure FailingUnregistrationDoesNotStopTheOthers;
    // Zweimal abmelden ist erlaubt und tut beim zweiten Mal nichts.
    [Test] procedure UnregisterAllIsIdempotent;
    // T.2 - Schluesselableitung fuer den Not-Aus.
    [Test] procedure EnabledKeyStripsEverythingButLettersAndDigits;
    [Test] procedure EnabledKeyIsEmptyWhenNothingUsableRemains;
    // Ein kaputter Not-Aus-Schalter darf nichts stilllegen.
    [Test] procedure ThrowingEnabledFuncCountsAsOnAndIsLogged;
  end;

  // A.3: der wiederverwendbare Adapter, mit dem die elf Plugin-Elemente
  // ohne je eigene Klasse in die Registry kommen.
  [TestFixture]
  TTestDelegatedUiElement = class
  public
    // Der Adapter reicht wirklich an die uebergebenen Prozeduren durch.
    [Test] procedure DelegatesRegisterAndUnregister;
    // nil-Unregister ist ein gueltiger Zustand, kein Fehler.
    [Test] procedure NilUnregisterIsANoOp;
    // nil-EnabledFunc heisst immer an.
    [Test] procedure NilEnabledFuncMeansOn;
    // Eine False liefernde EnabledFunc laesst die Registry ueberspringen.
    [Test] procedure EnabledFuncFalseSkipsTheElement;
    // Ohne Register-Prozedur knallt es am Aufrufort, nicht spaeter still.
    [Test] procedure NilRegisterProcRaisesAtCreation;
  end;

implementation

// noinspection-file BeginEndRequired, ClassPerFile, DuplicateString
// Fixture-Cluster: die Attrappe gehoert in dieselbe Datei wie die Tests,
// die sie benutzen (ClassPerFile); einzeilige Wenn-Zweige und die
// wiederholten Elementnamen 'A'/'B'/'C' sind in einer Testfolge lesbarer
// als Konstanten, deren Aufloesung man beim Lesen nachschlagen muesste.

uses
  System.SysUtils, System.Classes, uUiElementRegistry;

type
  /// <summary> Absichtlicher Fehlschlag einer Attrappe. </summary>
  /// <remarks>
  ///   Eigene Klasse statt eines nackten Exception: der Test soll den
  ///   Unterschied zwischen "meine Attrappe hat wie geplant geworfen" und
  ///   "irgendetwas anderes ist schiefgegangen" ausdruecken koennen.
  /// </remarks>
  EFakeElementFailure = class(Exception);

  /// <summary> Was eine Attrappe absichtlich falsch machen soll. </summary>
  TFakeBehaviour  = (fbDisabled, fbFailRegister, fbFailUnregister);
  TFakeBehaviours = set of TFakeBehaviour;

  /// <summary>
  ///   Attrappe eines UI-Elements. Schreibt jeden Aufruf in ein
  ///   gemeinsames Protokoll - daran wird die REIHENFOLGE geprueft, nicht
  ///   an einem Zaehler. Ein Zaehler wuerde vorwaerts wie rueckwaerts
  ///   dieselbe Zahl liefern, und genau darum geht es hier.
  /// </summary>
  TFakeElement = class(TInterfacedObject, IIDEUiElement)
  private
    FName      : string;
    FSortKey   : Integer;
    FBehaviour : TFakeBehaviours;
    FLog       : TStrings;
  public
    /// <summary> Verhalten als Menge statt als drei Boolean-Parameter -
    ///   am Aufrufort steht dann [fbFailRegister] und nicht True,True,False.
    /// </summary>
    constructor Create(ALog: TStrings; const AName: string;
      ASortKey: Integer; ABehaviour: TFakeBehaviours = []);
    /// <summary> Technischer Name, zugleich Protokolleintrag. </summary>
    function Name: string;
    /// <summary> Position in der Anmeldereihenfolge. </summary>
    function SortKey: Integer;
    /// <summary> False, wenn fbDisabled gesetzt ist. </summary>
    function IsEnabled: Boolean;
    /// <summary> Protokolliert '+Name', wirft bei fbFailRegister. </summary>
    procedure RegisterElement;
    /// <summary> Protokolliert '-Name', wirft bei fbFailUnregister. </summary>
    procedure UnregisterElement;
  end;

constructor TFakeElement.Create(ALog: TStrings; const AName: string;
  ASortKey: Integer; ABehaviour: TFakeBehaviours);
begin
  inherited Create;
  FLog       := ALog;
  FName      := AName;
  FSortKey   := ASortKey;
  FBehaviour := ABehaviour;
end;

function TFakeElement.Name: string;
begin
  Result := FName;
end;

function TFakeElement.SortKey: Integer;
begin
  Result := FSortKey;
end;

function TFakeElement.IsEnabled: Boolean;
begin
  Result := not (fbDisabled in FBehaviour);
end;

procedure TFakeElement.RegisterElement;
begin
  FLog.Add('+' + FName);
  if fbFailRegister in FBehaviour then
    raise EFakeElementFailure.Create('Anmelden absichtlich fehlgeschlagen');
end;

procedure TFakeElement.UnregisterElement;
begin
  FLog.Add('-' + FName);
  if fbFailUnregister in FBehaviour then
    raise EFakeElementFailure.Create('Abmelden absichtlich fehlgeschlagen');
end;

procedure TTestUiElementRegistry.RegisterOrderFollowsSortKeyNotInsertion;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    // Absichtlich verkehrt herum eingefuegt.
    R.Add(TFakeElement.Create(L, 'C', 30));
    R.Add(TFakeElement.Create(L, 'A', 10));
    R.Add(TFakeElement.Create(L, 'B', 20));
    R.RegisterAll;
    Assert.AreEqual('+A'#13#10'+B'#13#10'+C'#13#10, L.Text,
      'SortKey muss die Aufrufreihenfolge schlagen');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestUiElementRegistry.UnregisterRunsInExactReverseOrder;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TFakeElement.Create(L, 'A', 10));
    R.Add(TFakeElement.Create(L, 'B', 20));
    R.Add(TFakeElement.Create(L, 'C', 30));
    R.RegisterAll;
    L.Clear;
    R.UnregisterAll;
    Assert.AreEqual('-C'#13#10'-B'#13#10'-A'#13#10, L.Text,
      'Abmelden muss exakt rueckwaerts laufen - im Plugin lief es vorwaerts');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestUiElementRegistry.DisabledElementIsSkippedEntirely;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TFakeElement.Create(L, 'A', 10));
    R.Add(TFakeElement.Create(L, 'Aus', 20, [fbDisabled]));
    R.Add(TFakeElement.Create(L, 'C', 30));
    R.RegisterAll;
    R.UnregisterAll;
    Assert.AreEqual('+A'#13#10'+C'#13#10'-C'#13#10'-A'#13#10, L.Text,
      'Ein abgeschaltetes Element darf weder an- noch abgemeldet werden');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestUiElementRegistry.FailingRegistrationDoesNotStopTheOthers;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TFakeElement.Create(L, 'A', 10));
    R.Add(TFakeElement.Create(L, 'Kaputt', 20, [fbFailRegister]));
    R.Add(TFakeElement.Create(L, 'C', 30));
    R.RegisterAll;
    Assert.AreEqual('+A'#13#10'+Kaputt'#13#10'+C'#13#10, L.Text,
      'C muss trotz der Ausnahme in Kaputt noch angemeldet werden');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestUiElementRegistry.ElementThatFailedToRegisterIsNotUnregistered;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TFakeElement.Create(L, 'A', 10));
    R.Add(TFakeElement.Create(L, 'Kaputt', 20, [fbFailRegister]));
    R.RegisterAll;
    L.Clear;
    R.UnregisterAll;
    Assert.AreEqual('-A'#13#10, L.Text,
      'Ein Element in unbekanntem Zustand abzumelden waere geraten');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestUiElementRegistry.FailingUnregistrationDoesNotStopTheOthers;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TFakeElement.Create(L, 'A', 10));
    R.Add(TFakeElement.Create(L, 'Kaputt', 20, [fbFailUnregister]));
    R.Add(TFakeElement.Create(L, 'C', 30));
    R.RegisterAll;
    L.Clear;
    R.UnregisterAll;
    Assert.AreEqual('-C'#13#10'-Kaputt'#13#10'-A'#13#10, L.Text,
      'Bricht der Abbau in der Mitte ab, bleibt der Rest an der IDE haengen');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestUiElementRegistry.UnregisterAllIsIdempotent;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TFakeElement.Create(L, 'A', 10));
    R.RegisterAll;
    R.UnregisterAll;
    L.Clear;
    R.UnregisterAll;
    Assert.AreEqual('', L.Text, 'Zweites UnregisterAll darf nichts tun');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestUiElementRegistry.EnabledKeyStripsEverythingButLettersAndDigits;
begin
  Assert.AreEqual('Element.LineHighlighter',
                  UiElementEnabledKey('Line Highlighter'));
  Assert.AreEqual('Element.SonarOptions2',
                  UiElementEnabledKey('Sonar-Options #2'));
  Assert.AreEqual('Element.AboutBox', UiElementEnabledKey('AboutBox'));
end;

procedure TTestUiElementRegistry.EnabledKeyIsEmptyWhenNothingUsableRemains;
begin
  Assert.AreEqual('', UiElementEnabledKey(''));
  Assert.AreEqual('', UiElementEnabledKey('   '));
  Assert.AreEqual('', UiElementEnabledKey('-.:#'));
end;

type
  // Attrappe mit werfendem Schalter - nur fuer den einen Test darunter.
  TThrowingEnabledElement = class(TInterfacedObject, IIDEUiElement)
  private
    FLog : TStrings;
  public
    constructor Create(ALog: TStrings);
    function Name: string;
    function SortKey: Integer;
    function IsEnabled: Boolean;
    procedure RegisterElement;
    procedure UnregisterElement;
  end;

constructor TThrowingEnabledElement.Create(ALog: TStrings);
begin
  inherited Create;
  FLog := ALog;
end;

function TThrowingEnabledElement.Name: string;
begin
  Result := 'Wackelschalter';
end;

function TThrowingEnabledElement.SortKey: Integer;
begin
  Result := 10;
end;

function TThrowingEnabledElement.IsEnabled: Boolean;
begin
  raise EFakeElementFailure.Create('Schalter absichtlich kaputt');
end;

procedure TThrowingEnabledElement.RegisterElement;
begin
  FLog.Add('+Wackelschalter');
end;

procedure TThrowingEnabledElement.UnregisterElement;
begin
  FLog.Add('-Wackelschalter');
end;

procedure TTestUiElementRegistry.ThrowingEnabledFuncCountsAsOnAndIsLogged;
var
  L, Diag : TStringList;
  R       : TUiElementRegistry;
begin
  L    := TStringList.Create;
  Diag := TStringList.Create;
  R    := TUiElementRegistry.Create;
  try
    R.OnLog := procedure(const M: string) begin Diag.Add(M); end;
    R.Add(TThrowingEnabledElement.Create(L));
    R.RegisterAll;
    Assert.AreEqual('+Wackelschalter'#13#10, L.Text,
      'Kaputter Schalter darf das Element nicht stilllegen');
    Assert.IsTrue(Diag.Text.Contains('IsEnabled wirft'),
      'Der Fehler muss im Protokoll stehen, nicht verschwinden');
  finally
    R.Free;
    Diag.Free;
    L.Free;
  end;
end;

{ TTestDelegatedUiElement }

procedure TTestDelegatedUiElement.DelegatesRegisterAndUnregister;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TDelegatedUiElement.Create('Ding', 10,
      procedure begin L.Add('+Ding'); end,
      procedure begin L.Add('-Ding'); end));
    R.RegisterAll;
    R.UnregisterAll;
    Assert.AreEqual('+Ding'#13#10'-Ding'#13#10, L.Text);
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestDelegatedUiElement.NilUnregisterIsANoOp;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TDelegatedUiElement.Create('NurAufbau', 10,
      procedure begin L.Add('+NurAufbau'); end,
      nil));
    R.RegisterAll;
    R.UnregisterAll;
    Assert.AreEqual('+NurAufbau'#13#10, L.Text,
      'nil-Unregister heisst "nichts abzubauen" und darf nicht knallen');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestDelegatedUiElement.NilEnabledFuncMeansOn;
var
  E : IIDEUiElement;
begin
  E := TDelegatedUiElement.Create('Immer', 10, procedure begin end, nil);
  Assert.IsTrue(E.IsEnabled, 'nil-EnabledFunc muss "immer an" bedeuten');
end;

procedure TTestDelegatedUiElement.EnabledFuncFalseSkipsTheElement;
var
  L : TStringList;
  R : TUiElementRegistry;
begin
  L := TStringList.Create;
  R := TUiElementRegistry.Create;
  try
    R.Add(TDelegatedUiElement.Create('Aus', 10,
      procedure begin L.Add('+Aus'); end,
      procedure begin L.Add('-Aus'); end,
      function: Boolean begin Result := False; end));
    R.RegisterAll;
    R.UnregisterAll;
    Assert.AreEqual('', L.Text,
      'Abgeschaltet heisst: weder an- noch abgemeldet');
  finally
    R.Free;
    L.Free;
  end;
end;

procedure TTestDelegatedUiElement.NilRegisterProcRaisesAtCreation;
begin
  Assert.WillRaise(
    procedure
    begin
      TDelegatedUiElement.Create('Tot', 10, nil, nil);
    end,
    EArgumentNilException,
    'Ein Element ohne Register-Prozedur ist ein Fehler am Aufrufort');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUiElementRegistry);
  TDUnitX.RegisterTestFixture(TTestDelegatedUiElement);

end.
