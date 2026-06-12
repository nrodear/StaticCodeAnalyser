unit uDfmDefaultName;

// Detektor: Default-Komponentennamen im DFM.
//
// Refactoring-Killer wie Button1, Edit3, Panel2 erzeugen Code, der nichts
// ueber den Zweck verraet. Beispiel:
//   Button1.OnClick := SpeichernClick;
// vs.
//   btnSpeichern.OnClick := SpeichernClick;
//
// Regel: Name passt zu '<KlassenSuffix><Zahl>'. Heuristik nimmt den
// Klassen-Namen ohne fuehrendes 'T' (TButton -> Button), und prueft, ob
// der Komponenten-Name dazu plus eine Zahl ist. Damit fangen wir die
// IDE-Default-Namen ab, ohne legitime PascalCase-Namen mit Ziffern
// (z.B. 'btnSpeichern1') faelschlich zu treffen.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell (siehe KIND_META).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmDefaultNameDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CyclomaticComplexity, MultipleExit, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

function IsDefaultName(const ComponentName, ClassRef: string): Boolean;
// 'Button1' fuer TButton, 'Edit3' fuer TEdit, 'TForm2' nicht (das ist die
// Klasse selbst, faellt unter Heuristik aber raus weil 'Form' != 'TForm').
//
// Algorithmus:
//   1) Klassen-Suffix bestimmen: 'TButton' -> 'Button'.
//      Wenn die Klasse nicht mit grossem 'T' anfaengt (z.B. CompactComponent),
//      ist die ganze Klasse das Suffix.
//   2) Pruefen ob ComponentName mit Suffix beginnt (case-sensitive - die
//      IDE schreibt PascalCase, abweichende Schreibweise zaehlt nicht als
//      Default).
//   3) Rest dahinter muss aus mindestens einer Ziffer bestehen und sonst
//      nichts.
var
  Suffix : string;
  Rest   : string;
  i      : Integer;
begin
  Result := False;
  if (ComponentName = '') or (ClassRef = '') then Exit;

  if (Length(ClassRef) > 1) and (ClassRef[1] = 'T') then
    Suffix := Copy(ClassRef, 2, MaxInt)
  else
    Suffix := ClassRef;

  if Suffix = '' then Exit;
  if Length(ComponentName) <= Length(Suffix) then Exit;
  if not StartsStr(Suffix, ComponentName) then Exit;

  Rest := Copy(ComponentName, Length(Suffix) + 1, MaxInt);
  if Rest = '' then Exit;
  for i := 1 to Length(Rest) do
    if not CharInSet(Rest[i], ['0'..'9']) then Exit;

  Result := True;
end;

class procedure TDfmDefaultNameDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  All  : TList<TComponentNode>;
  N    : TComponentNode;
  F    : TLeakFinding;
begin
  if Graph = nil then Exit;

  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if IsDefaultName(N.Name, N.ClassRef) then
      begin
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(N.Line);
        F.MissingVar := Format('%s: %s', [N.Name, N.ClassRef]);
        F.SetKind(fkDfmDefaultName);
        Results.Add(F);
      end;
    end;
  finally
    All.Free;
  end;
end;

end.
