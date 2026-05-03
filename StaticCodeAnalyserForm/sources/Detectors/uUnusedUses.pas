unit uUnusedUses;

// AST-basierter Detektor fuer moeglicherweise ungenutzte uses-Eintraege.
//
// Kombiniert zwei Heuristiken:
//
//   H1 – Qualifizierter Bezeichner:
//        Sucht 'unitname.' als Praefix in Bezeichnern.
//        Beispiel: SysUtils.IntToStr  ->  'sysutils.' im Raw-Corpus
//
//   H2 – Bekannte Typen / Funktionen:
//        Prueft ob bekannte Bezeichner aus der Unit als eigenstaendige
//        Woerter im Quelltext vorkommen.
//        Beispiel: TStringList  ->  System.Classes ist benoetigt
//
// Einschraenkungen (keine 100% Sicherheit):
//   – Units mit reinem Initialisierungscode (z.B. Vcl.Themes)
//   – Bedingte Kompilierung ($IFDEF)
//   – Typen aus unbekannten (nicht gemappten) Units
//   Befunde sind daher immer Warnungen, keine Fehler.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnusedUsesDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // Baut zwei Corpus-Varianten:
    //   RawText  – lowercase, Punkte erhalten (fuer H1: 'sysutils.')
    //   WordText – lowercase, alle Nicht-Bezeichner durch Leerzeichen (fuer H2: ' tlist ')
    class procedure CollectText(Node: TAstNode;
      RawSB, WordSB: TStringBuilder); static;

    // Letzter Namensbestandteil: 'System.Classes' -> 'classes'
    class function ShortName(const QualName: string): string; static;

    // Units die nie gemeldet werden sollen
    class function IsAlwaysNeeded(const UnitLow: string): Boolean; static;

    // Bekannte oeffentliche Bezeichner einer Unit (fuer H2)
    class function KnownIdents(const UnitLow: string): TArray<string>; static;
  end;

implementation

{ ---- Hilfsmethoden ---- }

class function TUnusedUsesDetector.ShortName(const QualName: string): string;
var
  p: Integer;
begin
  p := LastDelimiter('.', QualName);
  if p > 0 then Result := Copy(QualName, p + 1, MaxInt)
  else          Result := QualName;
end;

class function TUnusedUsesDetector.IsAlwaysNeeded(const UnitLow: string): Boolean;
const
  SAFE: array[0..13] of string = (
    // Immer implizit benoetigt
    'system', 'sysinit',
    // Fast immer benoetigt (Basistypen, Exceptions, String-Funktionen)
    'sysutils', 'system.sysutils',
    // Windows-API: sehr haeufig indirekt benoetigt
    'windows', 'winapi.windows',
    'messages', 'winapi.messages',
    // VCL-Basiseinheiten (fast immer transitiv benoetigt)
    'types', 'system.types',
    'uitypes', 'system.uitypes',
    // Interfaces / unbekannte Abhaengigkeiten
    'activex', 'comobj'
  );
begin
  for var S in SAFE do
    if UnitLow = S then Exit(True);
  // Registration-Units (Konvention: enden auf 'reg')
  if UnitLow.EndsWith('reg') then Exit(True);
  Result := False;
end;

class procedure TUnusedUsesDetector.CollectText(Node: TAstNode;
  RawSB, WordSB: TStringBuilder);

  procedure Add(const S: string);
  var
    Low : string;
    Ch  : Char;
  begin
    if S = '' then Exit;
    Low := S.ToLower;
    // Raw: lowercase, Punkte beibehalten, sonstiges durch Leerzeichen
    RawSB.Append(' ');
    for Ch in Low do
    begin
      if CharInSet(Ch, ['a'..'z', '0'..'9', '_', '.']) then
        RawSB.Append(Ch)
      else
        RawSB.Append(' ');
    end;
    RawSB.Append(' ');
    // Word: nur Bezeichner-Zeichen, alles andere -> Leerzeichen
    WordSB.Append(' ');
    for Ch in Low do
    begin
      if CharInSet(Ch, ['a'..'z', '0'..'9', '_']) then
        WordSB.Append(Ch)
      else
        WordSB.Append(' ');
    end;
    WordSB.Append(' ');
  end;

begin
  if not Assigned(Node) then Exit;
  // nkUsesItem-Knoten NICHT aufnehmen: der Unit-Name selbst soll
  // nicht als "Verwendungsnachweis" gelten.
  if Node.Kind <> nkUsesItem then
  begin
    Add(Node.Name);
    Add(Node.TypeRef);
  end;
  for var Child in Node.Children do
    CollectText(Child, RawSB, WordSB);
