# Plan de travail - Implémentation Mode Isolé Total & Kill Switch

## Phase 1 : Exploration et Analyse du Code Existant
- [ ] Explorer la structure du projet Flutter (lib/)
- [ ] Analyser les services existants (connectivité, réseau, P2P)
- [ ] Analyser le backend serveur (test_servers/)
- [ ] Analyser le pubspec.yaml pour les dépendances
- [ ] Lire les fichiers de debug et logs existants

## Phase 2 : Implémentation Backend - Endpoint `/api/version/check`
- [ ] Ajouter l'endpoint version/check sur le serveur primaire (port 3000)
- [ ] Ajouter l'endpoint version/check sur le serveur secondaire (port 3001)
- [ ] Ajouter l'endpoint version/check sur le sandbox (port 4000)

## Phase 3 : Implémentation Flutter - Service de Connectivité (Mode Isolé Total)
- [ ] Implémenter l'écouteur d'état réseau dans ConnectivityService
- [ ] Implémenter la détection de topologie P2P dans P2PMeshService
- [ ] Implémenter la logique de déclenchement (serveurs injoignables + aucun pair Hive)
- [ ] Créer le widget/bannière d'alerte persistant

## Phase 4 : Implémentation Flutter - Kill Switch (Force Update)
- [ ] Créer le service de vérification de version (VersionCheckService)
- [ ] Implémenter l'appel HTTP à `/api/version/check` au démarrage
- [ ] Implémenter la logique de comparaison de versions
- [ ] Créer le dialogue modal bloquant (impossible à fermer)
- [ ] Intégrer les boutons "Quitter l'application" et "Mettre à jour manuellement"

## Phase 5 : Validation et Nettoyage
- [ ] Vérifier l'orthographe et la qualité des textes français
- [ ] Exécuter `flutter clean`
- [ ] Lancer le build Android
- [ ] Lancer le build Windows Desktop
- [ ] Simuler l'obsolescence depuis le sandbox (port 4000)