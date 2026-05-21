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
    Panels = <
      item
        Width = 160
      end
      item
        Width = 220
      end
      item
        Width = 50
      end>
    SimpleText = 'Ready.'
    ExplicitTop = 485
    ExplicitWidth = 848
  end
  object PanelStats: TPanel
    Left = 0
    Top = 0
    Width = 850
    Height = 45
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 3
    ExplicitWidth = 848
  end
  object Panel4: TPanel
    Left = 0
    Top = 45
    Width = 850
    Height = 165
    Align = alTop
    TabOrder = 1
    ExplicitWidth = 848
    object Panel3: TPanel
      Left = 1
      Top = 82
      Width = 848
      Height = 41
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      ExplicitWidth = 846
      DesignSize = (
        848
        41)
      object LblFilter: TLabel
        Left = 10
        Top = 12
        Width = 44
        Height = 15
        Caption = 'Severity:'
      end
      object LblType: TLabel
        Left = 184
        Top = 12
        Width = 28
        Height = 15
        Caption = 'Type:'
      end
      object LblProfile: TLabel
        Left = 333
        Top = 12
        Width = 37
        Height = 15
        Caption = 'Profile:'
      end
      object LblMinSev: TLabel
        Left = 497
        Top = 12
        Width = 24
        Height = 15
        Caption = 'Min:'
      end
      object LblSearch: TLabel
        Left = 621
        Top = 12
        Width = 38
        Height = 15
        Caption = 'Search:'
      end
      object SeverityFilterCombo: TComboBox
        Left = 64
        Top = 8
        Width = 110
        Height = 23
        Style = csDropDownList
        TabOrder = 0
        OnChange = SeverityFilterComboChange
      end
      object TypeFilterCombo: TComboBox
        Left = 218
        Top = 8
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 1
        OnChange = TypeFilterComboChange
      end
      object ProfileCombo: TComboBox
        Left = 377
        Top = 8
        Width = 110
        Height = 23
        Style = csDropDownList
        TabOrder = 2
        OnChange = ProfileComboChange
      end
      object MinSevCombo: TComboBox
        Left = 526
        Top = 8
        Width = 85
        Height = 23
        Style = csDropDownList
        TabOrder = 3
        OnChange = MinSevComboChange
      end
      object SearchEdit: TEdit
        Left = 665
        Top = 8
        Width = 175
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 4
        OnChange = SearchEditChange
        ExplicitWidth = 173
      end
    end
    object PanelActions: TPanel
      Left = 1
      Top = 123
      Width = 848
      Height = 41
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 2
      ExplicitWidth = 846
      object Button7: TButton
        Left = 152
        Top = 6
        Width = 110
        Height = 25
        Caption = 'Analyse file'
        TabOrder = 0
        OnClick = Button7Click
      end
      object Button6: TButton
        Left = 16
        Top = 6
        Width = 130
        Height = 25
        Caption = 'Analyse directory'
        TabOrder = 1
        OnClick = Button6Click
      end
      object BtnBranch: TButton
        Left = 268
        Top = 6
        Width = 36
        Height = 25
        Caption = #9095
        ParentShowHint = False
        ShowHint = True
        TabOrder = 2
        OnClick = BtnBranchClick
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
      ExplicitWidth = 846
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
        ExplicitWidth = 684
      end
      object Savetofile: TEdit
        Left = 112
        Top = 49
        Width = 686
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 1
        Text = '.\analyse_all.csv'
        ExplicitWidth = 684
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
        ExplicitLeft = 804
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
        ExplicitLeft = 804
      end
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 210
    Width = 850
    Height = 283
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    ExplicitWidth = 848
    ExplicitHeight = 275
    object ResultGrid: TStringGrid
      Left = 0
      Top = 0
      Width = 850
      Height = 283
      Align = alClient
      DefaultColWidth = 100
      DefaultRowHeight = 20
      FixedCols = 0
      RowCount = 2
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect, goThumbTracking]
      TabOrder = 0
      OnClick = ResultGridClick
      ExplicitWidth = 848
      ExplicitHeight = 275
      ColWidths = (
        176
        121
        50
        148
        100)
    end
  end
end
