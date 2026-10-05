unit uRdxRecipeRunner;

// reDelphix - der Rezept-Laeufer: fuehrt die Rezepte (uRdxRecipes) gegen
// den Quellstellen-Dienst des SCA-Cores (TSourcePlaces) aus. Ohne
// ToolsAPI, ohne Clipboard, ohne Menue - damit ist dieser Weg vom Fund
// bis zum fertigen Ersatztext in reDelphix.Test ohne IDE pruefbar. Der
// Anbieter (uRdxProvider) baut daraus nur noch Menuepunkte.
//
// ABLAUF FUER SCA044 (Rezept 5.1)
//
//   DescribeAnchor  NodesAt(Zeile, Anker) -> genau ein Knoten -> ChainOf
//   FormatRewrite   Parts -> BuildFormatCall; Bereich = erster bis letzter
//                   Term, Expected = dessen Text, NewText = Format(...)
//
// Ein Ergebnis mit Enabled = False traegt den Grund (Operand ohne
// String-Typ, Kommentar im Bereich, $IFDEF, SysUtils fehlt, SQL-Text,
// Zeile mehrdeutig, ...).

interface

uses
  System.SysUtils, System.Classes,
  uEngineApi, uRefactorInfo, uRdxRecipes;

type
  TRdxFormatOutcome = record
    Enabled  : Boolean;
    Reason   : string;          // bei Enabled = False
    Hint     : string;          // bei Enabled = True
    Span     : TRefactorSpan;   // zu ersetzender Bereich (erster bis letzter Term)
    Expected : string;          // Text des Bereichs laut Scan
    NewText  : string;          // Format(...)
  end;

  TRdxRecipeRunner = class
  public
    // Der Kopf eines nkCall-Knotens: der Teil von TNodeRef.Name vor '('.
    class function HeadOf(const ACallName: string): string; static;

    // Qualifizierte/rohe Namen aller uses-Eintraege der geoeffneten Datei.
    class function UsesNamesOf(APlaces: TSourcePlaces): TArray<string>; static;

    // Beschreibt die Anweisung des Funds auf ALine nach dem Anker der Regel
    // ('assign', 'call', 'assign-or-call', sonst beides). nil mit Grund,
    // wenn kein oder mehr als ein Knoten auf der Zeile liegt oder die
    // Anweisung sich nicht beschreiben laesst. Der Aufrufer besitzt das
    // Ergebnis.
    class function DescribeAnchor(APlaces: TSourcePlaces; ALine: Integer;
      const AAnchor: string; out AIsCall: Boolean;
      out AWhy: string): TRefactorInfo; static;

    // Teilbereiche mit Quelltext - die Eingabe der Rezepte.
    class function PartsOf(APlaces: TSourcePlaces;
      AInfo: TRefactorInfo): TRdxParts; static;

    // Warum ein Info nicht FixSafe ist - fuer den ausgegrauten Eintrag.
    class function UnsafeReason(AInfo: TRefactorInfo;
      const AParts: TRdxParts): string; static;

    // Rezept 5.1: Format() aus der Kette. AInfo darf nil sein (AWhy wird
    // dann zum Grund).
    class function FormatRewrite(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      const AWhy: string;
      const AUsesNames: TArray<string>): TRdxFormatOutcome; static;

    // Rezept 5.2: parametrisierte Vorlage (nur Text).
    class function SqlTemplate(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      AIsCall: Boolean; out ATemplate, AHint, AReason: string): Boolean; static;
  end;

implementation

{ TRdxRecipeRunner }

class function TRdxRecipeRunner.HeadOf(const ACallName: string): string;
var
  P : Integer;
