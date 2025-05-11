program analyser.d12;

uses
  Vcl.Forms,
  MainForm in 'sources\MainForm.pas' {Form2},
  StaticFiles in 'sources\StaticFiles.pas',
  uParser in 'sources\uParser.pas',
  uMethodd12 in 'sources\uMethodd12.pas',
  StaticAnalyzer in 'sources\StaticAnalyzer.pas',
  uConsts in 'sources\uConsts.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
