object CustomerForm: TCustomerForm
  Left = 0
  Top = 0
  Caption = 'Kundenpflege'
  ClientHeight = 442
  ClientWidth = 698
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  TextHeight = 13
  object pnlForm: TPanel
    Left = 0
    Top = 0
    Width = 698
    Height = 393
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 0
    object lblName: TLabel
      Left = 24
      Top = 24
      Width = 29
      Height = 13
      Caption = 'Name'
    end
    object lblEmail: TLabel
      Left = 24
      Top = 60
      Width = 27
      Height = 13
      Caption = 'Email'
    end
    object lblIsActive: TLabel
      Left = 24
      Top = 96
      Width = 25
      Height = 13
      Caption = 'Aktiv'
    end
    object lblBirthdate: TLabel
      Left = 24
      Top = 132
      Width = 74
      Height = 13
      Caption = 'Geburtsdatum'
    end
    object edName: TDBEdit
      Left = 120
      Top = 21
      Width = 240
      Height = 21
      DataField = 'Name'
      DataSource = dsCustomers
      TabOrder = 0
    end
    object edEmail: TDBEdit
      Left = 120
      Top = 57
      Width = 240
      Height = 21
      DataField = 'Email'
      DataSource = dsCustomers
      TabOrder = 1
    end
    object edIsActive: TDBEdit
      Left = 120
      Top = 93
      Width = 60
      Height = 21
      DataField = 'IsActive'
      DataSource = dsCustomers
      TabOrder = 2
    end
    object edBirthdate: TDBEdit
      Left = 120
      Top = 129
      Width = 120
      Height = 21
      DataField = 'Birthdate'
      DataSource = dsCustomers
      TabOrder = 3
    end
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 393
    Width = 698
    Height = 49
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnSave: TButton
      Left = 16
      Top = 12
      Width = 100
      Height = 25
      Action = actSave
      TabOrder = 0
      OnClick = btnSaveClick
    end
    object Button1: TButton
      Left = 128
      Top = 12
      Width = 100
      Height = 25
      Action = actCancel
      TabOrder = 1
    end
  end
  object qCustomers: TFDQuery
    SQL.Strings = (
      'SELECT ID, Name, Email, IsActive, Birthdate'
      'FROM Customers'
      'ORDER BY Name')
    Left = 32
    Top = 16
    object qCustomersID: TIntegerField
      FieldName = 'ID'
      Required = True
    end
    object qCustomersName: TStringField
      FieldName = 'Name'
      Required = True
      Size = 100
    end
    object qCustomersEmail: TStringField
      FieldName = 'Email'
      Size = 100
    end
    object qCustomersIsActive: TBooleanField
      FieldName = 'IsActive'
    end
    object qCustomersBirthdate: TDateField
      FieldName = 'Birthdate'
    end
  end
  object dspCustomers: TDataSetProvider
    DataSet = qCustomers
    Left = 88
    Top = 16
  end
  object cdsCustomers: TClientDataSet
    Aggregates = <>
    Params = <>
    ProviderName = 'dspCustomers'
    Left = 144
    Top = 16
    object cdsCustomersID: TIntegerField
      FieldName = 'ID'
      Required = True
    end
    object cdsCustomersName: TStringField
      FieldName = 'Name'
      Required = True
      Size = 100
    end
    object cdsCustomersEmail: TStringField
      FieldName = 'Email'
      Size = 100
    end
    object cdsCustomersIsActive: TBooleanField
      FieldName = 'IsActive'
    end
    object cdsCustomersBirthdate: TDateField
      FieldName = 'Birthdate'
    end
  end
  object dsCustomers: TDataSource
    DataSet = cdsCustomers
    Left = 200
    Top = 16
  end
  object alMain: TActionList
    Left = 256
    Top = 16
    object actSave: TAction
      Caption = 'Speichern'
      Hint = 'Aenderungen speichern'
      ShortCut = 16467
      OnExecute = actSaveExecute
    end
    object actCancel: TAction
      Caption = 'Abbrechen'
    end
  end
end
