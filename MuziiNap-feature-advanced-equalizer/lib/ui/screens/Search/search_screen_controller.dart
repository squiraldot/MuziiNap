import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../../utils/app_link_controller.dart' show ProcessLink;
import '../../../services/music_service.dart';

class SearchScreenController extends GetxController with ProcessLink {
  final textInputController = TextEditingController();
  final musicServices = Get.find<MusicServices>();
  final suggestionList = [].obs;
  final historyQuerylist = [].obs;
  late Box<dynamic> queryBox;
  final urlPasted = false.obs;

  @override
  onInit() {
    _init();
    super.onInit();
  }

  _init() async {
    queryBox = await Hive.openBox("searchQuery");
    historyQuerylist.value = queryBox.values.toList().reversed.toList();
  }

  final historyIndex = (-1).obs;
  String? _savedSearchInput;
  int _suggestionRequestId = 0;

  bool get isHistory => suggestionList.isEmpty && (_savedSearchInput ?? textInputController.text).isEmpty;

  Future<void> onChanged(String text) async {
    _savedSearchInput = text;
    historyIndex.value = -1;
    final requestId = ++_suggestionRequestId;

    if (text.contains("https://")) {
      urlPasted.value = true;
      suggestionList.clear();
      return;
    }

    urlPasted.value = false;

    // Clearing the field should restore search history, not request empty
    // suggestions (some providers return null entries for an empty query).
    if (text.trim().isEmpty) {
      suggestionList.clear();
      return;
    }

    try {
      final suggestions = await musicServices.getSearchSuggestion(text);
      // Ignore stale responses when the user has already changed/cleared input.
      if (requestId != _suggestionRequestId ||
          textInputController.text != text) {
        return;
      }

      suggestionList.assignAll(
        suggestions
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && item.toLowerCase() != 'null'),
      );
    } catch (_) {
      if (requestId == _suggestionRequestId) {
        suggestionList.clear();
      }
    }
  }

  void arrowDown() {
    final list = suggestionList.isEmpty ? historyQuerylist : suggestionList;
    if (list.isEmpty) return;
    
    if (historyIndex.value == -1) {
      _savedSearchInput = textInputController.text;
    }
    
    if (historyIndex.value < list.length - 1) {
      historyIndex.value++;
      textInputController.text = list[historyIndex.value];
      textInputController.selection = TextSelection.collapsed(offset: textInputController.text.length);
    }
  }

  void arrowUp() {
    final list = suggestionList.isEmpty ? historyQuerylist : suggestionList;
    if (list.isEmpty) return;

    if (historyIndex.value > 0) {
      historyIndex.value--;
      textInputController.text = list[historyIndex.value];
      textInputController.selection = TextSelection.collapsed(offset: textInputController.text.length);
    } else if (historyIndex.value == 0) {
      historyIndex.value = -1;
      textInputController.text = _savedSearchInput ?? "";
      textInputController.selection = TextSelection.collapsed(offset: textInputController.text.length);
    }
  }

  Future<void> suggestionInput(String txt) async {
    textInputController.text = txt;
    textInputController.selection =
        TextSelection.collapsed(offset: textInputController.text.length);
    await onChanged(txt);
  }

  Future<void> addToHistryQueryList(String txt) async {
    if (historyQuerylist.length > 9) {
      final queryForRemoval = queryBox.getAt(0);
      await queryBox.deleteAt(0);
      historyQuerylist.removeWhere((element) => element == queryForRemoval);
    }
    if (!historyQuerylist.contains(txt)) {
      await queryBox.add(txt);
      historyQuerylist.insert(0, txt);
    }

    //reset current query and suggestionlist
    reset();
  }

  void reset() {
    _suggestionRequestId++;
    urlPasted.value = false;
    _savedSearchInput = null;
    textInputController.text = "";
    suggestionList.clear();
    historyIndex.value = -1;
  }

  Future<void> removeQueryFromHistory(String txt) async {
    final index = queryBox.values.toList().indexOf(txt);
    await queryBox.deleteAt(index);
    historyQuerylist.remove(txt);
  }

  @override
  void dispose() {
    textInputController.dispose();
    queryBox.close();
    super.dispose();
  }
}
