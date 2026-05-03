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

const
  MARKERS : array[0..3] of string = ('TODO', 'FIXME', 'HACK', 'XXX');

// IsIdentChar siehe uDetectorUtils.TDetectorUtils.IsIdentChar - lokal entfernt
// (Duplikat). Aufrufer unten verwenden den Klassen-Helfer direkt.

function FindMarkerInComment(const Line: string;
  CommentStart: Integer; out Marker: string;
  out MarkerPos: Integer): Boolean;
// Sucht den ersten Marker im Bereich [CommentStart..End-of-Line].
var
  M       : string;
  p, pEnd : Integer;
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
begin
  if not FileExists(FileName) then Exit;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(FileName, TEncoding.UTF8);
    except
      // Bei Encoding-Fehler erneut ohne Encoding-Vorgabe versuchen
      Lines.Clear;
      try
        Lines.LoadFromFile(FileName);
      except
        Exit;
      end;
    end;

    InBlockComm := False;

    for i := 0 to Lines.Count - 1 do
    begin
      Line      := Lines[i];
      CommentAt := 0;

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
        // Erstes Vorkommen von '//' oder '{' suchen das nicht in einem
        // String-Literal steht. Vereinfacht: '//' und '{' werden
        // jeweils gesucht, kleinere Position gewinnt.
        var pSlash := Pos('//', Line);
        var pBrace := Pos('{', Line);
        if (pBrace > 0) and ((pSlash = 0) or (pBrace < pSlash)) then
        begin
          CommentAt := pBrace;
          // Endet der Block-Kommentar in derselben Zeile?
          var pClose := Pos('}', Line, pBrace + 1);
          if pClose = 0 then
            InBlockComm := True;
        end
        else if pSlash > 0 then
          CommentAt := pSlash;
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
        F.Severity   := lsHint;
        F.Kind       := fkTodoComment;
        Results.Add(F);
      end;
    end;
  finally
    Lines.Free;
  end;
end;

end.
