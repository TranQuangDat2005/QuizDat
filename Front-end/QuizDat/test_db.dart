import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'lib/services/repository_service.dart';
import 'lib/services/set_card_service.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  try {
    print('Testing Repository Creation...');
    final repoService = RepositoryService();
    final repo = await repoService.createRepository('Test Repo', 'Test Desc');
    print('Created Repository: \${repo.repositoryId}');
    
    print('Testing SetCard Creation...');
    final setService = SetService();
    final setCard = await setService.createSetCard('Test Set', repo.repositoryId);
    print('Created SetCard: \${setCard.setId}');
    
    print('Success!');
  } catch (e, st) {
    print('Error caught: \$e');
    print(st);
  }
}
