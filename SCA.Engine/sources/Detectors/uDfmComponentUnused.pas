unit uDfmComponentUnused;

// Detektor (SCA184): eine DFM-Komponente einer Form/Frame/DataModule, die
// NIRGENDS referenziert wird - weder im eigenen Pascal-Code, noch aus einer
// anderen Unit (Cross-Unit via Form-Global), noch DFM-intern (DataSource=,
// Action=, ActiveControl=, ...), noch ueber eine Event-Bindung.
//
// Beispiel (Refactoring-Rest):
//   uMainForm.dfm
//     object btnAlt: TButton ... end      // aus dem Code entfernt, im DFM blieb er
//   uMainForm.pas
//     type TMainForm = class(TForm)
//       btnAlt: TButton;                   // published Field, aber nie benutzt
//     end;
// Zur Laufzeit wird btnAlt vom Streamer erzeugt und belegt Speicher, obwohl
// ihn niemand anspricht.
//
// KERNRISIKO (Maintainer): eine published Komponente, die aus einer ANDEREN
// Unit ueber den Form-Singleton benutzt wird (Form1.SqlField1), ist KEIN
// Fund. Das faengt der repo-weite Cross-Unit-Index (TSymbolReferenceIndex)
// ab - deshalb ist S1 (ohne Symbol-Index kein Fund) die wichtigste Regel.
//
// Einstufung: ftCodeSmell / lsHint / fcLow. Bewusst unter dem fcMedium-
// Default-Filter (neuer Cross-Unit-Heuristik-Detektor mit realer FP-Flaeche);
// Promotion erst nach Real-World-A/B.

interface

uses
  System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uAstNode, uComponentGraph, uFormBinder,
  uDfmRepoIndex, uSymbolReferenceIndex;

