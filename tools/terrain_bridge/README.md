# Terrain bridge

Ce dossier contient le pont local PC <-> ComputerCraft pour la branche de brouillon terrain.

## Role

- servir une release locale publiee dans `tools/terrain_bridge/data/publish`
- exposer une commande par computer dans `tools/terrain_bridge/data/commands`
- recevoir les resultats dans `tools/terrain_bridge/data/results`
- recevoir les rapports dans `tools/terrain_bridge/data/reports`

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

## Boucle attendue

1. publier la release locale ;
2. ecrire une commande `sync_and_test` ;
3. le daemon terrain ComputerCraft telecharge la MAJ ;
4. le daemon lance les suites terrain ;
5. les rapports JSON remontent dans `data/reports`.
