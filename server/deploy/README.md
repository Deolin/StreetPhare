# Déploiement production StreetPhare — gestionnaire de processus

Le serveur StreetPhare lance **deux processus Node.js** qui doivent rester
disponibles en permanence :

| Processus | Script | Rôle | Port |
|---|---|---|---|
| `streetphare-primary` | `src/primary.js` | Serveur principal (reçoit, valide, réplique) | 3000 |
| `streetphare-backup` | `src/backup.js` | Miroir de secours (passif, prend le relais) | 3001 |

Le TLS est terminé par **Caddy** (voir `../Caddyfile`), lancé en processus
détaché par `primary.js` (`launchCaddyIndependent()`).

---

## Résilience anti-crash

Dans `src/primary.js` et `src/backup.js` :

- `uncaughtException` → sauvegarde l'état (`store.saveSync()`) puis **sort
  avec le code 1** afin que le gestionnaire de processus redémarre le serveur.
- `unhandledRejection` → journalise l'erreur sans tuer le serveur (les rejets
  sont généralement isolés et récupérables).

C'est le gestionnaire de processus (PM2 ou systemd) qui assure le
**redémarrage automatique** après un crash.

---

## Option A — PM2 (recommandé, multi-plateforme)

```bash
cd server
npm install            # installe pm2 (devDependency) + dépendances
npm run pm2:start      # démarre primary + backup
npm run pm2:status     # état des deux processus
npm run pm2:logs       # logs en direct
```

### Démarrage automatique au boot

```bash
npm run pm2:save                       # sauvegarde la liste des processus
pm2 startup                            # génère la commande d'init système
# exécuter la commande affichée par `pm2 startup` (sudo ...)
```

---

## Option B — systemd (Linux natif)

```bash
sudo cp deploy/streetphare-primary.service /etc/systemd/system/
sudo cp deploy/streetphare-backup.service /etc/systemd/system/

# Adaptez User / Group / WorkingDirectory dans les fichiers .service
# à votre déploiement (par défaut : user=streetphare, path=/opt/streetphare/server).

sudo systemctl daemon-reload
sudo systemctl enable --now streetphare-primary
sudo systemctl enable --now streetphare-backup

sudo systemctl status streetphare-primary   # vérifier l'état
journalctl -u streetphare-primary -f        # suivre les logs
```

> **Note** : les unités systemd ne chargent **pas** `.env` via
> `EnvironmentFile` — les secrets (`MASTER_KEY`, `JWT_SECRET`, `ADMIN_HASH`)
> sont lus par `dotenv` depuis `server/.env` (via `WorkingDirectory`). Cela
> évite le problème d'expansion des caractères `$` des hash bcrypt par systemd.

---

## Configuration (.env)

Copiez `.env.example` vers `.env` et renseignez **obligatoirement** en
production :

```bash
SERVER_TYPE=PRIMARY            # surchargé par PM2/systemd selon le rôle
MASTER_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
ADMIN_HASH=$(node -e "require('bcryptjs').hash('mot-de-passe', 12).then(h => console.log(h))")
```

Le serveur **refuse de démarrer** en `NODE_ENV=production` si ces valeurs
sont absentes ou restent aux valeurs par défaut.

---

## Redémarrage manuel

```bash
# PM2
npm run pm2:restart

# systemd
sudo systemctl restart streetphare-primary streetphare-backup
```
