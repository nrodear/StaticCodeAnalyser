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
  uAstNode, uFormBinder, uComponentGraph;

type
  TDfmOrphanHandlerDetector = class
  public
    class procedure Analyze(Binding: TFormBinding; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file ConcatToFormat, GroupedDeclaration, MultipleExit, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

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

procedure SammleItemListBindungen(Node: TComponentNode;
  AZiel: TDictionary<string, Boolean>);
// FP-Fix Charge 15 (Vollzaehlung rw70b: 31 von 426): Collection-Item-
// Events ('Actions = < item OnAction = Foo end >', WebModule-Actions,
// TJvPlugin-Commands, python4delphi-Events) speichert der DFM-Parser
// als pvkItemList-ROHTEXT - der Binder sieht diese Bindungen nicht,
// der Handler galt als verwaist, obwohl die DFM ihn woertlich bindet.
// Der Scan bleibt bewusst LOKAL in diesem Detektor: die geteilte
// Events-Liste des Binders speist auch SCA028/184 - dort wuerde jede
// neue Bindung eigene Bewegung erzeugen (Lehre: Gate nie in geteilten
// Helfern). Erkannt wird exakt die Form 'On<Ident> = <Ident>' am
// Zeilenanfang des Item-Blocks; 'nil' zaehlt nicht (Binder-Vertrag).
var
  Pair   : TPair<string, TPropValue>;
  Child  : TComponentNode;
  S, Rhs : string;
  P      : Integer;
begin
  for Pair in Node.Properties do
  begin
    if Pair.Value.Kind <> pvkItemList then Continue;
    for S in Pair.Value.RawValue.Split([#10, #13]) do
    begin
      Rhs := Trim(S);
      if (Length(Rhs) < 6) or (Copy(Rhs, 1, 2) <> 'On') then Continue;
      P := Pos('=', Rhs);
      if P = 0 then Continue;
      if not IsValidIdent(Trim(Copy(Rhs, 1, P - 1))) then Continue;
      Rhs := Trim(Copy(Rhs, P + 1, MaxInt));
      if IsValidIdent(Rhs) and not SameText(Rhs, 'nil') then
        AZiel.AddOrSetValue(LowerCase(Rhs), True);
    end;
  end;
  for Child in Node.Children do
    SammleItemListBindungen(Child, AZiel);
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
      // Collection-Item-Bindungen (pvkItemList) mitzaehlen - s. Doku
      // an SammleItemListBindungen.
      if Walker.FormNode <> nil then
        SammleItemListBindungen(Walker.FormNode, BoundHandlers);
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
      F.SetKind(fkDfmOrphanHandler);
      Results.Add(F);
    end;
  finally
    BoundHandlers.Free;
  end;
end;

end.
