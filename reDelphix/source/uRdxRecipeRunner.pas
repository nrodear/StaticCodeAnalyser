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
  // Eine Ersetzung im Editor: Bereich, erwarteter alter Text, neuer Text.
  // Zeilenumbrueche im neuen Text sind #10; der Editor setzt sie auf die
  // Zeilenenden des Puffers um.
  TRdxEdit = record
    Span     : TRefactorSpan;
    Expected : string;
    NewText  : string;
  end;

  // Was fuer eine fehlende Unit in der uses-Klausel zu tun ist (AH19).
  TRdxUsesPlan = record
    Needed : Boolean;     // False = die Unit steht schon in einer uses-Klausel
    Name   : string;      // der einzufuegende Name ('System.SysUtils' / 'SysUtils')
    Edit   : TRdxEdit;    // die Ersetzung, wenn Needed und Reason = ''
    Reason : string;      // wenn Needed, aber keine Stelle bestimmbar
  end;

  TRdxFormatOutcome = record
    Enabled   : Boolean;
    Reason    : string;          // bei Enabled = False
    Hint      : string;          // bei Enabled = True
    Span      : TRefactorSpan;   // zu ersetzender Bereich (erster bis letzter Term)
    Expected  : string;          // Text des Bereichs laut Scan
    NewText   : string;          // Format(...)
    // Format() braucht System.SysUtils: fehlt die Unit in der uses-Klausel,
    // wird sie mit eingefuegt (zweite Ersetzung, oberhalb der ersten).
    NeedsUses : Boolean;
    UsesName  : string;
    UsesEdit  : TRdxEdit;
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
    // dann zum Grund). Fehlt System.SysUtils, traegt das Ergebnis die
    // Einfuegung in die uses-Klausel (NeedsUses/UsesEdit).
    class function FormatRewrite(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      const AWhy: string;
      const AUsesNames: TArray<string>): TRdxFormatOutcome; static;

    // Plant die Ergaenzung der uses-Klausel um eine RTL-Unit (Kurzname und
    // qualifizierter Name). Reihenfolge der Stellen: die uses-Klausel des
    // implementation-Abschnitts, sonst die des interface-Abschnitts, sonst
    // eine beliebige (Programm); eine sortierte Liste bleibt sortiert
    // (SCA142), eine unsortierte bekommt den Namen vorn; steht hinter dem
    // letzten Eintrag ein 'in'-Pfad (.dpr), wird vorn eingefuegt. Ohne
    // jede uses-Klausel wird hinter 'implementation' (sonst 'interface')
    // eine neue angelegt. Reason, wenn auch das nicht geht.
    class function PlanUses(APlaces: TSourcePlaces;
      const AShortName, AQualifiedName: string): TRdxUsesPlan; static;

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
  Plan  : TRdxUsesPlan;
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
    Result.Reason := UnsafeReason(AInfo, Parts);
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
  Result.Hint := Format('%d Terme, alle Strings', [Last]);
  // Format() lebt in System.SysUtils: fehlt die Unit, kommt sie mit -
  // nicht ausgrauen, sondern die uses-Klausel ergaenzen (Nico, 2026-10-06).
  if not TRdxRecipes.HasUnit(AUsesNames, 'SysUtils') then
  begin
    Plan := PlanUses(APlaces, 'SysUtils', 'System.SysUtils');
    if Plan.Needed then
    begin
      if Plan.Reason <> '' then
      begin
        Result.Reason := 'System.SysUtils fehlt in uses: ' + Plan.Reason;
        Exit;
      end;
      Result.NeedsUses := True;
      Result.UsesName  := Plan.Name;
      Result.UsesEdit  := Plan.Edit;
      Result.Hint := Result.Hint + ' + uses ' + Plan.Name;
    end;
  end;
  Result.Enabled := True;
end;

class function TRdxRecipeRunner.PlanUses(APlaces: TSourcePlaces;
  const AShortName, AQualifiedName: string): TRdxUsesPlan;
