// Test widget basique pour StreetPhare
//
// Ce test vérifie simplement que l'application démarre correctement
// (le splash screen s'affiche sans erreur).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_streetphare/main.dart';

void main() {
  // Initialisation de SharedPreferences pour les tests
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('L\'application StreetPhare démarre et affiche le splash',
      (WidgetTester tester) async {
    // Construction de l'application
    await tester.pumpWidget(const StreetPhareApp());
    await tester.pump();

    // Vérification que le titre "StreetPhare" est présent dans le splash
    expect(find.text('StreetPhare'), findsWidgets);

    // Vérification qu'un indicateur de chargement est présent
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
