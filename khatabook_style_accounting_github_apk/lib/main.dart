import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = LocalRepository();
  await repo.init();
  runApp(AccountingApp(repo: repo));
}

class AccountingApp extends StatelessWidget {
  final LocalRepository repo;
  const AccountingApp({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Khata',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF075EAD)),
        scaffoldBackgroundColor: const Color(0xFFF3F5F7),
      ),
      home: HomePage(repo: repo),
    );
  }
}

enum PartyType { customer, supplier }
enum EntryType { gave, got }

class Business {
  String id, name;
  Business({required this.id, required this.name});
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Business.fromJson(Map<String, dynamic> j) =>
      Business(id: j['id'], name: j['name']);
}

class Party {
  String id, businessId, name, phone;
  PartyType type;
  Party({required this.id, required this.businessId, required this.name,
      required this.phone, required this.type});

  Map<String, dynamic> toJson() => {
    'id': id, 'businessId': businessId, 'name': name, 'phone': phone,
    'type': type.name,
  };

  factory Party.fromJson(Map<String, dynamic> j) => Party(
    id: j['id'], businessId: j['businessId'], name: j['name'],
    phone: j['phone'] ?? '',
    type: PartyType.values.byName(j['type']),
  );
}

class Txn {
  String id, partyId, description;
  DateTime date;
  double amount;
  EntryType type;
  List<String> billPaths;

  Txn({required this.id, required this.partyId, required this.description,
      required this.date, required this.amount, required this.type,
      this.billPaths = const []});

  Map<String, dynamic> toJson() => {
    'id': id, 'partyId': partyId, 'description': description,
    'date': date.toIso8601String(), 'amount': amount, 'type': type.name,
    'billPaths': billPaths,
  };

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
    id: j['id'], partyId: j['partyId'], description: j['description'] ?? '',
    date: DateTime.parse(j['date']), amount: (j['amount'] as num).toDouble(),
    type: EntryType.values.byName(j['type']),
    billPaths: List<String>.from(j['billPaths'] ?? const []),
  );
}

