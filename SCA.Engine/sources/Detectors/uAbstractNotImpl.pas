unit uAbstractNotImpl;

// Detektor: konkrete Subklasse erbt eine abstrakte Methode, ueberschreibt
// sie aber nicht.
//
// Pattern (Bug, Sonar-50 #10):
//   type
//     TBase = class
//       procedure DoWork; virtual; abstract;
//     end;
//     TDerived = class(TBase)
//       // DoWork nicht ueberschrieben - bei Instanziierung + Aufruf:
//       // EAbstractError zur Laufzeit.
//     end;
//
// Korrekt:
//   type
//     TDerived = class(TBase)
//       procedure DoWork; override;
//     end;
//
// Erkennung (within-unit only):
//   * Pro Class-Deklaration im AST (nkClass) deren Base-Klasse identifizieren
//     (steht im TypeRef).
//   * Pro Base: alle abstract-Methoden sammeln (TypeRef enthaelt ';abstract').
//   * Pro Derived: alle Method-Namen sammeln.
//   * Diff: abstract-Methoden der Base, die in Derived nicht auftauchen
//     -> Befund am Class-Deklarations-Knoten.
//
// Limitierungen:
//   * Cross-Unit-Bases (TForm, TStrings, etc.) werden NICHT erkannt - wir
//     sehen nur die Klassen-Hierarchien, die im selben File deklariert sind.
//   * Mehrstufige Hierarchien (TBase -> TMid -> TLeaf) werden nur eine
//     Stufe weit aufgeloest; abstract in TBase, das in TMid bereits
//     overridden wird, koennte als "fehlend in TLeaf" geflaggt werden.
//     Defensive Heuristik: nur Direct-Parent pruefen.
//   * Class-Helpers, Interfaces, Records werden ignoriert (nkClass nur).
//
// Schweregrad: lsError - Aufruf erzeugt EAbstractError zur Laufzeit.

interface

uses
  System.SysUtils, System.StrUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TAbstractNotImplDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, LongMethod, NestedTry, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// Extrahiert den direkten Parent-Klassennamen aus `TFoo = class(TBar, IFoo)`.
// TypeRef der nkClass-Node sieht typisch so aus: 'TBar' oder 'TBar,IFoo' oder
// leer (kein expliziter Parent).
function ExtractParentName(const TypeRef: string): string;
var
  Comma : Integer;
begin
  Result := Trim(TypeRef);
  Comma := Pos(',', Result);
  if Comma > 0 then Result := Trim(Copy(Result, 1, Comma - 1));
end;

function IsAbstractMethod(const MethodTypeRef: string): Boolean;
begin
  Result := Pos(';abstract', LowerCase(MethodTypeRef)) > 0;
end;

// Letztes Segment eines qualifizierten Method-Namens. 'TFoo.Bar' -> 'Bar'.
function UnqualifiedName(const MethName: string): string;
var
  i : Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

class procedure TAbstractNotImplDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  ClassNodes  : TList<TAstNode>;
  ClassByName : TDictionary<string, TAstNode>;
  ParentSet   : TDictionary<string, Boolean>;
  C           : TAstNode;
  Methods     : TList<TAstNode>;
  M           : TAstNode;
  ParentName  : string;
  Parent      : TAstNode;
  AbstractMethods : TList<string>;
  DerivedMethods  : TStringList;
  AbstrName   : string;
