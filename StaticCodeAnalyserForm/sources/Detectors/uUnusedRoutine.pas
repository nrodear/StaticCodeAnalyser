unit uUnusedRoutine;

// Detektor: top-level Procedure/Function in einer Unit wird nirgendwo
// aufgerufen (SCA164).
//
// Schliesst die Luecke zwischen SCA147 (UnusedPrivateMethod - nur class
// private) und SCA148+ (Visibility-Check - nur class public). Beispiel das
// vorher durch alle Maschen fiel:
//
//   unit u;
//   interface
//     procedure ExportedHelper;     // ggf. cross-unit gerufen
//   implementation
//     procedure InternalHelper;     // <- nur impl, kein Aufruf => DEAD
//     begin
//       ShowMessage('hi');
//     end;
//   end.
//
// Erkennung (analog SonarDelphi UnusedRoutineCheck, Single-File-Scope):
//   1. Walk alle nkMethod-Direct-Children von nkImplementation.
//   2. Filter: nur Standalone-Routinen (kein '.' im Namen). Klassen-
//      Methoden-Implementierungen (TFoo.Bar) sind durch SCA147 / SCA148+
//      abgedeckt, oder durch zukuenftige v2-Erweiterung dieses Detektors.
//   3. FP-Guards (in dieser Reihenfolge):
//        a) Konstruktor / Destruktor (nicht direkt callbar)
//        b) override / virtual; abstract / message / dynamic - Direktive
//           in TypeRef impliziert cross-class oder system dispatch
//        c) 'register' als Top-Level (IDE-Plugin-Bootstrap)
//        d) Enumerator-Trio (MoveNext / GetEnumerator / Current) -
//           implizit via for-in-Loop gerufen
//        e) Forward-Decl im interface-Teil der eigenen Unit (potenzieller
//           Cross-Unit-Konsument)
//   4. Wortgrenz-Match im stripped File-Text via TDetectorUtils.
//      StripStringsAndComments. Matches innerhalb der eigenen Routine
//      zaehlen NICHT (self-/recursive-Call != Use). Routine-Range:
//      [Mth.Line .. NextStandaloneRoutineStart-1].
//
// Severity: lsHint, Type: ftCodeSmell, Confidence: fcHigh fuer pure
// implementation-only Routinen (keine interface-Forward-Decl).
//
// Bekannte Limitierungen (MVP, dokumentiert in Konzept_SCA164_UnusedRoutine.md):
//   * Interface-Forward-Deklarierte Routinen werden NICHT geflagged - sie
//     koennten cross-unit gerufen werden, und der vorhandene gSymbolRefIndex
//     indexiert keine Bare-Calls auf top-level Routinen.
//   * `forward;`-Direktive innerhalb des implementation-Teils + spaeterer
//     Impl-Block der gleichen Routine: aktuell False-Negative (Forward-Decl-
//     Line zaehlt als externer Caller des Impls und umgekehrt). Selten in
//     modernem Code; Suppression-Marker als Escape.
//   * RTTI- und [Attribute]-Konsumenten werden nicht erkannt - Escape via
//     `// noinspection UnusedRoutine` an der Routine.
//   * DFM-Event-Handler werden in v1 nicht via DFM-Index gegengeprueft (die
//     sind ohnehin Klassen-Methoden und damit unter Klassenname qualifiziert
//     - dieses Detektor flaggt sie also gar nicht erst).
//   * Interface-Implementierungen sind ebenfalls Klassen-Methoden und werden
//     daher in v1 nicht beruehrt.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnusedRoutineDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // True wenn der Methoden-Direktiven-String einen der Modifier enthaelt
    // die Routine "von aussen referenziert" implizieren (override, abstract,
    // message, virtual). Match auf das von ParseMethodDirectives erzeugte
    // TypeRef-Format: 'procedure[:ret];dir1;dir2'.
    class function HasExternalReferenceDirective(const TypeRef: string): Boolean; static;
    // True wenn die Routine ein Konstruktor oder Destruktor ist - nicht
    // wie eine normale Procedure gerufen. Match an TypeRef-Praefix.
    class function IsCtorOrDtor(const TypeRef: string): Boolean; static;
    // True wenn der Name in der Enumerator-Whitelist liegt (MoveNext /
    // GetEnumerator / Current) - implizit via `for X in Y do` gerufen.
    class function IsEnumeratorRoutine(const Name: string): Boolean; static;
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

const
  // Routinen-Namen die per Konvention implizit gerufen werden.
  ENUMERATOR_NAMES : array[0..2] of string = (
    'movenext', 'getenumerator', 'current'
  );