class LocalRepository extends ChangeNotifier {
  late SharedPreferences prefs;
  List<Business> businesses = [];
  List<Party> parties = [];
  List<Txn> txns = [];

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    businesses = _decode('businesses', (x) => Business.fromJson(x));
    parties = _decode('parties', (x) => Party.fromJson(x));
    txns = _decode('txns', (x) => Txn.fromJson(x));
    if (businesses.isEmpty) {
      businesses.add(Business(id: _id(), name: 'My Business'));
      await save();
    }
  }

  String _id() => DateTime.now().microsecondsSinceEpoch.toString();

  List<T> _decode<T>(String key, T Function(Map<String,dynamic>) f) {
    final s = prefs.getString(key);
    if (s == null) return [];
    return (jsonDecode(s) as List).map((e) => f(Map<String,dynamic>.from(e))).toList();
  }

  Future<void> save() async {
    await prefs.setString('businesses', jsonEncode(businesses.map((e) => e.toJson()).toList()));
    await prefs.setString('parties', jsonEncode(parties.map((e) => e.toJson()).toList()));
    await prefs.setString('txns', jsonEncode(txns.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> addBusiness(String name) async {
    businesses.add(Business(id: _id(), name: name.trim()));
    await save();
  }

  Future<void> addParty(String businessId, String name, String phone, PartyType type) async {
    parties.add(Party(id: _id(), businessId: businessId, name: name.trim(),
        phone: phone.trim(), type: type));
    await save();
  }

  Future<void> addTxn(String partyId, String description, double amount,
      EntryType type, DateTime date, List<String> billPaths) async {
    txns.add(Txn(id: _id(), partyId: partyId, description: description,
        amount: amount, type: type, date: date, billPaths: billPaths));
    await save();
  }

  double balance(Party p) {
    double b = 0;
    for (final t in txns.where((x) => x.partyId == p.id)) {
      b += t.type == EntryType.gave ? t.amount : -t.amount;
    }
    return b;
  }

  List<Txn> partyTxns(Party p) =>
      txns.where((t) => t.partyId == p.id).toList()
        ..sort((a,b) => b.date.compareTo(a.date));

  double totalGave(Party p) => txns.where((t)=>t.partyId==p.id && t.type==EntryType.gave)
      .fold(0, (a,b)=>a+b.amount);
  double totalGot(Party p) => txns.where((t)=>t.partyId==p.id && t.type==EntryType.got)
      .fold(0, (a,b)=>a+b.amount);

  Future<void> exportExcel() async {
    final book = Excel.createExcel();
    final sheet = book['Ledger'];
    sheet.appendRow([TextCellValue('Business'), TextCellValue('Party'),
      TextCellValue('Type'), TextCellValue('Date'), TextCellValue('Description'),
      TextCellValue('Entry'), TextCellValue('Amount')]);
    for (final p in parties) {
      final b = businesses.firstWhere((x)=>x.id==p.businessId);
      for (final t in txns.where((x)=>x.partyId==p.id)) {
        sheet.appendRow([
          TextCellValue(b.name), TextCellValue(p.name), TextCellValue(p.type.name),
          TextCellValue(DateFormat('yyyy-MM-dd').format(t.date)),
          TextCellValue(t.description), TextCellValue(t.type.name),
          DoubleCellValue(t.amount)
        ]);
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/my_khata_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final bytes = book.encode();
    if (bytes != null) await File(path).writeAsBytes(bytes);
    await Share.shareXFiles([XFile(path)], text: 'My Khata data export');
  }

  Future<void> importExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx']);
    if (result == null || result.files.single.path == null) return;
    final bytes = File(result.files.single.path!).readAsBytesSync();
    final book = Excel.decodeBytes(bytes);
    final sheet = book.tables[book.tables.keys.first];
    if (sheet == null) return;
    for (var r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      if (row.length < 7) continue;
      String val(int i) => row[i]?.value?.toString() ?? '';
      final businessName = val(0);
      final partyName = val(1);
      final partyType = val(2) == 'supplier' ? PartyType.supplier : PartyType.customer;
      final desc = val(4);
      final entry = val(5) == 'got' ? EntryType.got : EntryType.gave;
      final amount = double.tryParse(val(6)) ?? 0;
      var b = businesses.where((x)=>x.name == businessName).firstOrNull;
      b ??= Business(id: _id(), name: businessName.isEmpty ? 'Imported Business' : businessName);
      if (!businesses.contains(b)) businesses.add(b);
      var p = parties.where((x)=>x.businessId==b!.id && x.name.toLowerCase()==partyName.toLowerCase()).firstOrNull;
      p ??= Party(id:_id(), businessId:b.id, name:partyName, phone:'', type:partyType);
      if (!parties.contains(p)) parties.add(p);
      txns.add(Txn(id:_id(), partyId:p.id, description:desc, date:DateTime.now(),
          amount:amount, type:entry));
    }
    await save();
  }
}

class HomePage extends StatefulWidget {
  final LocalRepository repo;
  const HomePage({super.key, required this.repo});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late String businessId;
  PartyType tab = PartyType.customer;

  @override
  void initState() {
    super.initState();
    businessId = widget.repo.businesses.first.id;
    widget.repo.addListener(_refresh);
  }
  void _refresh() => setState(() {});
  @override void dispose(){widget.repo.removeListener(_refresh); super.dispose();}

  List<Party> get filtered => widget.repo.parties
    .where((p)=>p.businessId==businessId && p.type==tab).toList()
    ..sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  double get totalOutstanding => filtered.fold(0,(s,p)=>s+widget.repo.balance(p));

  @override
  Widget build(BuildContext context) {
    final b = widget.repo.businesses.firstWhere((x)=>x.id==businessId);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF075EAD),
        foregroundColor: Colors.white,
        title: DropdownButton<String>(
          value: businessId,
          dropdownColor: Colors.white,
          underline: const SizedBox(),
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white,fontWeight: FontWeight.w600,fontSize:18),
          items: widget.repo.businesses.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.name))).toList(),
          onChanged:(v)=>setState(()=>businessId=v!),
        ),
        actions:[
          IconButton(onPressed:()=>widget.repo.exportExcel(),icon:const Icon(Icons.file_download)),
          PopupMenuButton<String>(
            onSelected:(v) async {
              if(v=='business') _addBusiness();
              if(v=='import') await widget.repo.importExcel();
            },
            itemBuilder:(_)=>const [
              PopupMenuItem(value:'business',child:Text('Add business')),
              PopupMenuItem(value:'import',child:Text('Import Excel')),
            ],
          )
        ],
      ),
      body: Column(children:[
        Container(
          color: const Color(0xFF075EAD),
          padding: const EdgeInsets.fromLTRB(16,0,16,14),
          child: Row(children:[
            Expanded(child:_tab('CUSTOMERS',PartyType.customer)),
            Expanded(child:_tab('SUPPLIERS',PartyType.supplier)),
          ]),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
            Text(tab==PartyType.customer?'Total Receivable':'Total Payable',
              style:const TextStyle(fontSize:16,color:Colors.black54)),
            Text('₹ ${totalOutstanding.abs().toStringAsFixed(2)}',
              style:TextStyle(fontSize:22,fontWeight:FontWeight.bold,
                color:totalOutstanding>=0?Colors.red.shade700:Colors.green.shade700))
          ]),
        ),
        Expanded(child: filtered.isEmpty
          ? const Center(child:Text('No entries yet. Tap + to add.'))
          : ListView.builder(itemCount:filtered.length,itemBuilder:(_,i){
              final p=filtered[i], bal=widget.repo.balance(p);
              return ListTile(
                tileColor:Colors.white,
                title:Text(p.name,style:const TextStyle(fontWeight:FontWeight.w600)),
                subtitle:Text(p.phone.isEmpty?'':p.phone),
                trailing:Text('₹ ${bal.abs().toStringAsFixed(2)}',
                  style:TextStyle(fontWeight:FontWeight.bold,
                    color:bal>=0?Colors.red.shade700:Colors.green.shade700)),
                onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>
                  LedgerPage(repo:widget.repo,party:p))),
              );
            })),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor:const Color(0xFF075EAD),foregroundColor:Colors.white,
        onPressed:_addParty,child:const Icon(Icons.add)),
    );
  }

  Widget _tab(String text, PartyType t)=>InkWell(
    onTap:()=>setState(()=>tab=t),
    child:Padding(padding:const EdgeInsets.all(12),
      child:Center(child:Text(text,style:TextStyle(color:Colors.white,
        fontWeight:tab==t?FontWeight.bold:FontWeight.normal)))));

  Future<void> _addBusiness() async {
    final c=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
      title:const Text('Add Business'),content:TextField(controller:c,autofocus:true,
      decoration:const InputDecoration(labelText:'Business name')),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(context,c.text.trim().isNotEmpty),child:const Text('Add'))]));
    if(ok==true){await widget.repo.addBusiness(c.text);setState(()=>businessId=widget.repo.businesses.last.id);}
  }

  Future<void> _addParty() async {
    final name=TextEditingController(), phone=TextEditingController();
    final picked=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(
      title:Text('Add ${tab==PartyType.customer?'Customer':'Supplier'}'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Name')),
        TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone')),
        Align(alignment:Alignment.centerLeft,child:TextButton.icon(
          onPressed:()async{
            if(await FlutterContacts.requestPermission()){
              final c=await FlutterContacts.openExternalPick();
              if(c!=null){name.text=c.displayName;phone.text=c.phones.isNotEmpty?c.phones.first.number:'';}
            }
          },icon:const Icon(Icons.contacts),label:const Text('Pick from contacts')))
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),
      FilledButton(onPressed:()=>Navigator.pop(context,name.text.trim().isNotEmpty),child:const Text('Save'))]));
    if(picked==true) await widget.repo.addParty(businessId,name.text,phone.text,tab);
  }
}

