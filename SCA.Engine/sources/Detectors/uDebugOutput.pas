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

  // --- Gate A (SCA017-FP-Paket 2026-08-27) ---------------------------------
  // 'WriteLn(F, ...)' auf ein Text-Handle ist Datei-/Drucker-I/O, keine
  // vergessene Konsolenausgabe. Der Korpus wird von genau diesem Muster
  // dominiert: von 2.717 code-echten WriteLn(-Stellen haengen 980 an einem
  // belegten Handle (36%) - allein die beiden SynGen-Codegeneratoren
  // (Dev-Cpp/HeidiSQL SynGenUnit.pas) stellen 806, der Makefile-Schreiber
  // Dev-Cpp/Compiler.pas 60, doublecmd uexceptions.pas (Crashlog) 8.
  //
  // Typnamen, die ein Text-Handle bezeichnen (getrimmt + lowercase
  // verglichen). 'Text' ist der Sprachtyp, 'TextFile' sein Alias,
  // 'System.Text' die qualifizierte Form (doublecmd uexceptions.pas:70).
  TEXT_HANDLE_TYPES : array[0..2] of string = (
    'text', 'textfile', 'system.text'
  );

  // Knotenarten, in denen eine Handle-Deklaration stehen kann. nkField ist
  // BEWUSST dabei und nicht nur nkLocalVar/nkParam: das groesste Einzelcluster
  // des Korpus deklariert sein Handle als KLASSENFELD
  // (SynGenUnit.pas:155 'OutFile: TextFile;', 404 bzw. 402 Funde). Ein Feld
  // dieses Typs ist genauso eindeutig ein Datei-Handle wie eine lokale
  // Variable - der Zweig kostet nichts und macht die Regel unabhaengig davon,
  // ob der oeffnende AssignFile-Aufruf in derselben Unit steht.
  HANDLE_DECL_KINDS : array[0..2] of TNodeKind = (
    nkLocalVar, nkParam, nkField
  );

  // RTL-Routinen, deren ERSTES Argument per Sprachdefinition ein Datei-Handle
  // ist. Zweite, typunabhaengige Beweisquelle - sie traegt die Faelle, in
  // denen der Typ nicht am Knoten haengt (Handle aus einem include, aus einem
  // Record-Feld oder ueber eine Sichtbarkeitsgrenze hinweg deklariert).
  // Der Match ist ein Praefix auf dem ganzen Aufrufnamen: ein qualifizierter
  // 'Bitmap.Assign(Other)' faengt nicht mit 'assign(' an und kann deshalb
  // keinen Namen in die Handle-Menge schmuggeln.
  // Gegenpruefung 2026-08-27 (MAJOR): 'assign(' und 'append(' sind
  // WIEDER RAUS - beide Namen sind ausserhalb der RTL-Datei-API belegt.
  // Belegter Schaden: mormot.core.text.Append(var Text: RawUtf8; const
  // Added: RawByteString) holte in test.orm.core.pas ueber 'Append(s,
  // ''u'')' (:543/:553) die STRING-Variable 's' in die Handle-Menge und
  // unterdrueckte damit das echte 'writeln(s)' in :703. Die vier
  // uebrigen Namen sind eindeutig; laut Nachmessung haengt keine der
  // ~985 richtigen Unterdrueckungen an den beiden gestrichenen - sie
  // alle kommen ueber den Deklarations-Zweig.
  FILE_OPEN_CALLS : array[0..3] of string = (
    'assignfile(', 'assignprn(', 'rewrite(', 'closefile('
  );

  // Die RTL-Standardhandles sind KEIN Datei-I/O - 'WriteLn(Output, ...)' und
  // 'WriteLn(ErrOutput, ...)' schreiben auf Konsole bzw. stderr und bleiben
  // exakt der Fund, den SCA017 sucht. Whitelist, die auch dann greift, wenn
  // eine Unit den Namen zusaetzlich selbst deklariert
  // (Beleg LoggerPro.ConsoleAppender.pas:427 'Writeln(ErrOutput, ...)').
  // stdout/stderr ergaenzt (Gegenpruefung 2026-08-27): der Korpus hat 11
  // 'WriteLn(StdErr, ...)'-Stellen (gnugettext-Familie, CEF4Delphi); wo
  // eine Unit StdErr selbst per AssignFile/Rewrite umleitet, haette der
  // Oeffner-Zweig sonst eine echte stderr-Ausgabe stummgeschaltet.
  STD_TEXT_HANDLES : array[0..4] of string = (
    'output', 'erroutput', 'input', 'stdout', 'stderr'
  );

