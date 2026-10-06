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
//   FormatRewrite   Parts -> BuildFormatCall (Kompilat-Regel, AH20);
//                   Bereich = erster bis letzter Term, Expected = dessen
//                   Text, NewText = Format(...); bei 'X := X + ...' nur
//                   der Rest hinter 'X +'
//
// Ein Ergebnis mit Enabled = False traegt den Grund (Operand mit Zahl-,
// Variant- oder AnsiString-Typ, Klammerausdruck, Kommentar oder Direktive
// im Bereich, SQL-Text, Zeile mehrdeutig, ...).

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
    // Herkunft der Argumente (AH20, Kompilat-Regel): wie viele Operanden,
    // wie viele davon bewiesen, wie viele als %d/%u, und fuer welche nur
    // das Kompilat buergt. SelfAppend: 'X := X + ...' - Format nur ueber
    // den Rest, der Bereich beginnt hinter 'X +'.
    Operands   : Integer;
    Proven     : Integer;
    Numeric    : Integer;
    ByCompiler : TArray<string>;
    SelfAppend : Boolean;
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

    // Teilbereiche mit Quelltext - die Eingabe der Rezepte. Operanden
    // tragen ihren deklarierten Typ (Resolved) und bei IntToStr(x) /
    // x.ToString den Typ von x (ArgResolved).
    class function PartsOf(APlaces: TSourcePlaces;
      AInfo: TRefactorInfo): TRdxParts; static;

    // Deklarierter Typ des Ziels (nackter Bezeichner oder Result), sonst ''.
    class function TargetTypeOf(APlaces: TSourcePlaces; AInfo: TRefactorInfo;
      const ATargetText: string): string; static;

    // Rezept 5.1: Format() aus der Kette nach der Kompilat-Regel
    // (uRdxRecipes.JudgeOperand). AInfo darf nil sein (AWhy wird dann
    // zum Grund). Gesperrt: Kommentar oder Direktive im Bereich, Ziel
    // oder Operand mit Nicht-Unicode-String-Typ, Operand mit Variant-
    // Anzeichen, Zahl, Klammerausdruck. Dass die Anweisung in einem
    // $IFDEF-Zweig liegt, sperrt nicht - ersetzt wird ihr exakter Text.
    // 'X := X + ...' wird 'X := X + Format(...)'. Fehlt System.SysUtils,
    // traegt das Ergebnis die Einfuegung in die uses-Klausel.
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
  i   : Integer;
  Arg : string;
begin
  Result := nil;
  if not Assigned(AInfo) then Exit;
  SetLength(Result, Length(AInfo.Parts));
  for i := 0 to High(AInfo.Parts) do
  begin
    Result[i] := TRdxRecipes.MakePart(AInfo.Parts[i].Role,
      APlaces.TextOf(AInfo.Parts[i]), AInfo.Parts[i].ValueType,
      AInfo.Parts[i].Resolved);
    if AInfo.Parts[i].Role = ROLE_OPERAND then
    begin
      Arg := TRdxRecipes.IntegerArgumentOf(Result[i].Text);
      if Arg <> '' then
        Result[i].ArgResolved := APlaces.DeclaredTypeOf(AInfo.Span.StartLine, Arg);
    end;
  end;
end;

class function TRdxRecipeRunner.TargetTypeOf(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; const ATargetText: string): string;
var
  T : string;
begin
  Result := '';
  T := Trim(ATargetText);
  if not Assigned(APlaces) or not Assigned(AInfo) then Exit;
  if not TRdxRecipes.IsPlainIdent(T) then Exit;
  Result := APlaces.DeclaredTypeOf(AInfo.Span.StartLine, T);
end;

// Gleicher Operand ohne Leerraum und Schreibung: 'Result' = 'result'.
function SameOperandText(const A, B: string): Boolean;
var
  SA, SB : string;
  i      : Integer;
begin
  SA := '';
  SB := '';
  for i := 1 to Length(A) do
    if A[i] > ' ' then SA := SA + A[i];
  for i := 1 to Length(B) do
    if B[i] > ' ' then SB := SB + B[i];
  Result := (SA <> '') and SameText(SA, SB);
end;

class function TRdxRecipeRunner.FormatRewrite(APlaces: TSourcePlaces;
  AInfo: TRefactorInfo; const AWhy: string;
  const AUsesNames: TArray<string>): TRdxFormatOutcome;
