unit uDfmDeadEvent;

// Detektor: Toter Event-Handler im DFM.
//
// Findet Event-Bindungen wie 'OnClick = btnGoClick', deren benannte
// Methode in der zugehoerigen Form-Klasse weder als Signatur noch als
// Implementation existiert. Zur Laufzeit produziert das einen Streaming-
// Crash:
//   Error reading <name>.OnClick: 'btnGoClick' is not a method
//
// Typischer Entstehungsweg: jemand benennt eine Handler-Methode um oder
// loescht sie aus der Form-Klasse, vergisst aber den Eintrag im DFM zu
// aktualisieren. Compiler meldet das nicht (DFM wird erst zur Laufzeit
// gestreamt), Tests merken es nur wenn die Form ueberhaupt instanziiert
// wird.
//
// Schweregrad: lsError, FindingType: ftBug.
//
// Ancestor-Gate (Real-World-Audit 2026-07-31): DFM-Streaming loest Handler
// ueber die GESAMTE Klassenhierarchie auf (TObject.MethodAddress). Gemeldet
// wird deshalb nur, wenn die Vererbungskette VOLLSTAENDIG aufgeloest ist -
// siehe IsAncestorChainResolved.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uFormBinder;

type
  TDfmDeadEventDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function FirstAncestorToken(const ATypeRefList: string): string;
// ClassNode.TypeRef ist eine Space-separierte Liste ('TForm IFoo') - das erste
// Token ist die Ahnen-Klasse, der Rest sind Interfaces. Ein Unit-Qualifier
// ('Vcl.Forms.TForm') wird gekappt, damit die Root-Liste greift.
// Lokale Kopie des Musters aus uFormBinder.FirstAncestor (geteilte Unit bleibt
// unangetastet).
var
  i : Integer;
begin
  Result := Trim(ATypeRefList);
  i := Pos(' ', Result);
  if i > 0 then Result := Trim(Copy(Result, 1, i - 1));
  i := LastDelimiter('.', Result);
  if i > 0 then Result := Copy(Result, i + 1, MaxInt);
end;

function IsFrameworkRoot(const AClassRef: string): Boolean;
// Spiegelt uFormBinder.BindWithParents.IsVclRoot: genau an diesen Klassen
// STOPPT die Parent-Aufloesung des Binders. Ist der oberste erreichte Ahn
// einer davon (oder gibt es gar keinen Ahn = implizit TObject), ist die Kette
// vollstaendig durchsucht. Muss eine Obermenge der Binder-Liste bleiben -
// sonst wuerden echte Funde faelschlich unterdrueckt.
const
  ROOTS : array[0..7] of string = (
    'TObject', 'TPersistent', 'TComponent',
    'TForm', 'TFrame', 'TCustomForm', 'TCustomFrame', 'TDataModule');
var
  R : string;
begin
  if AClassRef = '' then Exit(True);   // kein Ahn -> implizit TObject
  for R in ROOTS do
    if SameText(AClassRef, R) then Exit(True);
  Result := False;
end;

function IsAncestorChainResolved(Binding: TFormBinding): Boolean;
// FP-Gate (Real-World-Audit 2026-07-31, FP-Klasse 'Handler in Ancestor-
// Formklasse'): DFM-Streaming findet Handler ueber die komplette Klassen-
// hierarchie (TObject.MethodAddress), der Binder loest die Kette aber nur
// so weit auf, wie der Repo-Index reicht (Single-File-Scan: gar nicht;
// Multi-File: bis zur ersten unbekannten Klasse). Bricht die Kette bei einer
// USER-Klasse ab, kann der Handler dort deklariert sein - der behauptete
// Load-Crash ist dann unbeweisbar und wird nicht gemeldet.
// Vorbild-FP: skia4delphi Sample.Form.SplashScreen (TfrmSplashScreen =
// class(TfrmBase), pnlBackClick lebt in TfrmBase).
var
  Top : TFormBinding;
begin
  Result := False;
  Top := Binding;
  // MEHRDEUTIGKEIT schlaegt Vollstaendigkeit: wurde irgendein Glied der
  // Kette ueber einen Klassennamen erreicht, den mehrere Units fuehren,
  // hat der RepoIndex geraten. Die Kette kann dann formal bis zu einem
  // Framework-Root durchlaufen und trotzdem die eines fremden
  // Namensvetters sein - 'Handler nicht gefunden' beweist dann nichts.
  //
  // Belegt: skia4delphi fuehrt TfrmBase zweimal (Samples/Demo/VCL und
  // .../FMX). Der VCL-Splash wurde gegen die FMX-Basis gebunden, in der
  // pnlBackClick nicht existiert - gemeldet wurde ein Load-Crash, den es
  // nicht gibt. Der Zaehler war vor und nach dem 2026-07-31-Gate 4,
  // weil dieses Gate eine ANDERE Klasse trifft (abgebrochene Kette),
  // nicht die geratene.
  if Top.HasAmbiguousAncestor then Exit;
  while Top.Parent <> nil do
  begin
    Top := Top.Parent;
    if Top.HasAmbiguousAncestor then Exit;
  end;
  // Oberste Bindung ohne aufgeloeste Klasse -> Kette offen.
  if Top.FormClass = nil then Exit;
  Result := IsFrameworkRoot(FirstAncestorToken(Top.FormClass.TypeRef));
end;

// BEKANNTE GRENZE, bewusst NICHT gegatet: eine Property, deren Name mit
// 'On' beginnt, muss kein Ereignis sein. jvcl fuehrt
// 'TJvUIBQuery.OnError = etmStayIn' - das ist ein Enum-Wert, kein
// Methodenzeiger. Im DFM-Text sind beide ununterscheidbar: bare Bezeichner.
// Eine Heuristik ueber die Schreibweise scheidet aus, weil Enum-Literale
// ('etmStayIn') und IDE-erzeugte Handler ('btnOkClick') exakt dieselbe
// Form haben - Kleinbuchstaben-Praefix, dann Grossbuchstabe. Ein solches
// Gate wuerde die Mehrheit der echten Funde mit wegnehmen. Sauber loesbar
// erst mit Typinformation zur Komponentenklasse.
class procedure TDfmDeadEventDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Ev : TBoundEvent;
  F  : TLeakFinding;
begin
  if Binding = nil then Exit;
  // Ohne aufgeloeste Form-Klasse koennen wir die Existenz der Methode
  // nicht pruefen -> nichts melden. Ein eigener Befund fuer "Pascal nicht
  // gefunden" gehoert in den Runner-Layer, nicht hier.
  if Binding.FormClass = nil then Exit;
  // FP-Gate 2026-07-31: nur melden, wenn die Ahnen-Kette komplett aufgeloest
  // ist (s. IsAncestorChainResolved). Unvollstaendige Kette -> schweigen.
  if not IsAncestorChainResolved(Binding) then Exit;

  for Ev in Binding.Events do
  begin
    if Binding.HasHandler(Ev.HandlerName) then Continue;

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := Binding.FormClass.Name;
    F.LineNumber := IntToStr(Ev.Line);
    F.MissingVar := Format('%s.%s = %s (handler missing in %s)',
                            [Ev.Component.Name, Ev.EventName,
                             Ev.HandlerName, Binding.FormClass.Name]);
    F.SetKind(fkDfmDeadEvent);
    Results.Add(F);
  end;
end;

end.