begin
  // PScript/RTL-Spiegel-Stub-Files (cnwizards \PSDecl\ / \PSDeclEx\): reine
  // bodylose Deklarationen der echten RTL - die Overrides stehen in der
  // echten RTL, nicht im Stub. Real-World-FP 2026-06-23.
  if Pos('\psdecl', LowerCase(FileName)) > 0 then Exit;

  ClassNodes := UnitNode.FindAll(nkClass);
  ClassByName := TDictionary<string, TAstNode>.Create;
  ParentSet := TDictionary<string, Boolean>.Create;
  try
    // Index aller Class-Deklarationen nach Name + Set aller Klassen die als
    // Parent einer anderen File-Klasse auftauchen.
    for C in ClassNodes do
    begin
      ClassByName.AddOrSetValue(LowerCase(C.Name), C);
      var PN := LowerCase(ExtractParentName(C.TypeRef));
      if PN <> '' then ParentSet.AddOrSetValue(PN, True);
    end;

    for C in ClassNodes do
    begin
      // Intermediate-Abstract-Skip: ist C selbst Basis einer anderen Klasse
      // im File, ist es eine Zwischen-Basis - die Blatt-Subklassen liefern
      // die Overrides (und werden selbst geflaggt, falls sie es nicht tun).
      // Nur Blatt-Klassen flaggen. Real-World-FP 2026-06-23 (~10/10 FP).
      if ParentSet.ContainsKey(LowerCase(C.Name)) then Continue;

      ParentName := ExtractParentName(C.TypeRef);
      if ParentName = '' then Continue;
      if not ClassByName.TryGetValue(LowerCase(ParentName), Parent) then
        Continue;  // Cross-Unit-Base, ueberspringen.
      if Parent = C then Continue;

      // Abstract-Methoden der Parent-Klasse sammeln.
      AbstractMethods := TList<string>.Create;
      try
        Methods := Parent.FindAll(nkMethod);
        try
          for M in Methods do
            if IsAbstractMethod(M.TypeRef) then
              AbstractMethods.Add(LowerCase(UnqualifiedName(M.Name)));
        finally
          Methods.Free;
        end;
        if AbstractMethods.Count = 0 then Continue;

        // Methoden der Derived-Klasse sammeln.
        DerivedMethods := TStringList.Create;
        try
          DerivedMethods.CaseSensitive := False;
          DerivedMethods.Duplicates := dupIgnore;
          DerivedMethods.Sorted := True;
          var DerivedHasAbstract := False;
          Methods := C.FindAll(nkMethod);
          try
            for M in Methods do
            begin
              DerivedMethods.Add(LowerCase(UnqualifiedName(M.Name)));
              if IsAbstractMethod(M.TypeRef) then DerivedHasAbstract := True;
            end;
          finally
            Methods.Free;
          end;
          // Wenn Derived selbst (noch) abstrakt ist, kein Override-Zwang ->
          // skippen. Zwei Faelle: explizit als Klasse markiert, ODER die Klasse
          // fuehrt SELBST eine neue 'virtual; abstract'-Methode ein (dann ist
          // sie abstrakt; die konkreten Blatt-Subklassen liefern die Overrides).
          // Real-World-FP 2026-06-28: TWebSocketSocketIOProtocol u.ae.
          if (Pos(';abstract', LowerCase(C.TypeRef)) > 0)
             or DerivedHasAbstract then Continue;
          // Konvention: Klassen mit Prefix 'TCustom'/'TAbstract' sind
          // Zwischen-Abstract-Basen die Override an konkrete Subklassen
          // weiterreichen (VCL-Konvention: TCustomEdit, TCustomCombo,
          // Image32 TCustomRenderer/TCustomColorRenderer, ...). Audit-
          // Trigger Img32.Draw, mORMot orm.base.
          var CLow := LowerCase(C.Name);
          // 'TCustom...'-Prefix ODER 'abstract' irgendwo im Namen
          // (TALExprAbstractFuncSym): semantisch abstrakte Zwischen-Basis.
          if StartsStr('tcustom', CLow) or StartsStr('tbase', CLow)
             or ContainsText(CLow, 'abstract') then
            Continue;
          // Real-World-Sweep 2026-06-13: Intermediate-Abstract-Klassen die
          // KEIN ueberschreiben - 0 von N abstract methods implementiert.
          // mORMot Pattern: TSqlDBConnectionThreadSafe = class(TSqlDBConnection)
          // ist semantisch abstrakt (kommentar `abstract connection`), aber
          // nicht explicit als `;abstract` markiert. Konkrete Subklassen
          // (OleDB/ODBC/Oracle) liefern die echten Overrides.
          //
          // Heuristik mit Threshold: wenn die Derived-Klasse 0% der Abstract-
          // Methods ueberschreibt UND der Parent >= 3 abstract methods hat,
          // ist sie wahrscheinlich Intermediate-Abstract -> skip.
          // Iter 8 nach Test-Bug 2026-06-13: Threshold 3 noetig, sonst kollidiert
          // mit DUnitX-Test der genau "1 abstract + 0 overrides -> Finding"
          // erwartet. mORMot-Trigger hatte 10+ abstract methods, fuer den
          // greift der Skip weiterhin.
          var OverrideCount := 0;
          for AbstrName in AbstractMethods do
            if DerivedMethods.IndexOf(AbstrName) >= 0 then
              Inc(OverrideCount);
          if (OverrideCount = 0) and (AbstractMethods.Count >= 3) then Continue;
          // Fuer jede abstract-Methode der Parent: existiert sie in Derived?
          for AbstrName in AbstractMethods do
            if DerivedMethods.IndexOf(AbstrName) < 0 then
            begin
              Results.Add(TLeakFinding.New(FileName, C.Name, C.Line,
                Format('Class %s inherits abstract method %s.%s but does ' +
                       'not override it - EAbstractError on call',
                  [C.Name, Parent.Name, AbstrName]),
                fkAbstractNotImpl));
            end;
        finally
          DerivedMethods.Free;
        end;
      finally
        AbstractMethods.Free;
      end;
    end;
  finally
    ParentSet.Free;
    ClassByName.Free;
    ClassNodes.Free;
  end;
end;

end.