class LedgerPage extends StatefulWidget {
  final LocalRepository repo; final Party party;
  const LedgerPage({super.key,required this.repo,required this.party});
  @override State<LedgerPage> createState()=>_LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage>{
  DateTime? start,end;
  String search='';
  String filter='ALL';

  List<Txn> get rows {
    var list=widget.repo.partyTxns(widget.party);
    if(start!=null) list=list.where((t)=>!t.date.isBefore(start!)).toList();
    if(end!=null) list=list.where((t)=>!t.date.isAfter(end!)).toList();
    if(search.isNotEmpty) list=list.where((t)=>t.description.toLowerCase().contains(search.toLowerCase())).toList();
    if(filter!='ALL') list=list.where((t)=>t.type.name==filter.toLowerCase()).toList();
    return list;
  }

  double get gave=>rows.where((t)=>t.type==EntryType.gave).fold(0,(a,b)=>a+b.amount);
  double get got=>rows.where((t)=>t.type==EntryType.got).fold(0,(a,b)=>a+b.amount);

  @override Widget build(BuildContext context){
    final balance=widget.repo.balance(widget.party);
    return Scaffold(
      appBar:AppBar(backgroundColor:const Color(0xFF075EAD),foregroundColor:Colors.white,
        title:Text('Report of ${widget.party.name}'),
        actions:[IconButton(onPressed:_share,icon:const Icon(Icons.share))]),
      body:Column(children:[
        Container(color:const Color(0xFF075EAD),padding:const EdgeInsets.fromLTRB(16,0,16,14),
          child:Row(children:[
            Expanded(child:_dateBox('START DATE',start,(d)=>setState(()=>start=d))),
            const SizedBox(width:1),Expanded(child:_dateBox('END DATE',end,(d)=>setState(()=>end=d))),
          ])),
        Container(color:const Color(0xFF075EAD),padding:const EdgeInsets.fromLTRB(16,0,16,14),
          child:Row(children:[
            Expanded(child:TextField(
              onChanged:(v)=>setState(()=>search=v),style:const TextStyle(color:Colors.black87),
              decoration:InputDecoration(fillColor:Colors.white,filled:true,prefixIcon:const Icon(Icons.search),
                hintText:'Search Entries',border:OutlineInputBorder(borderRadius:BorderRadius.circular(4),
                borderSide:BorderSide.none)))),
            Container(width:110,height:56,color:const Color(0xFFDCEBFA),
              child:DropdownButtonHideUnderline(child:DropdownButton<String>(
                value:filter,isExpanded:true,padding:const EdgeInsets.symmetric(horizontal:12),
                items:const [DropdownMenuItem(value:'ALL',child:Text('ALL')),
                  DropdownMenuItem(value:'GAVE',child:Text('GAVE')),
                  DropdownMenuItem(value:'GOT',child:Text('GOT'))],
                onChanged:(v)=>setState(()=>filter=v!)))
          ]),
        Container(color:Colors.white,padding:const EdgeInsets.all(16),
          child:Column(children:[
            Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
              const Text('Net Balance',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
              Text('₹ ${balance.abs().toStringAsFixed(0)}',
                style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,
                  color:balance>=0?Colors.red.shade700:Colors.green.shade700))
            ]),
            const Divider(),
            Row(children:[
              Expanded(child:_stat('TOTAL','${rows.length} Entries',Colors.black54)),
              Expanded(child:_stat('YOU GAVE','₹ ${gave.toStringAsFixed(0)}',Colors.red.shade700)),
              Expanded(child:_stat('YOU GOT','₹ ${got.toStringAsFixed(0)}',Colors.green.shade700)),
            ])
          ])),
        Expanded(child:rows.isEmpty?const Center(child:Text('No transactions'))
          :ListView.builder(itemCount:rows.length,itemBuilder:(_,i)=>_row(rows[i],i))),
      ]),
      bottomNavigationBar:SafeArea(child:Container(color:Colors.white,padding:const EdgeInsets.all(16),
        child:Row(children:[
          Expanded(child:OutlinedButton.icon(onPressed:_share,icon:const Icon(Icons.picture_as_pdf),
            label:const Text('Download'))),
          const SizedBox(width:20),
          Expanded(child:FilledButton.icon(onPressed:_share,icon:const Icon(Icons.share),label:const Text('Share')))
        ]))),
      floatingActionButton:FloatingActionButton(
        backgroundColor:const Color(0xFF075EAD),foregroundColor:Colors.white,
        onPressed:_addTxn,child:const Icon(Icons.add))
    );
  }

  Widget _dateBox(String title,DateTime? value,void Function(DateTime) onPick)=>InkWell(
    onTap:()async{final d=await showDatePicker(context:context,firstDate:DateTime(2020),
      lastDate:DateTime(2100),initialDate:value??DateTime.now());if(d!=null)onPick(d);},
    child:Container(height:70,color:Colors.white,child:Row(mainAxisAlignment:MainAxisAlignment.center,
      children:[const Icon(Icons.calendar_month),const SizedBox(width:10),
      Text(value==null?title:DateFormat('dd MMM yy').format(value),
        style:const TextStyle(color:Color(0xFF075EAD),fontWeight:FontWeight.w600))])));

  Widget _stat(String a,String b,Color c)=>Column(crossAxisAlignment:CrossAxisAlignment.start,
    children:[Text(a,style:const TextStyle(color:Colors.black54)),const SizedBox(height:8),
      Text(b,style:TextStyle(fontSize:16,fontWeight:FontWeight.bold,color:c))]);

  Widget _row(Txn t,int i){
    final all=widget.repo.partyTxns(widget.party);
    final ordered=all.reversed.toList();
    double running=0;
    for(final x in ordered.take(ordered.indexOf(t)+1)) running+=x.type==EntryType.gave?x.amount:-x.amount;
    return Container(color:t.type==EntryType.gave?const Color(0xFFFFF4F4):Colors.white,
      child:ListTile(
        title:Text(DateFormat('dd MMM yy').format(t.date),style:const TextStyle(fontSize:18)),
        subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Bal. ₹ ${running.abs().toStringAsFixed(0)}',
            style:const TextStyle(backgroundColor:Color(0xFFFFF2F2),color:Colors.black54)),
          if(t.description.isNotEmpty)Text(t.description),
          if(t.billPaths.isNotEmpty)Text('${t.billPaths.length} bill photo(s)',
            style:const TextStyle(color:Colors.black54))
        ]),
        trailing:Text('₹ ${t.amount.toStringAsFixed(0)}',
          style:TextStyle(fontSize:18,fontWeight:FontWeight.bold,
            color:t.type==EntryType.gave?Colors.red.shade700:Colors.green.shade700)),
        onTap:()=>_shareTransaction(t),
      ));
  }

  Future<void> _addTxn() async {
    final amount=TextEditingController(),desc=TextEditingController();
    EntryType type=EntryType.gave; DateTime date=DateTime.now(); List<String> bills=[];
    final result=await showModalBottomSheet<bool>(context:context,isScrollControlled:true,builder:(_)=>
      StatefulBuilder(builder:(context,setModal)=>Padding(
        padding:EdgeInsets.only(bottom:MediaQuery.of(context).viewInsets.bottom),
        child:Container(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text('Add Transaction',style:Theme.of(context).textTheme.titleLarge),
          SegmentedButton<EntryType>(segments:const[
            ButtonSegment(value:EntryType.gave,label:Text('YOU GAVE')),
            ButtonSegment(value:EntryType.got,label:Text('YOU GOT'))],
            selected:{type},onSelectionChanged:(s)=>setModal(()=>type=s.first)),
          TextField(controller:amount,keyboardType:TextInputType.number,
            decoration:const InputDecoration(labelText:'Amount ₹')),
          TextField(controller:desc,decoration:const InputDecoration(labelText:'Description')),
          Row(children:[Text(DateFormat('dd MMM yyyy').format(date)),TextButton(onPressed:()async{
            final d=await showDatePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime(2100),initialDate:date);
            if(d!=null)setModal(()=>date=d);
          },child:const Text('Change date'))]),
          Row(children:[Text('${bills.length} bill photo(s)'),const Spacer(),
            TextButton.icon(onPressed:()async{
              final picked=await ImagePicker().pickMultiImage();
              if(picked.isNotEmpty)setModal(()=>bills=[...bills,...picked.map((x)=>x.path)]);
            },icon:const Icon(Icons.photo_library),label:const Text('Add bills'))]),
          const SizedBox(height:10),
          SizedBox(width:double.infinity,child:FilledButton(onPressed:(){
            final a=double.tryParse(amount.text);
            if(a!=null&&a>0)Navigator.pop(context,true);
          },child:const Text('SAVE')))
        ])))));
    if(result==true){
      await widget.repo.addTxn(widget.party.id,desc.text,double.parse(amount.text),type,date,bills);
      setState((){});
    }
  }

  Future<void> _shareTransaction(Txn t) async {
    await Share.share('My Khata\\n${widget.party.name}\\n${DateFormat('dd MMM yyyy').format(t.date)}\\n${t.type==EntryType.gave?'You Gave':'You Got'}: ₹${t.amount.toStringAsFixed(2)}\\nBalance: ₹${widget.repo.balance(widget.party).abs().toStringAsFixed(2)}');
  }

  Future<void> _share() async {
    final msg='${widget.party.name}\\nNet Balance: ₹${widget.repo.balance(widget.party).abs().toStringAsFixed(2)}\\nYou Gave: ₹${gave.toStringAsFixed(2)}\\nYou Got: ₹${got.toStringAsFixed(2)}\\nTotal Entries: ${rows.length}';
    if(widget.party.phone.isNotEmpty){
      final phone=widget.party.phone.replaceAll(RegExp(r'\\D'),'');
      final uri=Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
      if(await canLaunchUrl(uri)){await launchUrl(uri,mode:LaunchMode.externalApplication);return;}
    }
    await Share.share(msg);
  }
}
