unit uTodoComment;

// Detektor fuer TODO / FIXME / HACK / XXX-Marker in Kommentaren.
//
// Liest die Datei zeilenweise und sucht in den Kommentar-Bereichen
// (//... und {...}) nach den Markern. Das geht NICHT ueber den AST,
// weil der Lexer Kommentare ueberspringt und sie damit nicht im Baum
// landen.
//
// Akzeptiert wird der Marker nur als ganzes Wort und nur wenn er innerhalb
// eines Kommentars steht - sonst wuerde z.B. der String "todo: 'TODO'" ein
// false-positive ausloesen.
//
// Schweregrad: lsHint - kein Bug, sondern ein Reminder fuer offene Arbeit.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uDetectorUtils;

type
  TTodoCommentDetector = class
  public
    // UnitNode wird nicht verwendet, der Detektor liest die Datei selbst.
    // Die Signatur bleibt aus Konsistenz mit den anderen Detektoren erhalten.
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  uFileTextCache;

const
  MARKERS : array[0..3] of string = ('TODO', 'FIXME', 'HACK', 'XXX');

// IsIdentChar siehe uDetectorUtils.TDetectorUtils.IsIdentChar - lokal entfernt
// (Duplikat). Aufrufer unten verwenden den Klassen-Helfer direkt.

function ScanLineCommentStart(const Line: string;
  var InBlockComm: Boolean): Integer;
// Liefert die 1-basierte Spalte ab der ein Kommentar beginnt (inkl. der
// Marker '//' oder '{'). 0 falls kein Kommentar in dieser Zeile startet.
// Ueberspringt Pascal-String-Literale ('...' inkl. doppelter '' Escapes)
// damit ''// in einem String'' nicht faelschlich als Kommentar gilt.
var
  i, n   : Integer;
  InStr  : Boolean;
  pClose : Integer;
begin
  Result := 0;
  InStr  := False;
  i := 1;
  n := Length(Line);
  while i <= n do
  begin
    if InStr then
    begin
      if Line[i] = '''' then
      begin
        if (i < n) and (Line[i+1] = '''') then
          Inc(i, 2)              // doppelter Apostroph = escape
        else
        begin
          InStr := False;
          Inc(i);
        end;
      end
      else
        Inc(i);
      Continue;
    end;
    case Line[i] of
      '''':
        begin
          InStr := True;
          Inc(i);
        end;
      '/':
        begin
          if (i < n) and (Line[i+1] = '/') then
          begin
            Result := i;
            Exit;
          end;
          Inc(i);
        end;
      '{':
        begin
          Result := i;
          pClose := Pos('}', Line, i + 1);
          if pClose = 0 then
            InBlockComm := True;
          Exit;
        end;
    else
      Inc(i);
    end;
  end;
end;

function FindMarkerInComment(const Line: string;
  CommentStart: Integer; out Marker: string;
  out MarkerPos: Integer): Boolean;
// Sucht den ersten Marker im Bereich [CommentStart..End-of-Line].
//
// FP-Schutz fuer Datei-/Pfad-Referenzen wie 'todo-sonar.md', 'todo.md':
// nach dem Marker direkt ein '-' oder '.' (ohne Whitespace) deutet auf
// einen kebab-/dotted-Identifier hin (Filename/Markdown-Link), nicht auf
// einen TODO-Marker. Self-Test fand ~20 FPs auf todo-roadmap-Referenzen.
var
  M       : string;
  p, pEnd : Integer;
  Next    : Char;
begin
  Result := False;
  for M in MARKERS do
  begin
    p := CommentStart;
    while p <= Length(Line) - Length(M) + 1 do
    begin
      if SameText(Copy(Line, p, Length(M)), M) then
      begin
        // Wortgrenze links
        if (p > 1) and TDetectorUtils.IsIdentChar(Line[p - 1]) then
        begin
          Inc(p);
          Continue;
        end;
        // Wortgrenze rechts
        pEnd := p + Length(M);
        if (pEnd <= Length(Line)) and TDetectorUtils.IsIdentChar(Line[pEnd]) then
        begin
          Inc(p);
          Continue;
        end;
        // Datei-/Pfad-Heuristik: 'TODO' direkt gefolgt von '-' oder '.'
        // -> 'todo-sonar.md', 'todo.md' etc. KEIN echter Marker.
        if pEnd <= Length(Line) then
        begin
          Next := Line[pEnd];
          if (Next = '-') or (Next = '.') or (Next = '/') or (Next = '\') then
          begin
            Inc(p);
            Continue;
          end;
        end;
        // FP-Schutz: Marker in single-quotes ('TODO') ist Doku-Erwaehnung
        // (Detector-Source-File nennt sein Such-Pattern als String).
        if (p > 1) and (Line[p - 1] = '''') and
           (pEnd <= Length(Line)) and (Line[pEnd] = '''') then
        begin
          Inc(p); Continue;
        end;
        // FP-Schutz: Slash-getrennte Marker-Liste (' / TODO ' oder
        // ' TODO / ') - typische Doku-Notation 'TODO / FIXME / HACK / XXX'.
        if (p >= 4) and (Line[p - 1] = ' ') and (Line[p - 2] = '/') and
           (Line[p - 3] = ' ') then
        begin
          Inc(p); Continue;
        end;
        if (pEnd + 1 <= Length(Line)) and (Line[pEnd] = ' ') and
           (Line[pEnd + 1] = '/') then
        begin
          Inc(p); Continue;
        end;
        // FP-Schutz: Marker direkt vor closing-paren - Doku-Erwaehnung in
        // Klammer wie '(TODO)', '(TODO):', 'siehe Phase 1 TODO).' etc.
        if (pEnd <= Length(Line)) and (Line[pEnd] = ')') then
        begin
          Inc(p); Continue;
        end;
        Marker    := M;
        MarkerPos := p;
        Exit(True);
      end;
      Inc(p);
    end;
  end;
end;

class procedure TTodoCommentDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines       : TStringList;
  Line        : string;
  i, p        : Integer;
  InBlockComm : Boolean;   // {...}-Block ueber mehrere Zeilen
  CommentAt   : Integer;   // Spalte ab der Kommentar beginnt (1-basiert)
  Marker      : string;
  MarkerPos   : Integer;
  F           : TLeakFinding;
  Snippet     : string;
  Cached      : Boolean;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    InBlockComm := False;

    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];

      if InBlockComm then
      begin
        // Kompletter Zeilenanfang ist Kommentar bis '}' oder Zeilenende
        CommentAt := 1;
        p := Pos('}', Line);
        if p > 0 then
          InBlockComm := False;
      end
      else
      begin
        // String-aware Scan: ueberspringt Apostroph-Literale damit
        // 'foo // bar' den '// bar' nicht als Kommentar ansieht.
        CommentAt := ScanLineCommentStart(Line, InBlockComm);
      end;

      if CommentAt = 0 then Continue;

      if FindMarkerInComment(Line, CommentAt, Marker, MarkerPos) then
      begin
        // Snippet ab dem Marker bis Zeilenende, Whitespace getrimmt
        Snippet := Trim(Copy(Line, MarkerPos, MaxInt));
        if Length(Snippet) > 60 then
          Snippet := Copy(Snippet, 1, 57) + '...';

        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Snippet;
        F.SetKind(fkTodoComment);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