begin
  Result := ACallName;
  P := Pos('(', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  Result := Trim(Result);
end;

class function TRdxRecipeRunner.UsesNamesOf(
  APlaces: TSourcePlaces): TArray<string>;
var
  Entries : TArray<TRefactorSpan>;
  i       : Integer;
begin
  Result := nil;
  if not Assigned(APlaces) or not APlaces.IsOpen then Exit;
  Entries := APlaces.UsesEntries(TUsesSection.usAny);
  SetLength(Result, Length(Entries));
  for i := 0 to High(Entries) do
    Result[i] := Entries[i].Resolved;
end;

class function TRdxRecipeRunner.DescribeAnchor(APlaces: TSourcePlaces;
  ALine: Integer; const AAnchor: string; out AIsCall: Boolean;
  out AWhy: string): TRefactorInfo;
var
  Kinds : TNodeKinds;
  Nodes : TArray<TNodeRef>;
  N     : TNodeRef;
begin
  Result  := nil;
  AIsCall := False;
  AWhy    := '';
  if not Assigned(APlaces) or not APlaces.IsOpen then
  begin
    AWhy := 'keine Datei geoeffnet';
    Exit;
  end;
  if AAnchor = 'assign' then
    Kinds := [TNodeKind.nkAssign]
  else if AAnchor = 'call' then
    Kinds := [TNodeKind.nkCall]
  else
    Kinds := [TNodeKind.nkAssign, TNodeKind.nkCall];
  Nodes := APlaces.NodesAt(ALine, Kinds);
  if Length(Nodes) = 0 then
  begin
    AWhy := Format('keine Anweisung auf Zeile %d gefunden', [ALine]);
    Exit;
  end;
  if Length(Nodes) > 1 then
  begin
    AWhy := Format('Zeile %d ist mehrdeutig (%d Anweisungen)',
      [ALine, Length(Nodes)]);
    Exit;
  end;
  N := Nodes[0];
  if N.Kind = TNodeKind.nkAssign then
    Result := APlaces.ChainOf(N.Line, N.Col, N.Name)
  else
  begin
    AIsCall := True;
    Result := APlaces.CallOf(N.Line, N.Col, HeadOf(N.Name));
  end;
  // Ohne Kette wenigstens die Anweisung selbst (fuer "Stelle zeigen").
  if Result = nil then
    Result := APlaces.StatementAt(N.Line, N.Col);
  if Result = nil then
    AWhy := 'Anweisung laesst sich nicht beschreiben';
end;

class function TRdxRecipeRunner.PartsOf(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo): TRdxParts;
var
  i : Integer;
begin
  Result := nil;
  if not Assigned(AInfo) then Exit;
  SetLength(Result, Length(AInfo.Parts));
  for i := 0 to High(AInfo.Parts) do
    Result[i] := TRdxRecipes.MakePart(AInfo.Parts[i].Role,
      APlaces.TextOf(AInfo.Parts[i]), AInfo.Parts[i].ValueType);
end;

class function TRdxRecipeRunner.UnsafeReason(AInfo: TRefactorInfo;
  const AParts: TRdxParts): string;
var
  i : Integer;
begin
  if rfHasComment in AInfo.Flags then Exit('Kommentar im Bereich');
  if rfInConditional in AInfo.Flags then Exit('Bereich liegt in einem $IFDEF');
  for i := 0 to High(AParts) do
  begin
    if AParts[i].Role <> ROLE_OPERAND then Continue;
    if AParts[i].ValueType = rvNonString then
    begin
      if (i <= High(AInfo.Parts)) and (AInfo.Parts[i].Resolved <> '') then
        Exit(Format('Operand ''%s'': kein String (%s)',
          [TRdxRecipes.CollapseWhitespace(AParts[i].Text), AInfo.Parts[i].Resolved]));
      Exit(Format('Operand ''%s'': kein String',
        [TRdxRecipes.CollapseWhitespace(AParts[i].Text)]));
    end;
    if AParts[i].ValueType <> rvString then
      Exit(Format('Operand ''%s'': Typ unbekannt',
        [TRdxRecipes.CollapseWhitespace(AParts[i].Text)]));
  end;
  Result := 'Kette nicht rein (Operator auf oberster Ebene)';
end;

class function TRdxRecipeRunner.FormatRewrite(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; const AWhy: string;
  const AUsesNames: TArray<string>): TRdxFormatOutcome;
var
  Parts : TRdxParts;
  Last  : Integer;
begin
  Result := Default(TRdxFormatOutcome);
  if AInfo = nil then
  begin
    Result.Reason := AWhy;
    if Result.Reason = '' then Result.Reason := 'keine Beschreibung';
    Exit;
  end;
  Parts := PartsOf(APlaces, AInfo);
  Last  := High(AInfo.Parts);
  if (Last < 1) or (AInfo.Parts[0].Role <> ROLE_TARGET) then
    Result.Reason := 'keine Zuweisung mit Kette'
  else if not AInfo.FixSafe then
    Result.Reason := UnsafeReason(AInfo, Parts)
  else if not TRdxRecipes.HasUnit(AUsesNames, 'SysUtils') then
    Result.Reason := 'System.SysUtils fehlt in uses';
  if Result.Reason = '' then
    TRdxRecipes.BuildFormatCall(Parts, Result.NewText, Result.Reason);
  if Result.Reason <> '' then Exit;
  // Ersetzt wird vom ersten bis zum letzten Term; Ziel und ':=' bleiben.
  Result.Span := TRefactorSpan.Make(ROLE_STATEMENT,
    AInfo.Parts[1].StartLine, AInfo.Parts[1].StartCol,
    AInfo.Parts[Last].EndLine, AInfo.Parts[Last].EndCol);
  Result.Expected := APlaces.TextOf(Result.Span);
  if Result.Expected = '' then
  begin
    Result.Reason := 'Bereich nicht lesbar';
    Exit;
  end;
  Result.Hint    := Format('%d Terme, alle Strings', [Last]);
  Result.Enabled := True;
end;

class function TRdxRecipeRunner.SqlTemplate(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; AIsCall: Boolean;
  out ATemplate, AHint, AReason: string): Boolean;
var
  Parts : TRdxParts;
  i, N  : Integer;
begin
  Result    := False;
  ATemplate := '';
  AHint     := '';
  AReason   := '';
  if AInfo = nil then
  begin
    AReason := 'keine Beschreibung';
    Exit;
  end;
  Parts := PartsOf(APlaces, AInfo);
  if (Length(Parts) = 0) or (Parts[0].Role <> ROLE_TARGET) then
  begin
    AReason := 'kein Ziel erkannt';
    Exit;
  end;
  if not TRdxRecipes.BuildSqlTemplate(Parts[0].Text, AIsCall, Parts,
       AInfo.InsertIndent, ATemplate, AReason) then
    Exit;
  N := 0;
  for i := 0 to High(Parts) do
    if Parts[i].Role = ROLE_OPERAND then Inc(N);
  AHint  := Format('%d Parameter, nichts wird geschrieben', [N]);
  Result := True;
end;

end.