type
  TDfmComponentUnusedDetector = class
  public
    // AOwnUnitPath = Pfad der .pas (fuer Cross-Unit-Lookup + S3-Quelltext),
    // AFileName    = Pfad der .dfm (Fundort). SymIdx MUSS gesetzt sein,
    // sonst emittiert der Detektor NICHTS (S1).
    class procedure Analyze(Binding: TFormBinding; Graph: TComponentGraph;
      RepoIdx: TDfmRepoIndex; SymIdx: TSymbolReferenceIndex;
      const AOwnUnitPath, AFileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file GroupedDeclaration, MultipleExit, NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils, System.StrUtils, System.IOUtils,
  uCompatSet;  // D11: THashSet<T>-Ersatz (D12: natives THashSet)

function IsIdentCh(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

procedure TokenizeInto(const Text: string; Target: THashSet<string>);
// Zerlegt Text in maximale Identifier-Runs (durch Nicht-Identifier-Zeichen
// getrennt) und legt jeden lowercased ins Set. Ganzwort-Semantik: 'Panel'
// und 'Panel1' werden so nie verwechselt. Add ist idempotent.
var
  I, N, StartAt : Integer;
begin
  if Target = nil then Exit;
  N := Length(Text);
  I := 1;
  while I <= N do
  begin
    if IsIdentCh(Text[I]) then
    begin
      StartAt := I;
      while (I <= N) and IsIdentCh(Text[I]) do Inc(I);
      Target.Add(LowerCase(Copy(Text, StartAt, I - StartAt)));
    end
    else
      Inc(I);
  end;
end;

procedure CollectCodeTokens(Root: TAstNode; Target: THashSet<string>);
// U3-Quelle: alle Identifier aus dem Pascal-AST - AUSSER aus nkField-Knoten.
// nkField sind die published-Feld-Deklarationen (die tragen den Instanz-
// namen nur als Deklaration, nicht als Nutzung). Alles andere (nkCall.Name,
// nkAssign.Name/.TypeRef, Bedingungs-TypeRefs von if/while/case/for, ...)
// enthaelt echte Verwendungen. Iterativer Walk (kein Rekursionsrisiko).
var
  Stack : TList<TAstNode>;
  Cur   : TAstNode;
  I     : Integer;
begin
  if Root = nil then Exit;
  Stack := TList<TAstNode>.Create;
  try
    Stack.Add(Root);
    while Stack.Count > 0 do
    begin
      Cur := Stack[Stack.Count - 1];
      Stack.Delete(Stack.Count - 1);
      if Cur.Kind <> nkField then
      begin
        TokenizeInto(Cur.Name, Target);
        TokenizeInto(Cur.TypeRef, Target);
      end;
      for I := 0 to Cur.Children.Count - 1 do
        Stack.Add(Cur.Children[I]);
    end;
  finally
    Stack.Free;
  end;
end;

procedure CollectPropTokens(Graph: TComponentGraph; Target: THashSet<string>);
// U2-Quelle: alle Referenz-Werte aus DFM-Properties ALLER Komponenten -
// pvkIdent (DataSource=, Action=, PopupMenu=, ActiveControl=, MasterSource=)
// sowie die Rohwerte von pvkSet/pvkItemList/pvkStrList (Images=, Anchors,
// item-Listen). pvkString (Captions/Hints) zaehlt bewusst NICHT als Referenz.
// Der Wert einer Komponente nennt nie ihren EIGENEN Namen -> die globale
// Sammlung ist fuer die Namenssuche aequivalent zu "referenziert von einer
// anderen Komponente".
var
  All  : TList<TComponentNode>;
  Node : TComponentNode;
  Pair : TPair<string, TPropValue>;
begin
  All := Graph.EnumerateAll;
  try
    for Node in All do
      for Pair in Node.Properties do
        case Pair.Value.Kind of
          pvkIdent:
            TokenizeInto(Trim(Pair.Value.RawValue), Target);
          pvkSet, pvkItemList, pvkStrList:
            TokenizeInto(Pair.Value.RawValue, Target);
        end;
  finally
    All.Free;
  end;
end;

procedure CollectStringLiteralTokens(const Src: string; Target: THashSet<string>);
// S3-Quelle: Identifier aus einfach-gequoteten String-Literalen. Wird ein
// Komponentenname als Wort in einem String genannt, koennte er zur Laufzeit
// per Name angesprochen werden (RTTI/FindComponent-artig) -> konservativ
// nicht melden. Toggle-basierter Scanner; '' (escaped quote) wird
// vereinfachend als Ende+Anfang behandelt - fuer die Wortsuche unschaedlich.
var
  I, N     : Integer;
  InStr    : Boolean;
  StartAt  : Integer;
begin
  N := Length(Src);
  InStr := False;
  I := 1;
  while I <= N do
  begin
    if Src[I] = '''' then
    begin
      InStr := not InStr;
      Inc(I);
    end
    else if InStr and IsIdentCh(Src[I]) then
    begin
      StartAt := I;
      while (I <= N) and InStr and IsIdentCh(Src[I]) do Inc(I);
      Target.Add(LowerCase(Copy(Src, StartAt, I - StartAt)));
    end
    else
      Inc(I);
  end;
end;

function HasEventProperty(C: TComponentNode): Boolean;
// U1: mindestens eine belegte Event-Property (OnClick=..., OnChange=...).
// Event-Definition identisch zum FormBinder (IsEventPropertyName), damit
// U1 exakt "C taucht in Binding.Events auf" abbildet.
var
  Pair : TPair<string, TPropValue>;
begin
  Result := False;
  for Pair in C.Properties do
    if IsEventPropertyName(Pair.Key)
       and (Pair.Value.Kind = pvkIdent)
       and (Trim(Pair.Value.RawValue) <> '') then
      Exit(True);
end;

function HasInlineAncestorOrSelf(Node: TComponentNode): Boolean;
// 'inline Foo: ...'-Subtrees (eingebettete Frames / VCL-Collection-Parts)
// sind Laufzeit-Sub-Objekte, keine eigenstaendig entfernbaren Komponenten.
// Analog uDfmSchemaMismatch: die Parent-Kette hochlaufen, weil IsInline nur
// am inline-Knoten selbst steht.
begin
  Result := True;
  while Node <> nil do
  begin
    if Node.IsInline then Exit;
    Node := Node.Parent;
  end;
  Result := False;
end;

function StripPasComments(const S: string): string;
// Ersetzt Pascal-Kommentare (// bis Zeilenende, { ... }, (* ... *)) durch
// Leerzeichen, laesst String-Literale ('...') UNANGETASTET. Noetig fuer die
// S3-Textscans (FindComponent-Guard + String-Literal-Tokens): sonst wuerde
// AUSKOMMENTIERTER Code den Detektor stummschalten - und Kommentare duerfen
// im Projekt NIE als Benutzung/Suppression zaehlen (Review 2026-07-05).
// Zeichenweise, string-/kommentar-aware; Zeilenumbrueche bleiben erhalten.
var
  I, N   : Integer;
  Sb     : TStringBuilder;
begin
  N  := Length(S);
  Sb := TStringBuilder.Create(N);
  try
    I := 1;
    while I <= N do
    begin
      if S[I] = '''' then
      begin
        // String-Literal verbatim uebernehmen ('' = escaped quote bleibt drin).
        Sb.Append(S[I]); Inc(I);
        while I <= N do
        begin
          Sb.Append(S[I]);
          if S[I] = '''' then begin Inc(I); Break; end;
          Inc(I);
        end;
      end
      else if (S[I] = '/') and (I < N) and (S[I + 1] = '/') then
      begin
        while (I <= N) and (S[I] <> #10) and (S[I] <> #13) do
        begin
          if S[I] > ' ' then Sb.Append(' ') else Sb.Append(S[I]);
          Inc(I);
        end;
      end
      else if S[I] = '{' then
      begin
        while (I <= N) and (S[I] <> '}') do
        begin
          if (S[I] = #10) or (S[I] = #13) then Sb.Append(S[I]) else Sb.Append(' ');
          Inc(I);
        end;
        if I <= N then begin Sb.Append(' '); Inc(I); end;   // schliessendes '}'
      end
      else if (S[I] = '(') and (I < N) and (S[I + 1] = '*') then
      begin
        Sb.Append('  '); Inc(I, 2);
        while I <= N do
        begin
          if (S[I] = '*') and (I < N) and (S[I + 1] = ')') then
          begin
            Sb.Append('  '); Inc(I, 2); Break;
          end;
          if (S[I] = #10) or (S[I] = #13) then Sb.Append(S[I]) else Sb.Append(' ');
          Inc(I);
        end;
      end
      else
      begin
        Sb.Append(S[I]); Inc(I);
      end;
    end;
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function ReadSourceText(const APath: string): string;
// Quelltext der .pas fuer die S3-Pruefungen. Lesefehler werden geschluckt -
// U3 (AST-basiert), U4 (Index) und U1/U2 (DFM) laufen dann trotzdem; nur die
// S3-Heuristik ist ohne Text inaktiv.
begin
  Result := '';
  if APath = '' then Exit;
  if not TFile.Exists(APath) then Exit;
  try
    Result := TFile.ReadAllText(APath);
  except
    Result := '';
  end;
end;

class procedure TDfmComponentUnusedDetector.Analyze(Binding: TFormBinding;
  Graph: TComponentGraph; RepoIdx: TDfmRepoIndex; SymIdx: TSymbolReferenceIndex;
  const AOwnUnitPath, AFileName: string; Results: TObjectList<TLeakFinding>);
var
  SrcText      : string;
  CodeTokens   : THashSet<string>;   // U3: Own-Unit-Code-Referenzen
  PropTokens   : THashSet<string>;   // U2: DFM-interne Referenzen
  StrLitTokens : THashSet<string>;   // S3: Namen in String-Literalen
  Comps        : TList<TComponentNode>;
  C            : TComponentNode;
  NameLow      : string;
  F            : TLeakFinding;
begin
  // S1 (WICHTIGSTE REGEL): ohne repo-weiten Cross-Unit-Index gilt jede aus
  // einer anderen Unit benutzte Komponente faelschlich als unused. Im
  // Single-File-/Test-Modus ohne Index deshalb sofort raus - kein Fund.
  if SymIdx = nil then Exit;
  // S5: nur echte Form/Frame/DataModule mit aufgeloester Pascal-Klasse.
  if Binding = nil then Exit;
  if Binding.FormClass = nil then Exit;
  if Binding.FormNode = nil then Exit;
  if Graph = nil then Exit;

  // Kommentare strippen (Review 2026-07-05): sonst schaltet ein
  // AUSKOMMENTIERTER FindComponent(-Aufruf oder ein Komponentenname in einem
  // Kommentar-String die S3-Heuristik faelschlich stumm - Kommentare zaehlen
  // nie als Benutzung. String-Literale bleiben erhalten (S3 braucht sie).
  SrcText := StripPasComments(ReadSourceText(AOwnUnitPath));
  // S3 (file-global): benutzt die Unit FindComponent(, kann JEDE Komponente
  // zur Laufzeit per Name aufgeloest werden -> gar nicht melden.
  if ContainsText(SrcText, 'FindComponent(') then Exit;

  CodeTokens   := THashSet<string>.Create;
  PropTokens   := THashSet<string>.Create;
  StrLitTokens := THashSet<string>.Create;
  Comps        := nil;
  try
    CollectCodeTokens(Binding.UnitNode, CodeTokens);
    CollectPropTokens(Graph, PropTokens);
    CollectStringLiteralTokens(SrcText, StrLitTokens);

    Comps := Graph.EnumerateAll;
    for C in Comps do
    begin
      // Der Root (Form/Frame/DataModule selbst) ist keine "Komponente".
      if C = Binding.FormNode then Continue;
      if C.Name = '' then Continue;

      // S2: persistente Feld-Komponenten (TStringField/TIntegerField/
      // TSqlField/...) definieren das Dataset-Schema und sind zur Laufzeit
      // auch ohne Code-Ref aktiv (Grid/DisplayLabel) -> in v1 komplett
      // ueberspringen (dokumentierte Under-Coverage).
      if EndsText('field', C.ClassRef) then Continue;
      // S4: projekteigene Frame-/Form-Klasse (visuelle Vererbung /
      // eingebettete Frames schwer entscheidbar) -> konservativ skip.
      if (RepoIdx <> nil) and (RepoIdx.GetUnitForClass(C.ClassRef) <> '') then
        Continue;
      // inline/inherited-Subtrees: Laufzeit-Sub-Objekte bzw. in Parent-Form
      // deklarierte Member -> konservativ skip (analog SchemaMismatch).
      if C.IsInherited or HasInlineAncestorOrSelf(C) then Continue;

      NameLow := LowerCase(C.Name);

      // U1: interaktive Event-Bindung.
      if HasEventProperty(C) then Continue;
      // U2: DFM-interne Referenz (DataSource=, Action=, ActiveControl=, ...).
      if PropTokens.Contains(NameLow) then Continue;
      // U3: Referenz im eigenen Pascal-Code (ausser der Feld-Deklaration).
      if CodeTokens.Contains(NameLow) then Continue;
      // S3 (per Komponente): Name in einem String-Literal -> koennte per
      // Name angesprochen werden -> konservativ skip.
      if StrLitTokens.Contains(NameLow) then Continue;
      // U4 (FP-KERN): Cross-Unit-Referenz aus einer ANDEREN Unit.
      if SymIdx.HasExternalRefs(NameLow, AOwnUnitPath) then Continue;

      // -> nirgends referenziert.
      F            := TLeakFinding.Create;
      F.FileName   := AFileName;
      F.MethodName := Binding.FormClass.Name;
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar := Format(
        'DFM component %s (%s) is never referenced in code, other units or the DFM (possibly leftover after refactoring)',
        [C.Name, C.ClassRef]);
      F.SetKind(fkDfmComponentUnused);  // Confidence := fcLow (KindDefaultConfidence)
      Results.Add(F);
    end;
  finally
    Comps.Free;
    StrLitTokens.Free;
    PropTokens.Free;
    CodeTokens.Free;
  end;
end;

end.