class function TUnusedRoutineDetector.HasExternalReferenceDirective(
  const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  // ';dir' Pattern damit 'override' im Method-Body (unwahrscheinlich aber
  // moeglich bei Custom-Attributes) nicht matched. ';dynamic' verhaelt sich
  // identisch zu ';virtual' fuer Subclass-Dispatch.
  Result := (Pos(';override', Low)  > 0) or
            (Pos(';virtual',  Low)  > 0) or
            (Pos(';abstract', Low)  > 0) or
            (Pos(';message',  Low)  > 0) or
            (Pos(';dynamic',  Low)  > 0) or
            (Pos(';forward',  Low)  > 0); // ;forward: Decl ohne Body - der
                                          // spaetere Impl wird separat geprueft.
end;

class function TUnusedRoutineDetector.IsCtorOrDtor(
  const TypeRef: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(TypeRef);
  // TypeRef beginnt mit dem MethKind aus dem Parser - 'constructor' /
  // 'destructor' / 'procedure' / 'function' / 'operator'.
  Result := StartsText('constructor', Low) or
            StartsText('destructor',  Low);
end;

class function TUnusedRoutineDetector.IsEnumeratorRoutine(
  const Name: string): Boolean;
var
  Low, EN : string;
begin
  Low := LowerCase(Name);
  for EN in ENUMERATOR_NAMES do
    if Low = EN then Exit(True);
  Result := False;
end;

class procedure TUnusedRoutineDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Impls       : TList<TAstNode>;
  Impl        : TAstNode;
  Mth         : TAstNode;
  Standalones : TList<TAstNode>;
  Lines       : TStringList;
  Cached      : Boolean;
  Code        : string;
  LineForChar : TArray<Integer>;  // Char-Pos -> 0-basierter Quell-Zeilenindex
  InterfaceMethods : TStringList; // alle nkMethod-Namen unter nkInterface
  i           : Integer;
  IFList      : TList<TAstNode>;
  IFNode      : TAstNode;
  Fwd         : TAstNode;

  function NextStartAfter(StartLine: Integer): Integer;
  // Linie der naechsten Standalone-Routine nach StartLine, oder MaxInt
  // (= bis Datei-Ende) wenn es keine mehr gibt. Parser liefert nkMethod-
  // Knoten in File-Order, also ist Standalones bereits sortiert.
  var
    k : Integer;
  begin
    for k := 0 to Standalones.Count - 1 do
      if Standalones[k].Line > StartLine then Exit(Standalones[k].Line);
    Result := MaxInt;
  end;

  function HasExternalCaller(const MethName: string;
    const OwnStart, OwnEnd: Integer): Boolean;
  var
    RE        : TRegEx;
    M         : TMatch;
    MatchLine : Integer;
  begin
    Result := False;
    if MethName = '' then Exit;
    // Case-insensitive regex statt Lowercase-Kopie + Lower-Comparison.
    RE := TRegEx.Create('\b' + MethName + '\b', [roIgnoreCase]);
    for M in RE.Matches(Code) do
    begin
      // O(1) Zeilen-Lookup ueber das TDetectorUtils-LineForChar-Array.
      // M.Index ist 1-basiert (Delphi), Array 0-basiert, Source-Line
      // 0-basiert -> +1 fuer 1-basierten Output (Mth.Line ist 1-basiert).
      MatchLine := LineForChar[M.Index - 1] + 1;
      // Match in der eigenen Routine (Header- oder Body-Zeile) = self-Call,
      // nicht als Verwendung zaehlen.
      if (MatchLine >= OwnStart) and (MatchLine < OwnEnd) then Continue;
      Exit(True);
    end;
  end;

var
  MethName : string;
  Modifiers: string;
  RoutineEnd: Integer;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    // Strippt Strings + Kommentare und liefert die Char->Quellzeile-Map mit -
    // ersetzt den Zwilling von uUnusedPrivateMethod und sparte das O(n)-pro-
    // Match LineOfPos durch direkten Array-Lookup.
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineForChar);

    // Interface-Method-Namen EINMAL einsammeln statt pro Routine die ganze
    // AST mit FindAll(nkInterface) zu traversieren.
    InterfaceMethods := TStringList.Create;
    try
      InterfaceMethods.CaseSensitive := False;
      InterfaceMethods.Sorted        := True;
      InterfaceMethods.Duplicates    := dupIgnore;
      IFList := UnitNode.FindAll(nkInterface);
      try
        for IFNode in IFList do
          for Fwd in IFNode.Children do
            if (Fwd.Kind = nkMethod) and (Fwd.Name <> '') then
              InterfaceMethods.Add(Fwd.Name);
      finally
        IFList.Free;
      end;

      Standalones := TList<TAstNode>.Create;
      try
        // Phase 1: Standalone-Kandidaten sammeln. Multiple nkImplementation-
        // Sektionen waeren ungewoehnlich, FindAll deckt es ab.
        Impls := UnitNode.FindAll(nkImplementation);
        try
          for Impl in Impls do
            for Mth in Impl.Children do
              if (Mth.Kind = nkMethod) and (Pos('.', Mth.Name) = 0) then
                Standalones.Add(Mth);
        finally
          Impls.Free;
        end;

        // Phase 2: pro Kandidat FP-Guards + External-Caller-Check.
        for i := 0 to Standalones.Count - 1 do
        begin
          Mth       := Standalones[i];
          MethName  := Mth.Name;
          Modifiers := Mth.TypeRef;

          // FP-Guards
          if IsCtorOrDtor(Modifiers)                  then Continue;
          if HasExternalReferenceDirective(Modifiers) then Continue;
          if SameText(MethName, 'register')           then Continue;
          if IsEnumeratorRoutine(MethName)            then Continue;
          if InterfaceMethods.IndexOf(MethName) >= 0  then Continue;

          RoutineEnd := NextStartAfter(Mth.Line);
          if HasExternalCaller(MethName, Mth.Line, RoutineEnd) then Continue;

          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := MethName;
          F.LineNumber := IntToStr(Mth.Line);
          F.MissingVar := Format(
            'Top-level routine %s appears unused (no caller within the unit, ' +
            'no interface forward-declaration)', [MethName]);
          F.SetKind(fkUnusedRoutine);
          // Phase 1 ist hochkonfident: kein cross-unit-Confound (kein
          // interface-Decl), self-Calls sind ausgenommen.
          F.Confidence := fcHigh;
          Results.Add(F);
        end;
      finally
        Standalones.Free;
      end;
    finally
      InterfaceMethods.Free;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
