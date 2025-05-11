unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, uMethodd12,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  StaticAnalyzer;

type
  TForm2 = class(TForm)
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;
    Button1: TButton;
    Projectpath: TEdit;
    Savetofile: TEdit;
    resultsInfo: TListBox;
    leakyClazzes: TComboBox;
    Label1: TLabel;
    StartPrjButton: TButton;
    Button2: TButton;
    Button3: TButton;
    Button4: TButton;
    procedure StartPrjButtonClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure resultsInfoClick(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);

  private
    { Private-Deklarationen }
    procedure Analyse(Sender: TObject; const path, clazz: string);
    function SelectFolder: string;
    function GetAbsolutePath(const RelativePath: string): string;
    function SelectFile: string;
  public
    { Public-Deklarationen }
  end;

var
  Form2: TForm2;

implementation

uses
  System.Generics.Collections, clipbrd, uParser, uConsts, Vcl.FileCtrl;

{$R *.dfm}

procedure TForm2.Analyse(Sender: TObject; const path, clazz: string);

var
  results: TStringList;
begin
  resultsInfo.Items.Clear;
  results := TStaticAnalyzer.AnalyzeRecursive(path, clazz);
  resultsInfo.Clear;
  resultsInfo.Items := results;
  results.free;
end;

procedure TForm2.Button1Click(Sender: TObject);
begin
  close;
end;

procedure TForm2.Button2Click(Sender: TObject);
begin
  Projectpath.Text := SelectFolder;
end;

procedure TForm2.Button3Click(Sender: TObject);
begin
  Savetofile.Text := GetAbsolutePath(SelectFile);
end;

procedure TForm2.Button4Click(Sender: TObject);
begin
  resultsInfo.Items.Savetofile(GetAbsolutePath(Savetofile.Text));
end;

procedure TForm2.StartPrjButtonClick(Sender: TObject);
begin
  Analyse(Sender, Projectpath.Text, leakyClazzes.Text);
end;

procedure TForm2.FormShow(Sender: TObject);
var
  leaky: TStringList;
begin
  leaky := TConsts.GetLeakyClasses;
  leakyClazzes.Text := '';

  leakyClazzes.Items := leaky;
  leakyClazzes.ItemIndex := 0;
  freeAndNil(leaky);
end;

procedure TForm2.resultsInfoClick(Sender: TObject);
begin
  if resultsInfo.ItemIndex <> -1 then
    Clipboard.AsText := resultsInfo.Items[resultsInfo.ItemIndex];
end;

function TForm2.SelectFolder: string;
var
  OpenDialog: TFileOpenDialog;
begin
  result:='';

  OpenDialog := TFileOpenDialog.Create(nil);
  try
    OpenDialog.Options := [fdoPickFolders, fdoPathMustExist,
      fdoForceFileSystem];
    OpenDialog.Title := 'Ordner auswählen';

    if OpenDialog.Execute then
      result := OpenDialog.FileName;
  finally
    OpenDialog.free;
  end;
end;

function TForm2.GetAbsolutePath(const RelativePath: string): string;
begin
  result := RelativePath;
  if ExtractFileDrive(RelativePath) <> '' then
    exit;
  result := ExpandFileName(RelativePath);
end;

function TForm2.SelectFile: string;
var
  OpenDialog: TOpenDialog;
begin
  result := '';
  OpenDialog := TOpenDialog.Create(nil);
  try
    OpenDialog.Title := 'Datei auswählen';
    OpenDialog.Filter := 'Log Dateien|*.log';

    OpenDialog.FileName := 'analyse_' + leakyClazzes.Text + '.log';
    if OpenDialog.Execute then
      result := OpenDialog.FileName;
  finally
    OpenDialog.free;
  end;
end;

end.