var
  Parts  : TRdxParts;
  Last   : Integer;
  First  : Integer;
  Build  : TRdxFormatBuild;
  Plan   : TRdxUsesPlan;
  TType  : string;
  Names  : string;
  i      : Integer;
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
  begin
    Result.Reason := 'keine Zuweisung mit Kette';
    Exit;
  end;
  // Ein Kommentar im Bereich ginge beim Ersetzen verloren; eine Compiler-
  // Direktive im Bereich zaehlt der Builder ebenso als Kommentar. Dass die
  // Anweisung in einem $IFDEF-Zweig LIEGT, sperrt seit AH20 nicht mehr.
  if rfHasComment in AInfo.Flags then
  begin
    Result.Reason := 'Kommentar im Bereich';
    Exit;
  end;
  // Ziel mit Nicht-Unicode-String-Typ: Format liefert UnicodeString, die
  // Zuweisung wuerde konvertieren (Alcinoe, Indy: AnsiString-Ketten).
  TType := TargetTypeOf(APlaces, AInfo, Parts[0].Text);
  if TRdxRecipes.IsNonUnicodeStringType(TType) then
  begin
    Result.Reason := Format('Ziel ''%s'' ist %s - Format liefert UnicodeString',
      [TRdxRecipes.CollapseWhitespace(Parts[0].Text), TType]);
    Exit;
  end;
  // Selbst-Anhaengen 'X := X + ...' (ein Drittel der Korpus-Stellen):
  // Format nur ueber den Rest, X bleibt vorn - 'X := X + Format(...)'.
  First := 1;
  if (Last >= 3) and (AInfo.Parts[1].Role = ROLE_OPERAND)
     and SameOperandText(Parts[1].Text, Parts[0].Text) then
  begin
    First := 2;
    Result.SelfAppend := True;
  end;
  if not TRdxRecipes.BuildFormatCall(Copy(Parts, First, Last - First + 1), Build) then
  begin
    Result.Reason := Build.Reason;
    if Result.SelfAppend and (Build.Operands = 0) and (Build.Reason <> '')
       and (Pos('kein Operand', Build.Reason) > 0) then
      Result.Reason := 'hinter ' + TRdxRecipes.CollapseWhitespace(Parts[0].Text)
        + ' stehen nur Literale';
    Exit;
  end;
  Result.NewText    := Build.NewText;
  Result.Operands   := Build.Operands;
  Result.Proven     := Build.Proven;
  Result.Numeric    := Build.Numeric;
  Result.ByCompiler := Build.ByCompiler;
  // Ersetzt wird vom ersten (bzw. zweiten) bis zum letzten Term; Ziel und
  // ':=' (und bei Selbst-Anhaengen 'X +') bleiben.
  Result.Span := TRefactorSpan.Make(ROLE_STATEMENT,
    AInfo.Parts[First].StartLine, AInfo.Parts[First].StartCol,
    AInfo.Parts[Last].EndLine, AInfo.Parts[Last].EndCol);
  Result.Expected := APlaces.TextOf(Result.Span);
  if Result.Expected = '' then
  begin
    Result.Reason := 'Bereich nicht lesbar';
    Exit;
  end;
  if Pos('{$', Result.Expected) > 0 then
  begin
    Result.Reason := 'Compiler-Direktive im Bereich';
    Exit;
  end;
  Result.Hint := Format('%d Terme', [Last - First + 1]);
  if Result.SelfAppend then
    Result.Hint := Result.Hint + ' hinter '
      + TRdxRecipes.CollapseWhitespace(Parts[0].Text);
  if Length(Build.ByCompiler) = 0 then
    Result.Hint := Result.Hint + ', alle bewiesen'
  else
  begin
    Names := '';
    for i := 0 to High(Build.ByCompiler) do
    begin
      if i = 3 then
      begin
        Names := Names + ', ...';
        Break;
      end;
      if Names <> '' then Names := Names + ', ';
      Names := Names + Build.ByCompiler[i];
    end;
    Result.Hint := Result.Hint + Format(', %d laut Kompilat (%s)',
      [Length(Build.ByCompiler), Names]);
  end;
  if Build.Numeric > 0 then
    Result.Hint := Result.Hint + Format(', %d als %%d', [Build.Numeric]);
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
