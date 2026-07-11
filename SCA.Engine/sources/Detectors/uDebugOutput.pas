unit uDebugOutput;

// Detektor fuer Debug-Ausgaben in Produktionscode.
// Erkennt Aufrufe von:
//   WriteLn / Write      (Console-Output - meist vergessen)
//   ShowMessage(Pos)     (Dialog-Popup - stoert in Produktion)
//   OutputDebugString    (Debug-Ausgabe)
//
// Scope-Entscheidung 2026-07-11 (Real-World-FP-Audit, User): InputBox/InputQuery
// (Eingabe-Primitive - liefern einen Wert statt Output) und MessageDlg/
// MessageDlgPos (bewusste strukturierte UI: mt*-Dialogtyp + [mb*]-Button-Set)
// sind KEINE vergessenen Debug-Ausgaben und wurden aus den Zielen entfernt.
// ShowMessage bleibt als klassisches Quick-Debug-Popup ein Ziel.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDebugOutputDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file IfElseBegin, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  DEBUG_CALLS : array[0..4] of string = (
    'writeln(', 'writeln ',
    'showmessage(', 'showmessagepos(',
    'outputdebugstring('
  );

// True wenn die Position AtPos im Text innerhalb eines String-Literals
// liegt. Pascal-Strings sind durch ''-Apostrophe begrenzt; '' (double-
// apostroph) ist Escape fuer ein literales '. Heuristik: zaehle bare-
// Apostrophe (= ohne ''-Escape) vor AtPos. Ungerade -> wir sind im
// String. Praktisch schaltet das die FP-Klasse aus, in der UI-Hint-Texte
// oder Code-Doku als String-Literal Patterns wie WriteLn/ShowMessage als
// Pseudo-Beispiele enthalten - der Detector matcht das sonst als echten
// Aufruf (zu sehen in uFixHint.pas / uTodoComment.pas).
function IsInsideStringLiteral(const Text: string; AtPos: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  i := 1;
  while i < AtPos do
  begin
    if Text[i] = '''' then
    begin
      if (i + 1 < AtPos) and (Text[i + 1] = '''') then
        Inc(i, 2)   // '' = Escape, kein Quote-Toggle
      else
      begin
        Result := not Result;
        Inc(i);
      end;
    end
    else
      Inc(i);
  end;
end;

class procedure TDebugOutputDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls      : TList<TAstNode>;
  N          : TAstNode;
  CondRanges : TList<TAstNode>;   // Welle 2: nkConditionalRange (DEBUG-guarded {$IFDEF})

  // Welle 2 (Core-Detektoren-Architektur): True wenn Line in einer DEBUG-guarded
  // {$IFDEF DEBUG}-Range liegt (nkConditionalRange-Marker: Line=Start, TypeRef=Ende).
  function LineInDebugRange(Line: Integer): Boolean;
  var R: TAstNode;
  begin
    Result := False;
    for R in CondRanges do
      if SameText(R.Name, 'DEBUG')   // nur DEBUG-guarded Ranges (Welle 3: es gibt jetzt auch non-DEBUG)
         and (Line >= R.Line) and (Line <= StrToIntDef(R.TypeRef, R.Line)) then
        Exit(True);
  end;

  // Helper - prueft einen Call-/RHS-String gegen die DEBUG_CALLS-Liste
  // und emittiert ggf. einen Befund. Wird sowohl fuer nkCall.Name als
  // auch nkAssign.TypeRef aufgerufen (z.B. 's := InputBox(...)' hat
  // den InputBox-Aufruf in nkAssign.TypeRef, nicht als eigene nkCall).
  procedure CheckCallText(const CallText: string; Line: Integer);
  var
    NameLow : string;
    Found   : string;
  begin
    NameLow := CallText.ToLower;
    Found   := '';
    for var Kw in DEBUG_CALLS do
    begin
      var p := Pos(Kw, NameLow);
      if p = 0 then Continue;
      // Doku-/UI-Hint-Pattern (z.B. Result.Before := '... WriteLn(...) ...'):
      // wenn das Match innerhalb eines String-Literals liegt, ist es kein
      // echter Aufruf - skip.
      if IsInsideStringLiteral(CallText, p) then Continue;
      if p > 1 then
      begin
        var Prev := NameLow[p - 1];
        if CharInSet(Prev, ['a'..'z', '0'..'9', '_']) then Continue;
        // Real-World-FP-Audit 2026-07-10: member-qualifizierter Aufruf
        // (Self.WriteLn / FConsoleWriter.WriteLn / AWriter.WriteLn) ist eine
        // eigene Logging-/Writer-Methode der Klasse, KEIN RTL-Debug-Output.
        // Ausnahme: Qualifier = 'System' (das IST System.WriteLn). Unqualifiziertes
        // WriteLn/ShowMessage bleibt Befund. DUnitX-Console-Writer-FP-Cluster.
        if Prev = '.' then
        begin
          var qEnd := p - 2;
          var qStart := qEnd;
          while (qStart >= 1) and
                CharInSet(NameLow[qStart], ['a'..'z', '0'..'9', '_']) do
            Dec(qStart);
          if Copy(NameLow, qStart + 1, qEnd - qStart) <> 'system' then
            Continue;
        end;
      end;
      var EndPos := p;
      while (EndPos <= Length(NameLow)) and
            CharInSet(NameLow[EndPos], ['a'..'z']) do
        Inc(EndPos);
      Found := Copy(NameLow, p, EndPos - p);
      Break;
    end;
    if Found = '' then Exit;
    // Welle 2: Debug-Ausgabe in einem DEBUG-guarded {$IFDEF DEBUG}-Block ist
    // Absicht (aus Release-Builds auskompiliert), kein vergessener Produktions-
    // Debug -> unterdruecken. Additiv per nkConditionalRange-Marker.
    if LineInDebugRange(Line) then Exit;
    Results.Add(TLeakFinding.New(FileName, '', Line,
      'Debug output: ' + Found.Trim, fkDebugOutput));
  end;

var
  Assigns : TList<TAstNode>;
begin
  CondRanges := UnitNode.FindAll(nkConditionalRange);   // Welle 2 (additiv)
  try
    Calls := UnitNode.FindAll(nkCall);
    try
      for N in Calls do
        CheckCallText(N.Name, N.Line);
    finally
      Calls.Free;
    end;
    // Auch nkAssign-RHS pruefen - Aufrufe wie 's := InputBox(...)' oder
    // 'Result := WriteLnHelper(...)' leben im TypeRef der Zuweisung.
    Assigns := UnitNode.FindAll(nkAssign);
    try
      for N in Assigns do
        CheckCallText(N.TypeRef, N.Line);
    finally
      Assigns.Free;
    end;
  finally
    CondRanges.Free;
  end;
end;

end.
