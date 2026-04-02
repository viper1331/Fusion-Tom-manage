# Terrain bridge

Ce dossier contient le pont local PC <-> ComputerCraft pour la branche de brouillon terrain.

## Role

- servir une release locale publiee dans `tools/terrain_bridge/data/publish`
- exposer une commande par computer dans `tools/terrain_bridge/data/commands`
- recevoir les resultats dans `tools/terrain_bridge/data/results`
- recevoir les rapports dans `tools/terrain_bridge/data/reports`

## Endpoints

- `GET /` : ping service
- `GET /health` : healthcheck explicite
- `GET /activity` : dernieres activites (poll command / result / report / ack)
- `GET /command?computer=<name>` : lecture commande courante
- `POST /command/ack` : acquittement et suppression commande consommee
- `POST /result` : depot resultat
- `POST /report` : depot report
- `GET /publish/<path>` : telechargement bundle local

## Demarrage

```powershell
./tools/start_terrain_bridge.ps1
```

## Publication locale

```powershell
./tools/publish_local_release.ps1
```

## Ecriture d'une commande

```powershell
./tools/write_command.ps1 -Command sync_and_test
```

Si `-Computer` est omis, le script tente de lire `terrainAgent.computerName` dans `fusion_config.lua`, sinon retombe sur `fusion_terrain_01`.
Resolution exacte:
1. `-Computer` (si fourni)
2. `terrainAgent.computerName` depuis `fusion_config.lua` (si non vide)
3. dernier poll detecte dans `tools/terrain_bridge/data/activity.json`
4. fallback `fusion_terrain_01`

Si `-ExpectedVersion` est omis, le script tente de lire `fusion.version`.

## Boucle attendue

1. publier la release locale ;
2. ecrire une commande `sync_and_test` ;
3. le daemon terrain ComputerCraft telecharge la MAJ ;
4. le daemon lance les suites terrain ;
5. les rapports JSON remontent dans `data/reports`.

## Diagnostic rapide

Checklist quand `results/reports` ne montent pas :

1. `GET /health` renvoie `ok=true`.
2. `GET /activity` montre un `lastCommandPoll` recent pour le computer cible.
3. Le fichier `data/commands/<computer>.json` existe.
4. Le daemon ComputerCraft ecrit `/terrain_agent.heartbeat`.
5. Le startup ecrit `/terrain_agent.startup.log` (raison d'activation, erreurs boot, crash runLoop).
6. Le daemon loggue dans `/terrain_agent.log`.
7. Le daemon ecrit au moins `/terrain_agent.last_result.json`.
8. Le bridge recoit des POST dans `data/results` et `data/reports`.