// True wenn die Position AtPos im Text innerhalb eines String-Literals
// liegt. Pascal-Strings sind durch ''-Apostrophe begrenzt; '' (double-
// apostroph) ist Escape fuer ein literales '. Heuristik: zaehle bare-
// Apostrophe (= ohne ''-Escape) vor AtPos. Ungerade -> wir sind im
// String. Praktisch schaltet das die FP-Klasse aus, in der UI-Hint-Texte
// oder Code-Doku als String-Literal Patterns wie WriteLn/ShowMessage als
// Pseudo-Aufrufe enthalten - der Detector matcht das sonst als echten
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

// Gate D (SCA017-FP-Paket 2026-08-27): in der SENKE eines Logging-Frameworks
// ist die Konsolen-/OutputDebugString-Ausgabe die Implementierung der Regel-
// Abhilfe, kein vergessener Debug-Rest - "nimm statt WriteLn einen Logger"
// waere dort zirkulaer. Belegt an LoggerPro.ConsoleAppender.pas:427/429 und
// LoggerPro.OutputDebugStringAppender.pas:87, im Korpus je 3 Vendoring-Kopien
// (delphimvcframework x3) = 9 Funde.
// Nur der BASENAME entscheidet, nicht der Pfad: ein Verzeichnis 'logger\' sagt
// nichts darueber, ob die einzelne Unit die Senke ist (LoggerPro.AnsiColors.pas
// liegt daneben und traegt ohnehin keinen Code-Fund - seine WriteLn stehen in
// ///-Doku, und Kommentare zaehlen nie als Code).
function IsLoggerSinkFile(const AFileName: string): Boolean;
var
  Base : string;
begin
  Base   := LowerCase(ChangeFileExt(ExtractFileName(AFileName), ''));
  Result := (Pos('logger', Base) > 0) or (Pos('appender', Base) > 0);
end;

// Erstes Argument eines Aufrufs als nackter Bezeichner. ArgStart zeigt im
// BEREITS kleingeschriebenen Aufruftext hinter die oeffnende Klammer.
// Liefert '' wenn dort kein unqualifizierter Bezeichner mit direkt folgender
// Argumentgrenze steht - also bei Literalen, geschachtelten Aufrufen und bei
// 'F.Handle' / 'F^' / 'Arr[0]'. Das ist die konservative Richtung: nur was
// namensgleich mit einem belegten Handle ist, darf den Fund unterdruecken.
function FirstArgIdent(const LowText: string; ArgStart: Integer): string;
var
  i : Integer;
begin
  Result := '';
  if ArgStart < 1 then Exit;
  i := ArgStart;
  while (i <= Length(LowText)) and
        CharInSet(LowText[i], ['a'..'z', '0'..'9', '_']) do
    Inc(i);
  if i = ArgStart then Exit;
  if (i > Length(LowText)) or not CharInSet(LowText[i], [',', ')']) then Exit;
  Result := Copy(LowText, ArgStart, i - ArgStart);
end;

// Modifier-Praefix eines nkParam-Namens abschneiden. Der Parser legt einen
// Parameter mit Modifier als 'var F' / 'const S' / 'out X' im NAMEN ab
// (uParser2.pas:1609-1610). Ohne diesen Strip liefe der Handle-Vergleich fuer
// jeden var-Parameter leer - und genau so deklariert Dev-Cpp/Compiler.pas
// seine sieben Makefile-Schreiber ('procedure NewMakeFile(var F: TextFile)',
// :110-116, 60 Funde). Derselbe Praefix hat in einem frueheren Paket schon
// einmal ein Gate wirkungslos gemacht.
function StripParamModifier(const AName: string): string;
var
  SpacePos : Integer;
begin
  Result   := Trim(AName);
  SpacePos := LastDelimiter(' ', Result);
  if SpacePos > 0 then
    Result := Copy(Result, SpacePos + 1, Length(Result) - SpacePos);