end;

{ ---- Bekannte Bezeichner pro Unit (H2) ---- }

class function TUnusedUsesDetector.KnownIdents(
  const UnitLow: string): TArray<string>;
begin
  Result := [];

  // ══ System-Einheiten ══════════════════════════════════════════════════════

  if (UnitLow = 'system.classes') or (UnitLow = 'classes') then
    Result := ['tstringlist','tstrings','tmemorystream','tfilestream',
               'tstringstream','tresourcestream','tcomponent','tpersistent',
               'tlist','tobjectlist','tcollection','tthread','tnotifyevent',
               'thandlestream','tcustomstream','tinterfacelist',
               'tbinaryreader','tbinarywriter','tencoding',
               'registerclass','findclass','getclass',
               'tcomponentiterator','tcomponentenumerator',
               'tcollectionitem','townedcollection']

  else if UnitLow = 'system.generics.collections' then
    // TList<T>, TObjectList<T> und TArray<T> sind die haeufigsten Typen;
    // ohne sie wuerde jeder TList<>-Nutzer einen false positive erhalten.
    Result := ['tlist','tobjectlist','tarray',
               'tdictionary','tobjectdictionary',
               'tqueue','tstack','tpair',
               'tsortedlist','tenumerable',
               'tobjectqueue','tobjectstack']

  else if UnitLow = 'system.generics.defaults' then
    Result := ['tcomparer','tstringcomparer','icomparer',
               'iequalitycomparer','tequalitycomparer',
               'tdefaultcomparer','ticomparerref']

  else if (UnitLow = 'system.math') or (UnitLow = 'math') then
    Result := ['floor','ceil','sqrt','power','log10','log2',
               'arctan2','arcsin','arccos','tan','cot',
               'isnan','isinfinite','isinfinitevalue','sign',
               'divmod','max','min','hypot','ldexp','frexp',
               'intpower','lnxp1','sincos','logn']

  else if (UnitLow = 'system.strutils') or (UnitLow = 'strutils') then
    Result := ['posex','containsstr','startsstr','endsstr',
               'splitstring','joinstring','reversestring',
               'dupestring','wraptext','leftstr','rightstr','midstr',
               'countstr','ansicontainsstr','ansistartsstr',
               'ansistartstext','ansicontainstext','ansiindexstr',
               'contractwhitespace','expandwhitespace',
               'ifthen','finddelimiter']

  else if UnitLow = 'system.ioutils' then
    Result := ['tfile','tdirectory','tpath',
               'tcreationdisposition','tfileaccess','tfilesystemattrset',
               'tpathtoounittargettype']

  else if (UnitLow = 'system.inifiles') or (UnitLow = 'inifiles') then
    Result := ['tinifile','tmeminifile','tcustominifile',
               'thashedinitfile','treginifile']

  else if UnitLow = 'system.regularexpressions' then
    Result := ['tregex','tmatch','tmatchcollection','tgroupcollection',
               'tgroup','tregexoptions','isregex','tregexengine']

  else if UnitLow = 'system.json' then
    Result := ['tjsonobject','tjsonarray','tjsonvalue','tjsonstring',
               'tjsonnumber','tjsonbool','tjsonnull','tjsonpair',
               'tjsonserializer','tjsondeserializer','tjsonmarshal',
               'tjsonunmarshal','tjsonparser','tjsonreader']

  else if (UnitLow = 'system.dateutils') or (UnitLow = 'dateutils') then
    Result := ['dateof','timeof','daysbetween','monthsbetween','yearsbetween',
               'incday','incmonth','incyear','isinleapyear','weekof',
               'hoursbetween','minutesbetween','secondsbetween',
               'startoftheday','endoftheday','startofthemonth',
               'endofthemonth','startoftheyear','endoftheyear',
               'dayofweek','dayoftheyear','weekoftheyear',
               'encodedate','encodetime','encodedatetime',
               'decodedatetime','decodedate','decodetime',
               'today','now','yesterday','tomorrow']

  else if UnitLow = 'system.zip' then
    Result := ['tzipfile','tzipmode','tzipcompression',
               'tzipfileentry','tziponprogress']

  else if UnitLow = 'system.diagnostics' then
    Result := ['tstopwatch','ttimespan']

  else if UnitLow = 'system.threading' then
    Result := ['ttask','ittask','ttaskstatus','tparallel',
               'tfuture','tspinlock','tspinwait','tmonitor',
               'tinterlocked','tlightweightevent','tmrewlock']

  else if (UnitLow = 'system.hash') or (UnitLow = 'hash') then
    Result := ['thashmd5','thashsha1','thashsha2_256','thashsha2_512',
               'thashbobjenkins','thashfnv1a32','thash',
               'tbytes','thashsha2']

  else if (UnitLow = 'system.rtti') or (UnitLow = 'rtti') then
    Result := ['trtticontext','trttitype','trttimethod','trttifield',
               'trttiproperty','trttirecordfield','trttiparameter',
               'trttiobjecttype','trttiinstancetype','tvalue',
               'trttinamedargument','trttimethodtype']

  else if (UnitLow = 'system.typinfo') or (UnitLow = 'typinfo') then
    Result := ['getenumname','getenumvalue','getenumordvalue',
               'typeinfo','propinfo','ttypeinfo','ttypedata',
               'tpropinfo','tproplist','getproplist','getpropinfo',
               'getordprop','setordprop','getstrprop','setstrprop',
               'getfloatprop','setfloatprop','getobjectprop',
               'isobjectprop','propcount','tpropcount']

  else if (UnitLow = 'system.variants') or (UnitLow = 'variants') then
    Result := ['vartype','varastype','varisnull','varisempty',
               'vartostr','tvardata','varclear','varisarray',
               'varislongint','varisstring','vartostrdef',
               'varisordinal','varisfloat','varisdispatched']

  else if (UnitLow = 'system.character') or (UnitLow = 'character') then
    Result := ['tcharacter','isletter','isdigit','iswhitespace',
               'isupper','islower','ispunctuation','issymbol',
               'iscontrol','issurrogate','toupperfull','tolowerfull']

  else if (UnitLow = 'system.netencoding') or
          (UnitLow = 'system.net.encoding') then
    Result := ['tnetencoding','tbase64encoding','turlencodings',
               'thtmlencoding','tbase64urlencoding']

  else if (UnitLow = 'system.ansistrings') or (UnitLow = 'ansistrings') then
    Result := ['ansipos','ansicopy','ansicomparestr','ansicomparetext',
               'ansilowercase','ansiuppercase','ansiquotedstr',
               'ansiextractquotedstr','ansimidstr']

  else if (UnitLow = 'system.contnrs') or (UnitLow = 'contnrs') then
    Result := ['tobjectlist','tcomponentlist','tclasslist',
               'tobjectbucketlist','tqueuelist','tstacklist']

  else if UnitLow = 'system.net.httpclient' then
    Result := ['thttpclient','thttpresponse','thttprequest',
               'tcredentials','thttpclientcertificate',
               'tnamevaluepair','tproxysettings','thttprequestitem',
               'thttpclientcomponent','tnetencoding']

  else if (UnitLow = 'system.win.registry') or (UnitLow = 'registry') then
    Result := ['tregistry','tregistryconnection','tregistrydatatype',
               'treginifile','tregistrykey']

  else if (UnitLow = 'xml.xmldoc') or (UnitLow = 'xmldoc') then
    Result := ['txmldocument','ixmldocument','ixmlnode',
               'ixmlelementnode','ixmlnodelist','ixmlattr',
               'ixmlattributecollection','createxmldoc',
               'txmlnodetype','txmloption']

  else if (UnitLow = 'xml.xmlintf') or (UnitLow = 'xmlintf') then
    Result := ['ixmlnode','ixmldocument','ixmlnodelist',
               'ixmlelementnode','ixmlattr','txmlnodetype']

  // ══ Winapi-Einheiten ══════════════════════════════════════════════════════

  else if (UnitLow = 'winapi.shellapi') or (UnitLow = 'shellapi') then
    Result := ['shellexecute','shellexecuteex','shfileinfo',
               'shgetfileinfo','shgetspecialfolderpatha',
               'shgetspecialfolderpath','shbrowseforfolder',
               'tshellfolder','tshfileopstruct']

  else if (UnitLow = 'winapi.shlobj') or (UnitLow = 'shlobj') then
    Result := ['ishellfolder','ishellbrowser','ishellview',
               'titemidlist','pidl','comdlg32','shgetfolder']

  else if (UnitLow = 'winapi.commctrl') or (UnitLow = 'commctrl') then
    Result := ['ttbbutton','timagelist','ttvitem','tlvitem',
               'initcommoncontrols','initcommoncontrolsex']

  // ══ VCL-Einheiten ═════════════════════════════════════════════════════════

  else if (UnitLow = 'vcl.controls') or (UnitLow = 'controls') then
    Result := ['tcontrol','twincontrol','tcontainercontrol','tcustomcontrol',
               'tcursor','tdragmode','tcontrolstate','tgraphiccontrol',
               'tdockzone','tanchorstyle','tconstraintsize',
               'tcontrolactionlink','tscrollcontrol']

  else if (UnitLow = 'vcl.forms') or (UnitLow = 'forms') then
    Result := ['tform','tframe','tapplication','tscreen','tmonitor',
               'application','screen','printer',
               'tbordericons','tcloseaction','tformstyle',
               'tposition','twindowstate','tshowaction',
               'tapplicationevents','thintwindow','tformclass',
               'tscrollform','tcustomform']

  else if (UnitLow = 'vcl.stdctrls') or (UnitLow = 'stdctrls') then
    Result := ['tlabel','tbutton','tedit','tmemo','tcombobox','tlistbox',
               'tcheckbox','tgroupbox','tscrollbar','tstatictext',
               'tradiobutton','tcustomlabel','tcustombutton','tcustomedit',
               'tcustommemo','tcustomcombobox','tcustomlistbox',
               'tcustomcheckbox']

  else if (UnitLow = 'vcl.extctrls') or (UnitLow = 'extctrls') then
    Result := ['tpanel','ttimer','timage','tshape','tsplitter','tradiogroup',
               'tscrollbox','tbevel','tpaintbox','tflowpanel',
               'tcolorbox','tcontrolbar','tgridpanel',
               'tcustomgridpanel','tcustomflowpanel']

  else if (UnitLow = 'vcl.grids') or (UnitLow = 'grids') then
    Result := ['tstringgrid','tdrawgrid','tgridoption','tdrawstate',
               'tgridcoord','tcustomgrid','tselection',
               'tgridrowheights','tgridcolwidths']

  else if (UnitLow = 'vcl.dialogs') or (UnitLow = 'dialogs') then
    Result := ['showmessage','showmessagepos','messagedlg','messagedlgpos',
               'inputbox','inputquery',
               'topendialog','tsavedialog','tcolordialog','tfontdialog',
               'tfileopendialog','tfilesavedialog','tprintdialog',
               'tprinterdialog','tpagesetupdialog','tmessagedlg',
               'tfileopenorder','tmsgdlgbtn','tmsgdlgtype']

  else if (UnitLow = 'vcl.graphics') or (UnitLow = 'graphics') then
    Result := ['tbitmap','tcanvas','tfont','tpen','tbrush',
               'tcolor','tgraphic','ticon','tpicture','tmetafile',
               'tpenstyle','tpenstyle','tbrushedstyle','tfontstyle',
               'clred','clblue','clgreen','clblack','clwhite','clsyscolor',
               'colortostring','stringtocolor','rgbtocolor',
               'gettextextentpoint','tgraphicclass']

  else if (UnitLow = 'vcl.comctrls') or (UnitLow = 'comctrls') then
    Result := ['ttreeview','tlistview','tstatusbar','ttoolbar',
               'tpagecontrol','ttabcontrol','ttabsheet','trichedit',
               'tprogressbar','ttrackbar','tupdown','ttoolbutton',
               'ttreenode','ttreenodes','tlistitem','tlistitems',
               'tlistcolumn','tlistcolumns','tstatuspanel','tstatuspanels',
               'timageoptions']

  else if (UnitLow = 'vcl.menus') or (UnitLow = 'menus') then
    Result := ['tmainmenu','tpopupmenu','tmenuitem','tshortcut',
               'tcheckgroupmenuitem','tcustommenu','tmenuanimations']

  else if (UnitLow = 'vcl.clipbrd') or (UnitLow = 'clipbrd') then
    Result := ['clipboard','tclipboard','tclipboardformat']

  else if (UnitLow = 'vcl.imagelist') or (UnitLow = 'imagelist') then
    Result := ['timagelist','tcustomimagelist','timageindex',
               'timagelistdragobject']

  else if (UnitLow = 'vcl.actnlist') or (UnitLow = 'actnlist') then
    Result := ['tactionlist','taction','tcustomactionlist',
               'tbasicaction','tactionclientitem','tcontainedaction']

  else if (UnitLow = 'vcl.actns') or (UnitLow = 'actns') then
    Result := ['taction','tactionlist','tcustomaction','tcontrolaction',
               'tlistaction','texitaction','tgroupaction']

  else if (UnitLow = 'vcl.buttons') or (UnitLow = 'buttons') then
    Result := ['tbitbtn','tspeedbutton','tglyph',
               'tbitbtnkind','tspeedbutton']

  else if (UnitLow = 'vcl.checklst') or (UnitLow = 'checklst') then
    Result := ['tchecklistbox','tcheckedstate']

  else if (UnitLow = 'vcl.printing') or (UnitLow = 'printers') then
    Result := ['tprinter','printer','tprintrange','tprinterstatus',
               'tprinterorientation','abortdoc']

  else if (UnitLow = 'vcl.dbctrls') or (UnitLow = 'dbctrls') then
    Result := ['tdbedit','tdblabel','tdbmemo','tdbcombobox','tdblistbox',
               'tdbcheckbox','tdbradiogroup','tdbimage','tdbnavigator',
               'tdbtext','tdbrichtext','tnavbutton']

  else if (UnitLow = 'vcl.dbgrids') or (UnitLow = 'dbgrids') then
    Result := ['tdbgrid','tdbgridcolumn','tdbgridcolumns',
               'tcustomdbgrid','tdbgridoption']

  // ══ Datenbank-Einheiten ═══════════════════════════════════════════════════

  else if (UnitLow = 'data.db') or (UnitLow = 'db') then
    Result := ['tdataset','tfield','tfieldtype','tparam','tdatasource',
               'tdatalink','tbookmark','tfields','tparams',
               'tstringfield','tintegerfield','tfloatfield',
               'tbooleanfield','tdatetimefield','tblobfield',
               'tcalculatedfield','tlookupdataset','tcursorfield']

  else if (UnitLow = 'data.win.adodb') or (UnitLow = 'adodb') then
    Result := ['tadoconnection','tadoquery','tadocommand',
               'tadodataset','tadotable','tadostoredproc',
               'tconnectionstring','tadorecordset']

  else if (UnitLow = 'firedac.comp.client') then
    Result := ['tfdconnection','tfdquery','tfdcommand','tfdtable',
               'tfdmemtable','tfdstoredproc','tfdschemaadapter',
               'tfdguitransactionlinks']

  else if (UnitLow = 'firedac.stan.intf') then
    Result := ['ifdstanobject','ifdphysconnection','ifdphysdriver',
               'tfdresourceoptions']

  else if (UnitLow = 'firedac.stan.param') then
    Result := ['tfdparam','tfdparams']

  // ══ VCL – weitere Steuerelemente ═════════════════════════════════════════

  else if (UnitLow = 'vcl.mask') or (UnitLow = 'mask') then
    Result := ['tmaskedit','tcustommask','teditoption']

  else if (UnitLow = 'vcl.appevnts') or (UnitLow = 'appevnts') then
    Result := ['tapplicationevents']

  else if (UnitLow = 'vcl.filectrl') or (UnitLow = 'filectrl') then
    Result := ['tdirectorylistbox','tfilelistbox','tdrivecombobox',
               'tfilenameedit','tdirectorynameedit','tselectdirectory']

  else if (UnitLow = 'vcl.winxctrls') or (UnitLow = 'winxctrls') then
    Result := ['tsearchbox','tactivityindicator','ttoggleswitch',
               'trelativepanel','twrappanel','tsplitview']

  else if (UnitLow = 'vcl.categorybuttons') or (UnitLow = 'categorybuttons') then
    Result := ['tcategorybuttons','tcategoryitem','tbuttoncategory']

  else if (UnitLow = 'vcl.taskbar') or (UnitLow = 'taskbar') then
    Result := ['ttaskbar','ttaskbarprogress','tthumbnailbutton']

  else if (UnitLow = 'vcl.numberbox') or (UnitLow = 'numberbox') then
    Result := ['tnumberbox']

  else if (UnitLow = 'vcl.colorbutton') or (UnitLow = 'colorbutton') then
    Result := ['tcolorbutton']

  else if (UnitLow = 'vcl.htmlhelpviewer') then
    Result := ['thtmlhelpviewer']

  else if (UnitLow = 'vcl.olectrls') or (UnitLow = 'olectrls') then
    Result := ['tolecontrol','tactivexcontrol','toleinplaceobject']

  else if (UnitLow = 'vcl.shell.shellctrls') then
    Result := ['tshelltreeview','tshelllistview','tshellcombobox']

  // ══ System – Threading & Synchronisation ═════════════════════════════════

  else if (UnitLow = 'system.syncobjs') or (UnitLow = 'syncobjs') then
    Result := ['tcriticalsection','tmutex','tevent','tsemaphore',
               'tconditionvariablecs','tconditionvariablemres',
               'tlightweightevent','tspinlock']

  else if (UnitLow = 'system.messaging') or (UnitLow = 'messaging') then
    Result := ['tmessagemanager','tmessage','tmsgreceivedevent',
               'tmessagelistener','tmsgsendoreceive']

  else if (UnitLow = 'system.actions') or (UnitLow = 'actions') then
    Result := ['tactionlist','tcustomactionlist','tbasicaction',
               'tcommonactionlink']

  // ══ System – Netzwerk & Internet ══════════════════════════════════════════

  else if (UnitLow = 'system.net.urlclient') then
    Result := ['turlclient','turlrequest','turlresponse',
               'tnamevaluepair','tproxysettings','turlscheme']

  else if (UnitLow = 'system.net.mime') then
    Result := ['tmultipartformdata','tmimepart','tformfield']

  else if (UnitLow = 'system.net.httpclientcomponent') then
    Result := ['tnethttpclient','tnethttprequest']

  // ══ REST / JSON ═══════════════════════════════════════════════════════════

  else if (UnitLow = 'rest.client') then
    Result := ['trestclient','trestrequest','trestresponse',
               'trestcomponent','tauthenticator']

  else if (UnitLow = 'rest.types') then
    Result := ['trestoption','trestcontenttype','trequestparamkind',
               'trestresponsedatatype']

  else if (UnitLow = 'rest.response.adapter') then
    Result := ['trestresponsedatasetadapter','tjsontoobjectadapter']

  else if (UnitLow = 'rest.json') or (UnitLow = 'rest.json.types') then
    Result := ['tjson','tsjsonserializer','tjsonserialize',
               'tjsonunmarshal','tjsonmarshal']

  else if (UnitLow = 'rest.authenticator.oauth') then
    Result := ['toauth1authenticator','toauth2authenticator',
               'toauthaccesstokentype']

  // ══ Indy (Internet Direct) ════════════════════════════════════════════════

  else if (UnitLow = 'idhttp') then
    Result := ['tidhttp','tidhttprequestinfo','tidhttpresponseinfo',
               'tidcookiemanager']

  else if (UnitLow = 'idtcpclient') or (UnitLow = 'idtcp') then
    Result := ['tidtcpclient','tidtcpserver','tidcontext']

  else if (UnitLow = 'idsmtp') then
    Result := ['tidsmtp','tidmessage','tidattachment']

  else if (UnitLow = 'idftp') then
    Result := ['tidftp','tidftpdirectoryentry']

  else if (UnitLow = 'idpop3') then
    Result := ['tidpop3']

  else if (UnitLow = 'idssliopensslheaders') or
          (UnitLow = 'idssl') or
          (UnitLow = 'idsslopenssl') then
    Result := ['tidssliohannlersocketopenssl','tidsslopenssl',
               'tidssliohandleropenssl']

  else if (UnitLow = 'idiohandler') or (UnitLow = 'idiohandlerstack') then
    Result := ['tidiohandler','tidiohandlerstack','tidiohandlersocket']

  // ══ FireMonkey (FMX) ══════════════════════════════════════════════════════

  else if (UnitLow = 'fmx.types') then
    Result := ['tfmxobject','talignlayout','talign','trotation',
               'tnativeuint','tfmxcontrol']

  else if (UnitLow = 'fmx.controls') then
    Result := ['tcontrol','tcontainercontrol','tstyledcontrol',
               'tcustomcontrol','tgraphiccontrol','tinteractiveobject']

  else if (UnitLow = 'fmx.forms') then
    Result := ['tform','tcommonform','tapplication','tscreen',
               'application','screen','tformstyle','tcloseevent']

  else if (UnitLow = 'fmx.stdctrls') then
    Result := ['tlabel','tbutton','tspeedbutton','tcheckbox',
               'tradiobutton','tgroupbox','tswitch','ttrackbar',
               'tprogressbar','tscrollbar','tsegmentedcontrol',
               'texpander','tcaption','tstatusbar']

  else if (UnitLow = 'fmx.edit') then
    Result := ['tedit','tcustomedit','tcleareditbutton',
               'tpasswordedit','tnumedit']

  else if (UnitLow = 'fmx.memo') then
    Result := ['tmemo','tcustommemo']

  else if (UnitLow = 'fmx.combedit') then
    Result := ['tcomboedit']

  else if (UnitLow = 'fmx.listbox') then
    Result := ['tlistbox','tlistboxitem','tlistboxgroup',
               'tlistboxscrollbar','tcustomlistbox']

  else if (UnitLow = 'fmx.listview') then
    Result := ['tlistview','tlistviewitem','tlistviewitemappearance',
               'tlistviewappearance','tlistitem']

  else if (UnitLow = 'fmx.treeview') then
    Result := ['ttreeview','ttreeviewitem']

  else if (UnitLow = 'fmx.tabcontrol') then
    Result := ['ttabcontrol','ttabitem']

  else if (UnitLow = 'fmx.layouts') then
    Result := ['tlayout','tscaledlayout','tgridlayout','tflowlayout',
               'twraplayout','tvertscrollbox','thorzscrollbox',
               'tscrollbox','tframedsscrollbox']

  else if (UnitLow = 'fmx.objects') then
    Result := ['trectangle','tcircle','tellipse','tline','tpath',
               'timage','ttext','tselectionpoint','tcalloutrecangle']

  else if (UnitLow = 'fmx.grid') then
    Result := ['tgrid','tstringgrid','tcolumn','tstringcolumn',
               'tcheckcolumn','tnumbercolumn','tpopupcolumn']

  else if (UnitLow = 'fmx.dialogs') then
    Result := ['showmessage','messagedlg','inputbox','inputquery',
               'topendialog','tsavedialog','tmessagedialog']

  else if (UnitLow = 'fmx.graphics') then
    Result := ['tbitmap','tcanvas','tfill','tstroke','tfont',
               'tbitmapdata','tcolor','talphacolor','talphacolorrec',
               'tgradient','tgradientpoint','tbitmapsurface']

  else if (UnitLow = 'fmx.media') then
    Result := ['tmediaplayer','tcapturesetting','tmicrophonecapturedevice',
               'tcapturedevice','tvideocapturedevice']

  else if (UnitLow = 'fmx.maps') then
    Result := ['tmapview','tmaplocation','tmapdescriptor']

  else if (UnitLow = 'fmx.ani') then
    Result := ['tanimation','tfloatanimation','tcoloranimation',
               'tpathanimation','tbitmapanimation','tintanimation',
               'tanimator']

  else if (UnitLow = 'fmx.effects') then
    Result := ['teffect','tshadoweffect','tgloweffect','tblureffect',
               'treflectioneffect','tembosseffect']

  else if (UnitLow = 'fmx.multiview') then
    Result := ['tmultiview','tmultitviewpanel']

  else if (UnitLow = 'fmx.calendars') then
    Result := ['tcalendarview','tdatepicker']

  // ══ Winapi – weitere Einheiten ════════════════════════════════════════════

  else if (UnitLow = 'winapi.winsock2') or (UnitLow = 'winsock2') then
    Result := ['tsocket','twsadata','tfd_set','tsockaddr',
               'wsastartup','wsacleanup','gethostbyname']

  else if (UnitLow = 'winapi.tlhelp32') or (UnitLow = 'tlhelp32') then
    Result := ['tprocessentry32','tthreadentry32','tmoduleentry32',
               'createtoolhelp32snapshot','process32first','process32next']

  else if (UnitLow = 'winapi.psapi') or (UnitLow = 'psapi') then
    Result := ['tmoduleinfo','enumprocesses','enumprocessmodules',
               'getmodulefilename','getprocessmemoryinfo']

  else if (UnitLow = 'winapi.wininet') or (UnitLow = 'wininet') then
    Result := ['tinternethandle','internetopen','internetconnect',
               'httpsendrequesta','internetclosehandle']

  else if (UnitLow = 'winapi.activex') or (UnitLow = 'activex') then
    Result := ['iunknown','idispatch','tguid','ioleinplaceobject',
               'ioleobject','ioleclientsite','olecheck',
               'createcomobject','cogettypes']

  else if (UnitLow = 'winapi.taskschd') or (UnitLow = 'taskschd') then
    Result := ['itaskscheduler','itaskservice','itask',
               'itaskfolder','itasktrigger']

  else if (UnitLow = 'winapi.gdiplusgraphics') or
          (UnitLow = 'gdiplusapi') then
    Result := ['tgdiplus','tgraphics','tbitmap','tpen','tbrush',
               'tstringformat','tfont']

  // ══ IBX / InterBase ═══════════════════════════════════════════════════════

  else if (UnitLow = 'ibx.ibdatabase') or (UnitLow = 'ibdatabase') then
    Result := ['tibdatabase','tibtransaction','tibsql']

  else if (UnitLow = 'ibx.ibquery') or (UnitLow = 'ibquery') then
    Result := ['tibquery','tibstoredproc']

  else if (UnitLow = 'ibx.ibsql') or (UnitLow = 'ibsql') then
    Result := ['tibsql','tibsqltype','tibxsqlvar']

  // ══ DBX / SQLExpress ══════════════════════════════════════════════════════

  else if (UnitLow = 'data.dbxcommon') or (UnitLow = 'dbxcommon') then
    Result := ['tsqlconnection','tsqlquery','tsqldataset',
               'tsqlstoredproc','tsqlmonitor']

  // ══ Sonstige ══════════════════════════════════════════════════════════════

  else if (UnitLow = 'vcl.themes') or (UnitLow = 'themes') then
    Result := ['tthemeservices','tthermemanager']

  else if (UnitLow = 'vcl.styles') or (UnitLow = 'styles') then
    Result := ['tthemeservices','tstylecollection','tstylemanager']

  else if (UnitLow = 'vcl.platformvcl') or
          (UnitLow = 'vcl.platformvclstyles') then
    Result := ['tplatformvclstylsservice']

  else if (UnitLow = 'fmx.platform') then
    Result := ['iinterface','ifdtextinput','ifontmanager',
               'imultitouch','igenericplatformservice']

  else if (UnitLow = 'system.bluetooth') then
    Result := ['tbluetooth','tbluetoothdevice','tbluetoothle',
               'tbluetoothgattcharacteristic','tbluetoothmanager']

  else if (UnitLow = 'system.sensors') or
          (UnitLow = 'system.sensors.components') then
    Result := ['tsensormanager','tsensor','taccelerometersensor',
               'tgyroscopesensor','tlocationsensor',
               'tlocationsensorcomponent']

  else if (UnitLow = 'system.notification') then
    Result := ['tnotificationcenter','tnotification',
               'tnotificationpresentation']

  else if (UnitLow = 'system.tether.manager') or
          (UnitLow = 'system.tether.appprofile') then
    Result := ['ttetheringmanager','ttetheringappprofile',
               'ttetheringresource']

  else if (UnitLow = 'system.pushnotification') then
    Result := ['tpushserviceconnection','tpushservice',
               'tpushnotificationservice'];
