# Fusion-Tom-manage

Interface de gestion de reacteur a fusion Mekanism pour CC:Tweaked + Tom's Peripherals.

## Lancement

1. Configurer avec `lua install.lua`
2. Lancer l'interface avec `lua start.lua`

Compatibilite legacy:
- `lua start_menu_pages_live_v7.lua` reste supporte temporairement (shim vers `start.lua`).

## Agent terrain (branche brouillon)

La couche terrain auto-orchestree est optionnelle et se pilote via `fusion_config.lua`:

```lua
terrainAgent = {
  enabled = false,
  collectorBaseUrl = "http://127.0.0.1:8765",
  pollSeconds = 5,
  runtimeMode = "runtime_gated",
  computerName = "fusion_terrain_01",
  testComputerName = "fusion_terrain_01",
  primaryComputerName = "fusion_terrain_02",
  autoStart = true,
}
```

Comportement startup:
- `startup.lua` lance `terrain/boot.lua` uniquement si `terrainAgent.enabled=true` et `terrainAgent.autoStart=true`.
- si desactive, aucun daemon terrain n'est impose.

Boucle terrain attendue:
1. `powershell -ExecutionPolicy Bypass -File tools/start_terrain_bridge.ps1`
2. `powershell -ExecutionPolicy Bypass -File tools/publish_local_release.ps1`
3. `powershell -ExecutionPolicy Bypass -File tools/write_command.ps1 -Command sync_and_test`
4. le daemon terrain recupere la commande, synchronise la MAJ et publie resultats/rapports.
5. (optionnel) verifier le bridge local avec `powershell -ExecutionPolicy Bypass -File tools/test_terrain_bridge.ps1`.

Note: `tools/write_command.ps1` resolve automatiquement le `computerName` depuis `fusion_config.lua` si l'argument `-Computer` est omis.

Workflow post-main double-cible (test + principal):
1. publication depuis `main` (`tools/publish_local_release.ps1`);
2. verifier les labels config (`fusion_terrain_01` / `fusion_terrain_02`);
3. lancer `tools/deploy_post_main_dual_target.ps1 -TestComputer fusion_terrain_01 -PrimaryComputer fusion_terrain_02`;
4. le script purge les commandes residuelles, envoie les 2 commandes, suit les 2 IDs et echoue si un `result`/`report` manque.

## Mode secours (`rescue_update.lua`)

`rescue_update.lua` est un outil officiel de recuperation si l'UI principale ne demarre plus ou si la page MAJ est indisponible.

- Lancez-le avec `lua rescue_update.lua`
- Il telecharge le manifest depuis la branche configuree, puis telecharge les fichiers sur le commit epingle du manifest
- Il applique la mise a jour depuis un staging temporaire et garde une sauvegarde locale avant remplacement

Elements preserves localement pendant un rescue apply:
- `fusion_config.lua`
- `rescue_update.lua`

Chemins utilises par le mode secours:
- log: `/rescue_update.log`
- backup: `/backup_rescue`
- staging: `/.rescue_staging`

## Mise a jour integree (page MAJ)

- `CHECK` : verifie le manifest distant
- `DOWNLOAD` : telecharge les fichiers dans `update_tmp` + valide taille/hash runtime (SHA-256)
- `APPLY` : backup puis application, uniquement si staging valide (taille/hash/commit)
- `ROLLBACK` : restauration depuis `backup_last`
- `RESTART` : relance propre du programme

## Logs structures

Le projet utilise une couche commune `core/logging/logger.lua` avec format homogene:

`[YYYY-MM-DD HH:MM:SS] [LEVEL] [CATEGORY] message | k=v ...`

Sorties par defaut:
- runtime UI: `ui_runtime.log`
- update: `update.log`
- rescue: `/rescue_update.log`

Niveaux disponibles dans `fusion_config.lua`:
- `DEBUG`
- `INFO` (defaut)
- `WARN`
- `ERROR`

Categories couvertes:
- `BOOT`, `ROUTER`, `LOOP`, `INPUT`
- `TELEMETRY`, `ACTIONS`
- `OVERVIEW`, `ASSETS`, `ANIMATIONS`, `GPU`
- `UPDATE`, `RESCUE`

Options de config:
- `logging.telemetrySnapshotSeconds` pour la periodicite des snapshots telemetrie
- `logging.loopEventDebug` pour activer le debug event loop

## Publication manifest

- Le manifest distant est lu sur la branche configuree.
- Les fichiers d'update sont telecharges depuis le `commit` fige declare dans le manifest.
- Script de generation recommande : `powershell -ExecutionPolicy Bypass -File tools/generate_manifest.ps1`
- Script release recommande : `powershell -ExecutionPolicy Bypass -File tools/release_prepare.ps1`
- Regenerer le manifest avant chaque push de release pour synchroniser `size/hash/hashAlgo/commit`.
- La liste `files` doit contenir uniquement les fichiers necessaires au runtime distribue.
- Les chemins avec espaces sont supportes (encodage URL), mais a eviter pour les assets non essentiels.

## Workflow release standard

1. Mettre a jour le code.
2. Incrementer `fusion.version`.
3. Lancer `powershell -ExecutionPolicy Bypass -File tools/release_prepare.ps1`.
4. Creer un commit fonctionnel (code/outillage/version).
5. Creer un commit de release pour la synchro finale du manifest (pin commit/hash/size).
6. Push sur la branche de travail (puis integration vers `main` seulement apres validation terrain reelle).
