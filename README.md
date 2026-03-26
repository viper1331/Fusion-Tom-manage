# Fusion-Tom-manage

Interface de gestion de reacteur a fusion Mekanism pour CC:Tweaked + Tom's Peripherals.

## Lancement

1. Configurer avec `lua install.lua`
2. Lancer l'interface avec `lua start_menu_pages_live_v7.lua`

## Mise a jour integree (page MAJ)

- `CHECK` : verifie le manifest distant
- `DOWNLOAD` : telecharge les fichiers dans `update_tmp`
- `APPLY` : backup puis application
- `ROLLBACK` : restauration depuis `backup_last`
- `RESTART` : relance propre du programme