end;

{ ---- Oeffentliche API ---- }

class procedure TUnusedUsesDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  UsesItems  : TList<TAstNode>;
  RawSB, WordSB : TStringBuilder;
  RawText    : string;   // lowercase mit Punkten: fuer H1
  WordText   : string;   // lowercase nur Bezeichner: fuer H2
  Reported   : TDictionary<string, Boolean>;
  Item       : TAstNode;
  UnitLow    : string;
  ShortLow   : string;
  Found      : Boolean;
  F          : TLeakFinding;
begin
  RawSB  := TStringBuilder.Create;
  WordSB := TStringBuilder.Create;
  try
    CollectText(UnitNode, RawSB, WordSB);
    RawText  := RawSB.ToString;
    WordText := WordSB.ToString;
  finally
    RawSB.Free;
    WordSB.Free;
  end;

  Reported  := TDictionary<string, Boolean>.Create;
  UsesItems := UnitNode.FindAll(nkUsesItem);
  try
    for Item in UsesItems do
    begin
      UnitLow  := Item.Name.ToLower;
      ShortLow := ShortName(UnitLow);

      // Duplikate (gleiche Unit in Interface + Implementation) einmal melden
      if Reported.ContainsKey(UnitLow) then Continue;

      if IsAlwaysNeeded(UnitLow)  then Continue;
      if IsAlwaysNeeded(ShortLow) then Continue;

      Found := False;

      // ── H1: Qualifizierter Bezeichner ('sysutils.' im Raw-Text) ───────────
      if (Pos(ShortLow + '.', RawText)  > 0) or
         (Pos(UnitLow  + '.', RawText)  > 0) then
        Found := True;

      // ── H2: Bekannte Bezeichner im Word-Text ──────────────────────────────
      if not Found then
      begin
        var Idents := KnownIdents(UnitLow);
        if Length(Idents) = 0 then
          Idents := KnownIdents(ShortLow);

        // Unbekannte Unit (kein Mapping): Verwendung nicht bestimmbar.
        // Ohne Mapping wuerden alle unbekannten Units fälschlich als unused
        // gemeldet → lieber false negative als false positive.
        if Length(Idents) = 0 then Continue;

        for var Id in Idents do
        begin
          if Pos(' ' + Id + ' ', WordText) > 0 then
          begin
            Found := True;
            Break;
          end;
        end;
      end;

      if Found then Continue;

      // H1 und H2 haben keine Verwendung gefunden → melden
      Reported.AddOrSetValue(UnitLow, True);
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(Item.Line);
      F.MissingVar := Item.Name;
      F.Severity   := lsWarning;
      F.Kind       := fkUnusedUses;
      Results.Add(F);
    end;
  finally
    UsesItems.Free;
    Reported.Free;
  end;
end;

end.
