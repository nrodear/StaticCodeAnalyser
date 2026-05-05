program TestParseX509;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  uLexer in '..\sources\Parsing\uLexer.pas',
  uAstNode in '..\sources\Parsing\uAstNode.pas',
  uParser2 in '..\sources\Parsing\uParser2.pas',
  uMethodd12 in '..\sources\Common\uMethodd12.pas',
  uSCAConsts in '..\sources\Common\uSCAConsts.pas',
  uDetectorUtils in '..\sources\Common\uDetectorUtils.pas',
  uCollectValues in '..\sources\Common\uCollectValues.pas',
  uRegExMatches in '..\sources\Common\uRegExMatches.pas';

const
  FILENAME =
    'D:\git-demos\delphi\mORMot2-2.4-stable\mORMot2-2.4-stable\src\crypt\mormot.crypt.x509.pas';

var
  Parser : TParser2;
  Root   : TAstNode;
  Sw     : TStopwatch;
  Source : TStringList;
begin
  try
    if not FileExists(FILENAME) then
    begin
      Writeln('FILE NOT FOUND: ', FILENAME);
      Halt(1);
    end;

    Writeln('Loading...');
    Source := TStringList.Create;
    try
      Source.LoadFromFile(FILENAME);
      Writeln('  ', Source.Count, ' lines, ', Length(Source.Text), ' chars');

      Sw := TStopwatch.StartNew;
      Parser := TParser2.Create;
      try
        Writeln('Parsing...');
        Root := Parser.ParseSource(Source.Text);
        try
          Sw.Stop;
          Writeln(Format('OK: parsed in %d ms', [Sw.ElapsedMilliseconds]));
          if Assigned(Root) then
            Writeln('  AST root: ', Root.Children.Count, ' top-level nodes');
        finally
          Root.Free;
        end;
      finally
        Parser.Free;
      end;
    finally
      Source.Free;
    end;
  except
    on E: Exception do
    begin
      Sw.Stop;
      Writeln(Format('EXCEPTION after %d ms: [%s] %s',
        [Sw.ElapsedMilliseconds, E.ClassName, E.Message]));
      Halt(2);
    end;
  end;
end.
