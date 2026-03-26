# Fusion-Tom-manage

Interface de gestion de reacteur a fusion Mekanism pour CC:Tweaked + Tom's Peripherals.

## Lancement

1. Configurer avec `lua install.lua`
2. Lancer l'interface avec `lua start.lua`

Compatibilite legacy:
- `lua start_menu_pages_live_v7.lua` reste supporte temporairement (shim vers `start.lua`).

## Mise a jour integree (page MAJ)

- `CHECK` : verifie le manifest distant
- `DOWNLOAD` : telecharge les fichiers dans `update_tmp` + valide taille/hash runtime (SHA-256)
- `APPLY` : backup puis application, uniquement si staging valide (taille/hash/commit)
- `ROLLBACK` : restauration depuis `backup_last`
- `RESTART` : relance propre du programme

## Publication manifest

- Le manifest distant est lu sur la branche configuree.
- Les fichiers d'update sont telecharges depuis le `commit` fige declare dans le manifest.
- Script de generation recommande : `powershell -ExecutionPolicy Bypass -File tools/generate_manifest.ps1`
- Regenerer le manifest avant chaque push de release pour synchroniser `size/hash/hashAlgo/commit`.
- La liste `files` doit contenir uniquement les fichiers necessaires au runtime distribue.
- Les chemins avec espaces sont supportes (encodage URL), mais a eviter pour les assets non essentiels.
