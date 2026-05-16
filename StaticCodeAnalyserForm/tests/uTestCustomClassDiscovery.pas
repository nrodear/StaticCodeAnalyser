unit uTestCustomClassDiscovery;

// Tests fuer TCustomClassDiscovery - die Auto-Discovery von Custom-Klassen
// die freigegeben werden muessen. Pre-Pass-Pipeline-Komponente vor
// uLeakDetector2 (analyser.ini -> AutoDiscoverClasses=1).
//
// Liefert zwei Listen:
//   * Instantiable - Klassen mit Ctor/Dtor ODER Create-Call -> leak-relevant
//   * StaticOnly   - keine Instanziierungs-Evidenz, vermutlich Utility-Klassen
//
// Owner-managed Parents (TForm/TFrame/TComponent/TInterfacedObject/...)
// werden vor der Klassifizierung ausgeschlossen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCustomClassDiscovery = class
  public
    // ---- Owner-Managed-Filter ---------------------------------------------
    [Test] procedure FormDescendant_IsSkipped;
    [Test] procedure FrameDescendant_IsSkipped;
    [Test] procedure InterfacedObjectDescendant_IsSkipped;
    [Test] procedure ExceptionDescendant_IsSkipped;

    // ---- Instantiable-Klassifikation --------------------------------------
    [Test] procedure ClassWithCtor_IsInstantiable;
    [Test] procedure ClassWithCreateCallInUnit_IsInstantiable;
    [Test] procedure ClassWithoutCtorOrCreate_IsStaticOnly;

    // ---- Edge / Multi-Hit -------------------------------------------------
    [Test] procedure MultipleCustomClasses_AllDiscovered;
    [Test] procedure GenericClassSuffix_StrippedBeforeParentCheck;

    // ---- API-Helper -------------------------------------------------------
    [Test] procedure IsOwnerManagedParent_DirectChecks;
  end;

implementation

uses
  System.SysUtils,
  uAstNode, uParser2,
  uCustomClassDiscovery;

// Helper: Parse + Discover + return both lists.
procedure RunDiscover(const Src: string;
  out Instantiable, StaticOnly: TArray<string>);
var
  Parser : TParser2;
  Root   : TAstNode;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(Src);
    try
      TCustomClassDiscovery.DiscoverInUnit(Root, Instantiable, StaticOnly);
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function ContainsName(const Arr: TArray<string>; const N: string): Boolean;
var S: string;
begin
  for S in Arr do
    if SameText(S, N) then Exit(True);
  Result := False;
end;

// ---- Owner-Managed-Filter ---------------------------------------------------

procedure TTestCustomClassDiscovery.FormDescendant_IsSkipped;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMyForm = class(TForm) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsFalse(ContainsName(Inst, 'TMyForm'),
    'TForm-Descendant darf nicht in Instantiable landen');
  Assert.IsFalse(ContainsName(Stat, 'TMyForm'),
    'TForm-Descendant darf nicht in StaticOnly landen');
end;

procedure TTestCustomClassDiscovery.FrameDescendant_IsSkipped;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses Vcl.Forms;'#13#10 +
  'type TMyFrame = class(TFrame) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsFalse(ContainsName(Inst, 'TMyFrame'));
  Assert.IsFalse(ContainsName(Stat, 'TMyFrame'));
end;

procedure TTestCustomClassDiscovery.InterfacedObjectDescendant_IsSkipped;
// TInterfacedObject hat Reference-Counting -> kein Leak-Risiko
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TMyService = class(TInterfacedObject) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsFalse(ContainsName(Inst, 'TMyService'));
  Assert.IsFalse(ContainsName(Stat, 'TMyService'));
end;

procedure TTestCustomClassDiscovery.ExceptionDescendant_IsSkipped;
// Exception-Hierarchie wird per raise/except verwaltet
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type ESomethingFailed = class(Exception) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsFalse(ContainsName(Inst, 'ESomethingFailed'));
  Assert.IsFalse(ContainsName(Stat, 'ESomethingFailed'));
end;

// ---- Instantiable-Klassifikation --------------------------------------------

