import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'utils_impl.dart';

class Utils implements UtilsImpl {
  Utils._();
  static final Utils _utils = Utils._();
  static final lastPathComponentRegEx = RegExp(r'[^/\\]+[/\\]?$');
  static Utils get instance => _utils;
  String? _customSavePath;
  bool useSupportDir = false;
  final _storageCache = <String, StreamController<Map<String, dynamic>>>{};

  SharedPreferences? prefs;

  Future<SharedPreferences> getSharedPreferences() async {
    return await SharedPreferences.getInstance();
  }

  @override
  void setCustomSavePath(String path) {
    _customSavePath = path;
    _utils.setCustomSavePath(_customSavePath!);
  }

  @override
  void setUseSupportDirectory(bool useSupportDir) {
    this.useSupportDir = useSupportDir;
  }

  @override
  Future<Map<String, dynamic>?> get(String path, [bool? isCollection = false, List<List>? conditions]) async {
    // Fetch the documents for this collection

    print('path ::: $path');

    prefs = await getSharedPreferences();
    final List<String>? items = prefs?.getStringList('items');
    print('prefs ::: $items');
    if( items != null ){
      return await _getAll(items,path);
    }else{
      return null;
    }

  }

  @override
  Future<dynamic>? set(Map<String, dynamic> data, String path) {
    return _writeFile(data, path);
  }

  @override
  Future delete(String path) async {
    if (path.endsWith(Platform.pathSeparator)) {
      _deleteDirectory(path);
    } else {
      _deleteFile(path);
    }
  }

  @override
  Stream<Map<String, dynamic>> stream(String path, [List<List>? conditions]) {
    // ignore: close_sinks
    var storage = _storageCache[path];
    if (storage == null) {
      storage = _storageCache.putIfAbsent(path, () => _newStream(path));
    } else {
      _initStream(storage, path);
    }
    return storage.stream;
  }

  Future<Map<String, dynamic>?> _getAll(List<String> entries,String path) async {
    print('_getAll ::: $entries');
    final items = <String, dynamic>{};
    entries.forEach((element) {
      String itemName = '$path$element';
      final String? itemJson = prefs?.getString(itemName);
      final Map<String, dynamic> itemMap = jsonDecode(itemJson!);
      items[itemName] = itemMap;
    });

    if (items.isEmpty) return null;
    print('items ::: $items');
    return items;
  }

  /// Streams all file in the path
  StreamController<Map<String, dynamic>> _newStream(String path) {
    final storage = StreamController<Map<String, dynamic>>.broadcast();
    _initStream(storage, path);
    return storage;
  }

  Future _initStream(
    StreamController<Map<String, dynamic>> storage,
    String path,
  ) async {

    print('_initStream ::: $path');
    prefs = await getSharedPreferences();
    final List<String>? items = prefs?.getStringList('items');

    if( items != null ){
      items.forEach((element) {
        String itemName = '$path$element';
        final String? itemJson = prefs?.getString(itemName);
        final Map<String, dynamic> itemMap = jsonDecode(itemJson!);
        storage.add(itemMap);
      });
    }

  }

  Future _writeFile(Map<String, dynamic> data, String path) async {

    print('_writeFile ::: $path ::: $data');

    prefs = await getSharedPreferences();
    List<String>? items = prefs?.getStringList('items');
    String itemName = path.split('/').last;

    if( items != null ){
      if( !items.contains(itemName) ){
        items.add(itemName);
        prefs?.remove('items');
        prefs?.setStringList('items', items);
      }
    }else{
      prefs?.setStringList('items', [itemName]);
    }

    await prefs?.setString(path, jsonEncode(data));

    final key = path.replaceAll(lastPathComponentRegEx, '');
    final storage = _storageCache.putIfAbsent(key, () => _newStream(key));
    storage.add(data);

  }

  Future _deleteFile(String path) async {

    print('_deleteFile ::: $path');

    prefs = await getSharedPreferences();
    List<String>? items = prefs?.getStringList('items');

    String itemName = path.split('/').last;

    if( items != null && items.contains(itemName) ){
      items.remove(itemName);
      prefs?.remove('items');
      prefs?.setStringList('items', items);
    }

    await prefs?.remove(path);

  }

  Future _deleteDirectory(String path) async {

    print('_deleteDirectory ::: $path');

    prefs = await getSharedPreferences();
    List<String>? items = prefs?.getStringList('items');

    if( items != null ){
      items.forEach((element) {
        String itemName = '$path$element';
        prefs?.remove(itemName);
      });
    }

    prefs?.remove('items');

  }
}
