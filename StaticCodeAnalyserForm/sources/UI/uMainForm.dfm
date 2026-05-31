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
        Width = 0
      end>
    SimpleText = 'Ready.'
    ExplicitTop = 485
    ExplicitWidth = 848
  end
  object PanelStats: TPanel
    Left = 0
    Top = 0
    Width = 850
    Height = 49
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 3
  end
  object Panel4: TPanel
    Left = 0
    Top = 49
    Width = 850
    Height = 140
    Align = alTop
    TabOrder = 1
    ExplicitTop = 43
    object Panel3: TPanel
      Left = 1
      Top = 79
      Width = 848
      Height = 41
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      ExplicitLeft = 0
      DesignSize = (
        848
        41)
      object LblFilter: TLabel
        Left = 16
        Top = 9
        Width = 44
        Height = 15
        Caption = 'Severity:'
      end
      object LblType: TLabel
        Left = 184
        Top = 10
        Width = 28
        Height = 20
        Caption = 'Type:'
      end
      object LblMinSev: TLabel
        Left = 366
        Top = 9
        Width = 24
        Height = 17
        Caption = 'Min:'
      end
      object LblSearch: TLabel
        Left = 490
        Top = 10
        Width = 38
        Height = 15
        Caption = 'Search:'
      end
      object SeverityFilterCombo: TComboBox
        Left = 66
        Top = 7
        Width = 110
        Height = 23
        Style = csDropDownList
        TabOrder = 0
        OnChange = SeverityFilterComboChange
      end
      object TypeFilterCombo: TComboBox
        Left = 218
        Top = 6
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 1
        OnChange = TypeFilterComboChange
      end
      object MinSevCombo: TComboBox
        Left = 396
        Top = 6
        Width = 85
        Height = 23
        Style = csDropDownList
        TabOrder = 2
        OnChange = MinSevComboChange
      end
      object SearchEdit: TEdit
        Left = 534
        Top = 6
        Width = 169
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 3
        OnChange = SearchEditChange
      end
    end
    object PanelActions: TPanel
      Left = 1
      Top = 1
      Width = 848
      Height = 35
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 2
      ExplicitLeft = 0
      ExplicitTop = 6
      object LblProfile: TLabel
        Left = 352
        Top = 9
        Width = 37
        Height = 15
        Caption = 'Profile:'
      end
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
        Top = 5
        Width = 36
        Height = 25
        Caption = #9095
        ParentShowHint = False
        ShowHint = True
        TabOrder = 2
        OnClick = BtnBranchClick
      end
      object ProfileCombo: TComboBox
        Left = 395
        Top = 7
        Width = 110
        Height = 23
        Style = csDropDownList
        TabOrder = 3
        OnChange = ProfileComboChange
      end
    end
    object Panel1: TPanel
      Left = 1
      Top = 36
      Width = 848
      Height = 43
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 1
      ExplicitLeft = 2
      ExplicitTop = 37
      DesignSize = (
        848
        43)
      object Label1: TLabel
        Left = 16
        Top = 17
        Width = 67
        Height = 15
        Caption = 'Project path:'
      end
      object Projectpath: TComboBox
        Left = 89
        Top = 14
        Width = 584
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
        Text = 'D:\git-demos\delphi\StaticCodeAnalyser\resources'
      end
      object Button2: TButton
        Left = 679
        Top = 14
        Width = 24
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 1
        OnClick = Button2Click
      end
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 189
    Width = 850
    Height = 304
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    ExplicitTop = 185
    ExplicitWidth = 848
    ExplicitHeight = 300
    object ResultGrid: TStringGrid
      Left = 0
      Top = 0
      Width = 850
      Height = 304
      Align = alClient
      DefaultColWidth = 100
      DefaultRowHeight = 20
      FixedCols = 0
      RowCount = 2
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goColSizing, goRowSelect, goThumbTracking]
      TabOrder = 0
      OnClick = ResultGridClick
      ExplicitTop = -6
      ColWidths = (
        176
        121
        50
        148
        100)
    end
  end
end
