// test/avoidance_filters_test.dart
//
// Tests unitaires des préférences d'évitement du moteur de routage
// "Safe Path" (filtrage des zones à éviter).

import 'package:flutter_streetphare/core/models/alert_model.dart';
import 'package:flutter_streetphare/features/routing/domain/models/avoidance_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AvoidanceFilters — valeurs par défaut', () {
    const f = AvoidanceFilters();

    test('évite barrages, nasses, contrôles et rassemblements', () {
      expect(f.avoidBarrages, isTrue);
      expect(f.avoidNasses, isTrue);
      expect(f.avoidControles, isTrue);
      expect(f.avoidRassemblements, isTrue);
    });

    test('n\'évite pas accidents et autres par défaut', () {
      expect(f.avoidAccidents, isFalse);
      expect(f.avoidAutres, isFalse);
    });

    test('masterSwitch vaut true par défaut', () {
      expect(f.masterSwitch, isTrue);
    });
  });

  group('AvoidanceFilters — shouldAvoid (mapping AlertType)', () {
    const f = AvoidanceFilters();

    test('barrage → avoidBarrages', () {
      expect(f.shouldAvoid(AlertType.barrage), isTrue);
      expect(f.shouldAvoid(AlertType.filtre), isTrue); // filtre → avoidBarrages
    });

    test('casseurs → avoidRassemblements', () {
      expect(f.shouldAvoid(AlertType.casseurs), isTrue);
    });

    test('policiers → avoidControles', () {
      expect(f.shouldAvoid(AlertType.policiers), isTrue);
    });

    test('danger → avoidAccidents (false par défaut)', () {
      expect(f.shouldAvoid(AlertType.danger), isFalse);
    });

    test('types résiduels (panic, density, autre) → avoidAutres', () {
      expect(f.shouldAvoid(AlertType.panic), isFalse);
      expect(f.shouldAvoid(AlertType.density), isFalse);
      expect(f.shouldAvoid(AlertType.autre), isFalse);
    });
  });

  group('AvoidanceFilters — cohérence & sérialisation', () {
    test('allEnabled est true uniquement si tout est activé', () {
      expect(const AvoidanceFilters().allEnabled, isFalse);
      const all = AvoidanceFilters(
        avoidBarrages: true,
        avoidNasses: true,
        avoidControles: true,
        avoidAccidents: true,
        avoidRassemblements: true,
        avoidAutres: true,
      );
      expect(all.allEnabled, isTrue);
    });

    test('allDisabled est true si tout est désactivé', () {
      const none = AvoidanceFilters(
        avoidBarrages: false,
        avoidNasses: false,
        avoidControles: false,
        avoidAccidents: false,
        avoidRassemblements: false,
        avoidAutres: false,
      );
      expect(none.allDisabled, isTrue);
    });

    test('copyWith ne modifie que les champs fournis', () {
      const f = AvoidanceFilters();
      final g = f.copyWith(avoidBarrages: false, avoidAccidents: true);
      expect(g.avoidBarrages, isFalse);
      expect(g.avoidAccidents, isTrue);
      expect(g.avoidNasses, isTrue); // inchangé
    });

    test('toJson/fromJson round-trip', () {
      const f = AvoidanceFilters(avoidBarrages: false, avoidAutres: true);
      final g = AvoidanceFilters.fromJson(f.toJson());
      expect(g.avoidBarrages, isFalse);
      expect(g.avoidAutres, isTrue);
      expect(g.avoidNasses, isTrue);
    });
  });
}