var
  AllNames : TArray<string>;
  Entries  : TArray<TRefactorSpan>;
  Names    : TArray<string>;
  i, Idx   : Integer;
  E        : TRefactorSpan;
  Rest     : string;
  Old      : string;
  Line     : Integer;
  Text     : string;
begin
  Result := Default(TRdxUsesPlan);
  if not Assigned(APlaces) or not APlaces.IsOpen then
  begin
    Result.Needed := True;
    Result.Reason := 'keine Datei geoeffnet';
    Exit;
  end;
  AllNames := UsesNamesOf(APlaces);
  if TRdxRecipes.HasUnit(AllNames, AShortName) then Exit;   // schon da
  Result.Needed := True;
  Result.Name   := TRdxRecipes.UsesNameFor(AllNames, AShortName, AQualifiedName);

  // Die Klausel: implementation vor interface vor beliebig (Programm).
  Entries := APlaces.UsesEntries(TUsesSection.usImplementation);
  if Length(Entries) = 0 then
    Entries := APlaces.UsesEntries(TUsesSection.usInterface);
  if Length(Entries) = 0 then
    Entries := APlaces.UsesEntries(TUsesSection.usAny);

  if Length(Entries) > 0 then
  begin
    SetLength(Names, Length(Entries));
    for i := 0 to High(Entries) do
      Names[i] := Entries[i].Resolved;
    Idx := TRdxRecipes.SortedInsertIndex(Names, Result.Name);
    if Idx >= Length(Entries) then
    begin
      // Anhaengen nur, wenn hinter dem letzten Eintrag direkt das ';'
      // folgt oder die Zeile dort endet. Steht dort etwas anderes - ein
      // 'in'-Pfad (.dpr), ein Kommentar, eine Direktive -, wird VOR dem
      // letzten Eintrag eingefuegt: das ist immer gueltig.
      E := Entries[High(Entries)];
      Rest := Trim(Copy(APlaces.LineText(E.EndLine), E.EndCol, MaxInt));
      if (Rest <> '') and (Rest[1] <> ';') then
        Idx := High(Entries);
    end;
    if Idx >= Length(Entries) then
      E := Entries[High(Entries)]
    else
      E := Entries[Idx];
    // Ersetzt wird der Eintrag so, wie er im Puffer steht (TextOf), nicht
    // der aufgeloeste Name - der Editor vergleicht Zeichen fuer Zeichen.
    Old := APlaces.TextOf(E);
    if Old = '' then
    begin
      Result.Reason := Format('uses-Eintrag in Zeile %d nicht lesbar',
        [E.StartLine]);
      Exit;
    end;
    Result.Edit.Span     := E;
    Result.Edit.Expected := Old;
    if Idx >= Length(Entries) then
      Result.Edit.NewText := Old + ', ' + Result.Name
    else
      Result.Edit.NewText := Result.Name + ', ' + Old;
    Exit;
  end;

  // Keine uses-Klausel: eine neue hinter 'implementation', sonst hinter
  // 'interface' anlegen - als Ersetzung der Schluesselwort-Zeile.
  Line := APlaces.SectionLine(TUsesSection.usImplementation);
  if Line = 0 then
    Line := APlaces.SectionLine(TUsesSection.usInterface);
  if Line = 0 then
  begin
    Result.Reason := 'keine uses-Klausel und kein interface/implementation';
    Exit;
  end;
  Text := APlaces.LineText(Line);
  if Trim(Text) = '' then
  begin
    Result.Reason := Format('Zeile %d des Abschnitts nicht lesbar', [Line]);
    Exit;
  end;
  Result.Edit.Span     := TRefactorSpan.Make(ROLE_STATEMENT, Line, 1, Line,
    Length(Text) + 1);
  Result.Edit.Expected := Text;
  Result.Edit.NewText  := Text + #10 + #10 + 'uses' + #10 + '  '
    + Result.Name + ';';
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
