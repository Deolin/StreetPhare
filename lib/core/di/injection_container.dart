// lib/core/di/injection_container.dart
// Conteneur d'injection de dépendances pour StreetPhare.
//
// Centralise l'enregistrement et la résolution des services,
// cassant le pattern singleton statique (.instance) pour permettre
// le mocking dans les tests unitaires.
//
// Usage :
//   final svc = InjectionContainer.resolve<MyService>();
//
// Pour les tests :
//   InjectionContainer.register<MyService>(MockMyService());
//
// Référence : docs/STREETPHARE_AUDIT_COMPLET_v2.2.0.md — Anomalie M8

/// Clé d'identification de service pour le conteneur.
typedef ServiceKey<T> = Type;

/// Conteneur léger d'injection de dépendances.
///
/// Fonctionne comme un Service Locator avec possibilité
/// d'enregistrer des instances ou des factories.
class InjectionContainer {
  InjectionContainer._();

  static final Map<ServiceKey, dynamic> _instances = {};
  static final Map<ServiceKey, dynamic Function()> _factories = {};

  /// Enregistre une instance concrète (singleton).
  static void register<T>(T instance) {
    _instances[T] = instance;
  }

  /// Enregistre une factory (créera une nouvelle instance à chaque appel).
  static void registerFactory<T>(T Function() factory) {
    _factories[T] = factory;
  }

  /// Résout un service enregistré.
  ///
  /// Lance une [StateError] si le service n'est pas enregistré.
  static T resolve<T>() {
    if (_instances.containsKey(T)) {
      return _instances[T] as T;
    }
    if (_factories.containsKey(T)) {
      return _factories[T]!() as T;
    }
    throw StateError(
      'Service $T non enregistré dans le conteneur DI. '
      'Utilisez InjectionContainer.register<$T>(instance) au démarrage.',
    );
  }

  /// Vérifie si un service est enregistré.
  static bool isRegistered<T>() {
    return _instances.containsKey(T) || _factories.containsKey(T);
  }

  /// Supprime un service du conteneur (utile en tests).
  static void unregister<T>() {
    _instances.remove(T);
    _factories.remove(T);
  }

  /// Vide complètement le conteneur (utile en tearDown de tests).
  static void reset() {
    _instances.clear();
    _factories.clear();
  }

  /// Enregistre un remplacement (override) pour les tests.
  /// Retourne l'instance précédente pour restauration.
  static T? override<T>(T mockInstance) {
    final previous = _instances[T] as T?;
    _instances[T] = mockInstance;
    return previous;
  }
}