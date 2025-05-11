object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Form2'
  ClientHeight = 441
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnShow = FormShow
  TextHeight = 15
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 624
    Height = 145
    Align = alTop
    TabOrder = 0
    object Label1: TLabel
      Left = 40
      Top = 19
      Width = 34
      Height = 15
      Caption = 'Label1'
    end
    object Label2: TLabel
      Left = 40
      Top = 48
      Width = 34
      Height = 15
      Caption = 'Label1'
    end
    object StartPrjButton: TButton
      Left = 31
      Top = 104
      Width = 75
      Height = 25
      Caption = 'Start'
      TabOrder = 0
      OnClick = StartPrjButtonClick
    end
    object Projectpath: TEdit
      Left = 112
      Top = 16
      Width = 369
      Height = 23
      TabOrder = 1
      Text = 'D:\git-demos\delphi\analyser.d12\resources'
    end
    object Edit2: TEdit
      Left = 112
      Top = 74
      Width = 369
      Height = 23
      TabOrder = 2
      Text = 'D:\git-demos\delphi\analyser.d12\logResults.log'
    end
    object leakyClazzes: TComboBox
      Left = 208
      Top = 104
      Width = 145
      Height = 23
      TabOrder = 3
      Text = 'leakyClazzes'
    end
    object TestButton: TButton
      Left = 112
      Top = 103
      Width = 75
      Height = 25
      Caption = 'Test'
      TabOrder = 4
      OnClick = TestButtonClick
    end
    object TestPath: TEdit
      Left = 112
      Top = 45
      Width = 369
      Height = 23
      TabOrder = 5
      Text = 'D:\git-demos\delphi\analyser.d12\resources'
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 145
    Width = 624
    Height = 255
    Align = alClient
    TabOrder = 1
    object resultsInfo: TListBox
      Left = 1
      Top = 1
      Width = 622
      Height = 253
      Align = alClient
      ItemHeight = 15
      TabOrder = 0
      OnClick = resultsInfoClick
    end
  end
  object Panel3: TPanel
    Left = 0
    Top = 400
    Width = 624
    Height = 41
    Align = alBottom
    TabOrder = 2
    object Button1: TButton
      Left = 520
      Top = 6
      Width = 75
      Height = 25
      Caption = 'Close'
      TabOrder = 0
      OnClick = Button1Click
    end
  end
end
