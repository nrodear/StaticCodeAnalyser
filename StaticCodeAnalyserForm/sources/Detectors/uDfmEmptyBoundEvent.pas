unit uDfmEmptyBoundEvent;

// Detektor: Leerer gebundener Event-Handler.
//
// Findet Komponenten-Events, deren Handler-Methode zwar existiert, aber
// einen leeren Body hat. Bewusst gepaart - der generische 'EmptyMethod'-
// Detektor meldet jede leere Methode, was bei abstrakten Hook-Methoden
// und Override-Stubs viele False Positives erzeugt. Hier ist die Bindung
// im DFM aber explizit: jemand hat den Handler verdrahtet und vergessen
// zu implementieren.
//
// Body-Definition wie in uEmptyMethod: nkBlock-Child mit Children.Count=0.
// Methoden mit nur 'inherited;' produzieren ein nkInherited-Kind und
// gelten als nicht leer.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uFormBinder;

type
  TDfmEmptyBoundEventDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

function FindBodyBlock(Method: TAstNode): TAstNode;
var Child: TAstNode;
begin
  Result := nil;
  if Method = nil then Exit;
  for Child in Method.Children do
    if Child.Kind = nkBlock then
      Exit(Child);
end;

class procedure TDfmEmptyBoundEventDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Ev    : TBoundEvent;
  Impl  : TAstNode;
  Block : TAstNode;
  Key   : string;
  F     : TLeakFinding;
begin
  if Binding = nil then Exit;
  if Binding.FormClass = nil then Exit;

  for Ev in Binding.Events do
  begin
    // Nur Bindungen auswerten, deren Implementation tatsaechlich existiert.
    // Fehlende Methode ist Sache von TDfmDeadEventDetector.
    Key := LowerCase(Ev.HandlerName);
    if not Binding.MethodImpls.TryGetValue(Key, Impl) then Continue;

    Block := FindBodyBlock(Impl);
    if Block = nil then Continue;                 // Forward-Decl / abstract
    if Block.Children.Count > 0 then Continue;    // hat Anweisungen

    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := Binding.FormClass.Name + '.' + Ev.HandlerName;
    F.LineNumber := IntToStr(Ev.Line);
    F.MissingVar := Format(
      '%s.%s is wired to %s but the method body is empty',
      [Ev.Component.Name, Ev.EventName, Ev.HandlerName]);
    F.Severity   := lsHint;
    F.Kind       := fkDfmEmptyBoundEvent;
    Results.Add(F);
  end;
end;

end.
