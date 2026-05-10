object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Static Code Analysis Tool for Delphi'
  ClientHeight = 512
  ClientWidth = 850
  Color = clWhite
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object StatusBar1: TStatusBar
    Left = 0
    Top = 493
    Width = 850
    Height = 19
    Panels = <>
    SimplePanel = True
    SimpleText = 'Ready.'
    ExplicitTop = 485
    ExplicitWidth = 616
  end
  object Panel4: TPanel
    Left = 0
    Top = 0
    Width = 850
    Height = 129
    Align = alTop
    TabOrder = 1
    ExplicitWidth = 616
    object Panel3: TPanel
      Left = 1
      Top = 82
      Width = 848
      Height = 41
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      ExplicitWidth = 614
      DesignSize = (
        848
        41)
      object Button6: TButton
        Left = 513
        Top = 6
        Width = 130
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Analyse directory'
        TabOrder = 0
        OnClick = Button6Click
        ExplicitLeft = 279
      end
      object Button7: TButton
        Left = 377
        Top = 6
        Width = 130
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Analyse file'
        TabOrder = 3
        OnClick = Button7Click
        ExplicitLeft = 143
      end
      object Button4: TButton
        Left = 649
        Top = 6
        Width = 75
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Save'
        TabOrder = 1
        OnClick = Button4Click
        ExplicitLeft = 415
      end
      object Button1: TButton
        Left = 744
        Top = 6
        Width = 83
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Quit'
        TabOrder = 2
        OnClick = Button1Click
        ExplicitLeft = 510
      end
    end
    object Panel1: TPanel
      Left = 1
      Top = 1
      Width = 848
      Height = 81
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 1
      ExplicitWidth = 614
      DesignSize = (
        848
        81)
      object Label1: TLabel
        Left = 16
        Top = 20
        Width = 67
        Height = 15
        Caption = 'Project path:'
      end
      object Label3: TLabel
        Left = 16
        Top = 52
        Width = 54
        Height = 15
        Caption = 'Save path:'
      end
      object Projectpath: TComboBox
        Left = 112
        Top = 17
        Width = 686
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
        Text = 'D:\git-demos\delphi\StaticCodeAnalyser\resources'
        ExplicitWidth = 452
      end
      object Savetofile: TEdit
        Left = 112
        Top = 49
        Width = 686
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 1
        Text = '.\analyse_all.csv'
        ExplicitWidth = 452
      end
      object Button2: TButton
        Left = 806
        Top = 15
        Width = 27
        Height = 25
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 2
        OnClick = Button2Click
        ExplicitLeft = 572
      end
      object Button3: TButton
        Left = 806
        Top = 47
        Width = 27
        Height = 25
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 3
        OnClick = Button3Click
        ExplicitLeft = 572
      end
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 129
    Width = 850
    Height = 364
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    ExplicitWidth = 616
    ExplicitHeight = 356
    object ResultGrid: TStringGrid
      Left = 0
      Top = 0
      Width = 850
      Height = 364
      Align = alClient
      DefaultColWidth = 100
      DefaultRowHeight = 20
      FixedCols = 0
      RowCount = 2
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect, goThumbTracking]
      TabOrder = 0
      OnClick = ResultGridClick
      ExplicitWidth = 616
      ExplicitHeight = 356
      ColWidths = (
        176
        121
        50
        148
        100)
    end
  end
end
