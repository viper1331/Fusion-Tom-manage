# Terrain bridge

Ce dossier contient le pont local PC <-> ComputerCraft pour la branche de brouillon terrain.

## Rôle

- servir une release locale publiée dans `tools/terrain_bridge/data/publish`
- exposer une commande par computer dans `tools/terrain_bridge/data/commands`
- recevoir les résultats dans `tools/terrain_bridge/data/results`
- recevoir les rapports dans `tools/terrain_bridge/data/reports`

## Démarrage

```powershell
./tools/start_terrain_bridge.ps1
```

## Publication locale

```powershell
./tools/publish_local_release.ps1
```

## Écriture d'une commande

```powershell
./tools/write_command.ps1 -Command sync_and_test -Computer fusion_terrain_01
```

## Boucle attendue

1. publier la release locale ;
2. écrire une commande `sync_and_test` ;
3. le daemon terrain ComputerCraft télécharge la MAJ ;
4. le daemon lance les suites terrain ;
5. les rapports JSON remontent dans `data/reports`.