end;

function IsTextHandleType(const ATypeRef: string): Boolean;
var
  LowType : string;
  T       : string;
begin
  LowType := LowerCase(Trim(ATypeRef));
  for T in TEXT_HANDLE_TYPES do
    if LowType = T then Exit(True);
  Result := False;
end;

function IsStdTextHandle(const ALowIdent: string): Boolean;
var
  S : string;
begin
  for S in STD_TEXT_HANDLES do
    if ALowIdent = S then Exit(True);
  Result := False;
end;

// Baut die Handle-Menge einer Unit (lowercase Bezeichner). Calls wird
// durchgereicht statt neu gesucht - der Aufrufer hat die Liste ohnehin schon.
procedure CollectTextHandles(UnitNode: TAstNode; Calls: TList<TAstNode>;
  Handles: TDictionary<string, Boolean>);
var
  DeclKind : TNodeKind;
  Decls    : TList<TAstNode>;
  N        : TAstNode;
  NameLow  : string;
  Opener   : string;

  procedure AddHandle(const AName: string);
  var
    LowName : string;
  begin
    LowName := LowerCase(Trim(AName));
    if LowName <> '' then
      Handles.AddOrSetValue(LowName, True);
  end;

begin
  for DeclKind in HANDLE_DECL_KINDS do
  begin
    Decls := UnitNode.FindAll(DeclKind);
    try
      for N in Decls do
        if IsTextHandleType(N.TypeRef) then
          AddHandle(StripParamModifier(N.Name));
    finally
      Decls.Free;
    end;
  end;

  for N in Calls do
  begin
    NameLow := N.Name.ToLower;
    for Opener in FILE_OPEN_CALLS do
      if NameLow.StartsWith(Opener) then
      begin
        AddHandle(FirstArgIdent(NameLow, Length(Opener) + 1));
        Break;
      end;
  end;
end;

class procedure TDebugOutputDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls       : TList<TAstNode>;
  N           : TAstNode;
  CondRanges  : TList<TAstNode>;   // Welle 2: nkConditionalRange (DEBUG-guarded {$IFDEF})
  TextHandles : TDictionary<string, Boolean>;   // Gate A: Text-/TextFile-Handles der Unit

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

  // Gate A: True wenn das erste Argument ab ArgStart ein belegtes Text-Handle
  // der Unit ist. Liest TextHandles aus dem umschliessenden Gueltigkeits-
  // bereich - dieselbe Bauform wie LineInDebugRange/CondRanges oben.
  function FirstArgIsTextHandle(const LowText: string; ArgStart: Integer): Boolean;
  var
    Ident : string;
  begin
    Result := False;
    Ident  := FirstArgIdent(LowText, ArgStart);
    if Ident = '' then Exit;
    if IsStdTextHandle(Ident) then Exit;   // Output/ErrOutput/Input bleiben Fund
    Result := TextHandles.ContainsKey(Ident);
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
      // Gate A: 'WriteLn(F, ...)' mit F = Text-/TextFile-Handle schreibt in
      // eine Datei bzw. auf den Drucker. Continue statt Exit, damit ein
      // ANDERES Debug-Muster im selben Text (z.B. ein ShowMessage im
      // Argument) weiterhin gefunden wird.
      if (Kw = 'writeln(') and
         FirstArgIsTextHandle(NameLow, p + Length(Kw)) then Continue;
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
  // Gate D vor allem anderen: in einer Logger-/Appender-Senke hat SCA017
  // nichts zu melden, also gar nicht erst analysieren.
  if IsLoggerSinkFile(FileName) then Exit;

  TextHandles := TDictionary<string, Boolean>.Create;
  try
    CondRanges := UnitNode.FindAll(nkConditionalRange);   // Welle 2 (additiv)
    try
      Calls := UnitNode.FindAll(nkCall);
      try
        // Gate A: Handle-Menge steht VOR der Call-Schleife - eine Datei wird
        // regelmaessig erst weiter unten geoeffnet als sie beschrieben wird
        // (SynGenUnit.pas: WriteLn ab :200, AssignFile erst :750).
        CollectTextHandles(UnitNode, Calls, TextHandles);
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
  finally
    TextHandles.Free;
  end;
end;

end.
