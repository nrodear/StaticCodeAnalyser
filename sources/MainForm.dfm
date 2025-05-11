object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Form2'
  ClientHeight = 441
  ClientWidth = 541
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
    Width = 541
    Height = 145
    Align = alTop
    TabOrder = 0
    ExplicitWidth = 624
    object Label1: TLabel
      Left = 40
      Top = 19
      Width = 64
      Height = 15
      Caption = 'ProjectPath:'
    end
    object Projectpath: TEdit
      Left = 112
      Top = 16
      Width = 369
      Height = 23
      TabOrder = 0
      Text = '.\sources'
    end
    object Savetofile: TEdit
      Left = 112
      Top = 74
      Width = 369
      Height = 23
      TabOrder = 1
      Text = '.\logResults.log'
    end
    object leakyClazzes: TComboBox
      Left = 336
      Top = 45
      Width = 145
      Height = 23
      TabOrder = 2
      Text = 'leakyClazzes'
    end
    object Button2: TButton
      Left = 487
      Top = 14
      Width = 27
      Height = 25
      Caption = '...'
      TabOrder = 3
      OnClick = Button2Click
    end
    object Button3: TButton
      Left = 487
      Top = 74
      Width = 27
      Height = 25
      Caption = '...'
      TabOrder = 4
      OnClick = Button3Click
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 145
    Width = 541
    Height = 255
    Align = alClient
    TabOrder = 1
    ExplicitWidth = 624
    object resultsInfo: TListBox
      Left = 1
      Top = 1
      Width = 539
      Height = 253
      Align = alClient
      ItemHeight = 15
      TabOrder = 0
      OnClick = resultsInfoClick
      ExplicitWidth = 622
    end
  end
  object Panel3: TPanel
    Left = 0
    Top = 400
    Width = 541
    Height = 41
    Align = alBottom
    TabOrder = 2
    ExplicitLeft = -1
    ExplicitTop = 405
    ExplicitWidth = 624
    object Button1: TButton
      Left = 439
      Top = 5
      Width = 75
      Height = 25
      Caption = 'Close'
      TabOrder = 0
      OnClick = Button1Click
    end
    object StartPrjButton: TButton
      Left = 255
      Top = 6
      Width = 75
      Height = 25
      Caption = 'Analyse...'
      TabOrder = 1
      OnClick = StartPrjButtonClick
    end
    object Button4: TButton
      Left = 336
      Top = 6
      Width = 75
      Height = 25
      Caption = 'Save'
      TabOrder = 2
      OnClick = Button4Click
    end
  end
end
