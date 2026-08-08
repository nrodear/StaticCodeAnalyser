object Form2: TForm2
  Left = 0
  Top = 0
  Anchors = [akTop, akRight]
  Caption = 'Static Code Analysis Tool for Delphi'
  ClientHeight = 512
  ClientWidth = 777
  Color = clBtnFace
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
    Width = 777
    Height = 19
    Panels = <
      item
        Width = 160
      end
      item
        Width = 170
      end
      item
        Width = 0
      end>
    ExplicitTop = 485
    ExplicitWidth = 775
  end
  object PanelStats: TPanel
    Left = 0
    Top = 0
    Width = 777
    Height = 49
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 3
    ExplicitWidth = 775
  end
  object Panel4: TPanel
    Left = 0
    Top = 49
    Width = 777
    Height = 120
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 1
    ExplicitWidth = 775
    object Panel3: TPanel
      Left = 0
      Top = 78
      Width = 777
      Height = 41
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      ExplicitWidth = 775
      DesignSize = (
        777
        41)
      object LblFilter: TLabel
        Left = 168
        Top = 8
        Width = 44
        Height = 15
        Caption = 'Severity:'
      end
      object LblType: TLabel
        Left = 18
        Top = 10
        Width = 28
        Height = 15
        Caption = 'Type:'
      end
      object LblSearch: TLabel
        Left = 428
        Top = 10
        Width = 38
        Height = 15
        Caption = 'Search:'
      end
      object SeverityFilterCombo: TComboBox
        Left = 218
        Top = 6
        Width = 200
        Height = 23
        Style = csDropDownList
        DropDownCount = 16
        TabOrder = 0
        OnChange = SeverityFilterComboChange
      end
      object TypeFilterCombo: TComboBox
        Left = 52
        Top = 6
        Width = 105
        Height = 23
        Style = csDropDownList
        TabOrder = 1
        OnChange = TypeFilterComboChange
      end
      object SearchEdit: TEdit
        Left = 472
        Top = 6
        Width = 160
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 2
        OnChange = SearchEditChange
        ExplicitWidth = 158
      end
    end
    object PanelActions: TPanel
      Left = 0
      Top = 0
      Width = 777
      Height = 35
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 2
      ExplicitTop = -6
      DesignSize = (
        777
        35)
      object LblProfile: TLabel
        Left = 281
        Top = 8
        Width = 37
        Height = 15
        Caption = 'Profile:'
      end
      object LblMinSev: TLabel
        Left = 447
        Top = 8
        Width = 24
        Height = 15
        Caption = 'Min:'
      end
      object Button7: TButton
        Left = 127
        Top = 6
        Width = 97
        Height = 25
        Caption = 'Analyse file'
        TabOrder = 0
        OnClick = Button7Click
      end
      object Button6: TButton
        Left = 16
        Top = 6
        Width = 105
        Height = 25
        Caption = 'Analyse directory'
        TabOrder = 1
        OnClick = Button6Click
      end
      object BtnBranch: TButton
        Left = 230
        Top = 6
        Width = 36
        Height = 25
        Caption = #9095
        ParentShowHint = False
        ShowHint = True
        TabOrder = 2
        OnClick = BtnBranchClick
      end
      object ProfileCombo: TComboBox
        Left = 324
        Top = 6
        Width = 110
        Height = 23
        Style = csDropDownList
        TabOrder = 3
        OnChange = ProfileComboChange
      end
      object MinSevCombo: TComboBox
        Left = 477
        Top = 6
        Width = 116
        Height = 23
        Style = csDropDownList
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 4
        OnChange = MinSevComboChange
      end
      object FBtnHamburger: TButton
        Left = 608
        Top = 6
        Width = 24
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 5
        OnClick = Button2Click
      end
    end
    object Panel1: TPanel
      Left = 0
      Top = 35
      Width = 777
      Height = 43
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 1
      ExplicitWidth = 775
      DesignSize = (
        777
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
        Width = 504
        Height = 23
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
        Text = 'D:\git-demos\delphi\StaticCodeAnalyser\resources'
      end
      object Button2: TButton
        Left = 608
        Top = 14
        Width = 24
        Height = 23
        Anchors = [akTop, akRight]
        Caption = '...'
        TabOrder = 1
        OnClick = Button2Click
        ExplicitLeft = 606
      end
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 169
    Width = 777
    Height = 324
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    ExplicitWidth = 775
    ExplicitHeight = 316
    object ResultGrid: TStringGrid
      Left = 0
      Top = 0
      Width = 777
      Height = 324
      Align = alClient
      DefaultColWidth = 100
      DefaultRowHeight = 20
      FixedCols = 0
      RowCount = 2
      Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRangeSelect, goColSizing, goRowSelect, goThumbTracking]
      TabOrder = 0
      OnClick = ResultGridClick
      ExplicitWidth = 775
      ExplicitHeight = 316
      ColWidths = (
        176
        121
        50
        148
        100)
    end
  end
end