procedure TTestCustomClassDiscovery.ClassWithCtor_IsInstantiable;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  constructor Create;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'constructor TFoo.Create; begin end;'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsTrue(ContainsName(Inst, 'TFoo'),
    'Klasse mit Konstruktor muss in Instantiable landen');
end;

procedure TTestCustomClassDiscovery.ClassWithCreateCallInUnit_IsInstantiable;
// Auch ohne expliziten Ctor zaehlt eine Klasse, wenn ein Create-Call in
// derselben Unit auftaucht.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBar = class'#13#10 +
  '  procedure DoWork;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure UseBar; var b: TBar;'#13#10 +
  'begin b := TBar.Create; end;'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsTrue(ContainsName(Inst, 'TBar'),
    'Klasse mit TBar.Create-Call muss in Instantiable landen');
end;

procedure TTestCustomClassDiscovery.ClassWithoutCtorOrCreate_IsStaticOnly;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TUtils = class'#13#10 +
  '  class procedure Helper;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'class procedure TUtils.Helper; begin end;'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsTrue(ContainsName(Stat, 'TUtils'),
    'Klasse ohne Ctor/Create muss in StaticOnly landen');
  Assert.IsFalse(ContainsName(Inst, 'TUtils'),
    'StaticOnly-Klasse darf nicht doppelt in Instantiable sein');
end;

// ---- Edge / Multi-Hit --------------------------------------------------------

procedure TTestCustomClassDiscovery.MultipleCustomClasses_AllDiscovered;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TA = class constructor Create; end;'#13#10 +
  '  TB = class constructor Create; end;'#13#10 +
  '  TC = class end;'#13#10 +     // ohne Create-Call -> StaticOnly
  'implementation'#13#10 +
  'constructor TA.Create; begin end;'#13#10 +
  'constructor TB.Create; begin end;'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  Assert.IsTrue(ContainsName(Inst, 'TA'));
  Assert.IsTrue(ContainsName(Inst, 'TB'));
  Assert.IsTrue(ContainsName(Stat, 'TC'));
end;

procedure TTestCustomClassDiscovery.GenericClassSuffix_StrippedBeforeParentCheck;
// `TBox<T> = class(TInterfacedObject)` muss als InterfacedObject erkannt
// werden, auch wenn der Parent-TypeRef Generic-Suffixe enthaelt.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type TBox<T> = class(TInterfacedObject)'#13#10 +
  '  procedure Add(Item: T);'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBox<T>.Add(Item: T); begin end;'#13#10 +
  'end.';
var Inst, Stat: TArray<string>;
begin
  RunDiscover(SRC, Inst, Stat);
  // TInterfacedObject-Descendant -> beide Listen leer fuer TBox
  Assert.IsFalse(ContainsName(Inst, 'TBox'),
    'TBox<T>:TInterfacedObject darf nicht als leakable klassifiziert werden');
end;

// ---- API-Helper --------------------------------------------------------------

procedure TTestCustomClassDiscovery.IsOwnerManagedParent_DirectChecks;
begin
  // Direkter Helper-Test - die OWNER_MANAGED-Liste muss alle dokumentierten
  // Basis-Klassen kennen.
  Assert.IsTrue(TCustomClassDiscovery.IsOwnerManagedParent('TForm'));
  Assert.IsTrue(TCustomClassDiscovery.IsOwnerManagedParent('TFrame'));
  Assert.IsTrue(TCustomClassDiscovery.IsOwnerManagedParent('TDataModule'));
  Assert.IsTrue(TCustomClassDiscovery.IsOwnerManagedParent('TInterfacedObject'));
  Assert.IsTrue(TCustomClassDiscovery.IsOwnerManagedParent('Exception'));
  // Case-Insensitivity (Pascal-Konvention)
  Assert.IsTrue(TCustomClassDiscovery.IsOwnerManagedParent('tform'));
  Assert.IsTrue(TCustomClassDiscovery.IsOwnerManagedParent('TFORM'));
  // Nicht owner-managed -> False
  Assert.IsFalse(TCustomClassDiscovery.IsOwnerManagedParent('TObject'));
  Assert.IsFalse(TCustomClassDiscovery.IsOwnerManagedParent('TStringList'));
  Assert.IsFalse(TCustomClassDiscovery.IsOwnerManagedParent(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCustomClassDiscovery);

end.
