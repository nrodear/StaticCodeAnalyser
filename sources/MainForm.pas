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
    StartPrjButton: TButton;
    Projectpath: TEdit;
    Edit2: TEdit;
    resultsInfo: TListBox;
    leakyClazzes: TComboBox;
    TestButton: TButton;
    Label1: TLabel;
    Label2: TLabel;
    TestPath: TEdit;
    procedure StartPrjButtonClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure TestButtonClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure resultsInfoClick(Sender: TObject);

  private
    { Private-Deklarationen }
    procedure Analyse(Sender: TObject; const path, clazz: string);
  public
    { Public-Deklarationen }
  end;

var
  Form2: TForm2;

implementation

uses
  System.Generics.Collections, clipbrd,
  uParser, uConsts;

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

procedure TForm2.StartPrjButtonClick(Sender: TObject);
begin
  Analyse(Sender, Projectpath.Text, leakyClazzes.Text);
end;

procedure TForm2.TestButtonClick(Sender: TObject);
begin
  Analyse(Sender, TestPath.Text, leakyClazzes.Text);
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
  Clipboard.AsText := resultsInfo.Items.Text;
end;

end.
