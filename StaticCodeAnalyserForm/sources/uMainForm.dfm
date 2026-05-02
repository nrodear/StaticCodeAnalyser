object Form2: TForm2
  Left = 0
  Top = 0
  Caption = 'Static Code Analyser'
  ClientHeight = 512
  ClientWidth = 618
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
    Width = 618
    Height = 19
    Panels = <>
    SimplePanel = True
    SimpleText = 'Bereit.'
    ExplicitTop = 501
    ExplicitWidth = 620
  end
  object Panel4: TPanel
    Left = 0
    Top = 0
    Width = 618
    Height = 129
    Align = alTop
    TabOrder = 1
    ExplicitWidth = 620
    object Panel3: TPanel
      Left = 1
      Top = 82
      Width = 618
      Height = 41
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      DesignSize = (
        616
        41)
      object Button6: TButton
        Left = 287
        Top = 6
        Width = 130
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Verzeichnis analysieren'
        TabOrder = 0
        OnClick = Button6Click
        ExplicitLeft = 289
      end
      object Button7: TButton
        Left = 151
        Top = 6
        Width = 130
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Datei analysieren'
        TabOrder = 3
        OnClick = Button7Click
      end
      object Button4: TButton
        Left = 423
        Top = 6
        Width = 75
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Speichern'
        TabOrder = 1
        OnClick = Button4Click
        ExplicitLeft = 425
      end
      object Button1: TButton
        Left = 518
        Top = 6
        Width = 83
        Height = 25
        Anchors = [akTop, akRight]
        Caption = 'Beenden'
        TabOrder = 2
        OnClick = Button1Click
        ExplicitLeft = 520
      end
    end
    object Panel1: TPanel
      Left = 1
      Top = 1
      Width = 616
      Height = 81
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 1
      ExplicitWidth = 618
      DesignSize = (
        616
        81)
      object Label1: TLabel
        Left = 16
        Top = 20
        Width = 64
        Height = 15
        Caption = 'Projektpfad:'
      end
      object Label3: TLabel
        Left = 16
        Top = 52
        Width = 72
        Height = 15
        Caption = 'Speicherpfad:'
      end
      object Projectpath: TComboBox
        Left = 112
        Top = 17
        Width = 454
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
        Text = 'D:\git-demos\delphi\StaticCodeAnalyser\resources'
      end
      object Savetofile: TEdit
        Left = 112
        Top = 49
        Width = 454
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 1
        Text = '.\analyse_all.csv'
        ExplicitWidth = 456
      end
      object Button2: TButton
        Left = 574
        Top = 15
        Width = 27
        Height = 25
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 2
        OnClick = Button2Click
        ExplicitLeft = 576
      end
      object Button3: TButton
        Left = 574
        Top = 47
        Width = 27
        Height = 25
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 3
        OnClick = Button3Click
        ExplicitLeft = 576
      end
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 129
    Width = 618
    Height = 364
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    ExplicitWidth = 620
    ExplicitHeight = 372
    object ResultGrid: TStringGrid
      Left = 0
      Top = 0
      Width = 620
      Height = 372
      Align = alClient
      DefaultColWidth = 100
      DefaultRowHeight = 20
      FixedCols = 0
      RowCount = 2
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect, goThumbTracking]
      TabOrder = 0
      OnClick = ResultGridClick
      ColWidths = (
        176
        121
        50
        148
        100)
    end
  end
end
