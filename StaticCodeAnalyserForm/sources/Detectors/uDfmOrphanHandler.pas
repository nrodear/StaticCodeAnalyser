unit uDfmOrphanHandler;

// Detektor: Verwaister Event-Handler.
//
// Findet published Methoden in der Form-Klasse, die wie Event-Handler
// aussehen, aber von keiner Komponente im DFM aufgerufen werden.
// Klassischer Code-Smell nach Refactoring: jemand entfernt eine
// Komponente aus der Form, vergisst aber den dazugehoerigen Handler im
// Pascal-Code zu loeschen.
//
// Heuristik fuer "sieht wie Event-Handler aus":
//   * Methode ist published (TPersistent-Default oder explizit deklariert)
//   * Erster Parameter heisst 'Sender' (case-insensitiv)
//   * Erster Parameter-Typ ist 'TObject' (case-insensitiv)
// Dass die Methode mehrere Parameter haben darf (OnKeyPress hat 2,
// OnMouseDown hat 5) ist absichtlich - der Sender ist der erste, das
// reicht als Signatur-Marker.
//
// Schweregrad: lsHint, FindingType: ftCodeSmell.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uFormBinder;

type
  TDfmOrphanHandlerDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.StrUtils;

function IsSenderEventHandler(Method: TAstNode): Boolean;
// Erster Param: Name 'Sender' (mit optionalem 'var '/'const '/'out '
// Modifier-Prefix vom Parser), Typ 'TObject'.
var
  P, FirstChild   : TAstNode;
  ParamName, T    : string;
  SpacePos        : Integer;
begin
  Result := False;
  if Method.Children.Count = 0 then Exit;
  FirstChild := Method.Children[0];
  if FirstChild.Kind <> nkParam then Exit;

  P := FirstChild;
  ParamName := P.Name;
  // Modifier-Prefix abschneiden (uParser2 setzt z.B. 'var Sender').
  SpacePos := Pos(' ', ParamName);
  if SpacePos > 0 then
    ParamName := Copy(ParamName, SpacePos + 1, MaxInt);

  if not SameText(ParamName, 'Sender') then Exit;

  T := Trim(P.TypeRef);
  if not SameText(T, 'TObject') then Exit;

  Result := True;
end;

class procedure TDfmOrphanHandlerDetector.Analyze(Binding: TFormBinding;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  BoundHandlers : TDictionary<string, Boolean>;
  Ev            : TBoundEvent;
  Pair          : TPair<string, TAstNode>;
  M             : TAstNode;
  F             : TLeakFinding;
  Walker        : TFormBinding;
begin
  if Binding = nil then Exit;
  if Binding.FormClass = nil then Exit;
  if Binding.PublishedMethods.Count = 0 then Exit;

  BoundHandlers := TDictionary<string, Boolean>.Create;
  try
    // Lokale Events erst. Anschliessend Events aller Parent-Bindings,
    // sodass eine Methode in TForm2.published, die von einem Button im
    // _Parent_-DFM (TForm1.dfm) per OnClick gebunden ist, nicht
    // false-positiv als Orphan gemeldet wird.
    Walker := Binding;
    while Walker <> nil do
    begin
      for Ev in Walker.Events do
        BoundHandlers.AddOrSetValue(LowerCase(Ev.HandlerName), True);
      Walker := Walker.Parent;
    end;

    for Pair in Binding.PublishedMethods do
    begin
      M := Pair.Value;
      if not IsSenderEventHandler(M) then Continue;
      if BoundHandlers.ContainsKey(LowerCase(M.Name)) then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := Binding.FormClass.Name + '.' + M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := Format(
        '%s.%s has a (Sender: TObject) signature but no component binds it',
        [Binding.FormClass.Name, M.Name]);
      F.Severity   := lsHint;
      F.Kind       := fkDfmOrphanHandler;
      Results.Add(F);
    end;
  finally
    BoundHandlers.Free;
  end;
end;

end.
