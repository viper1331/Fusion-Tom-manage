# PLANS.md

## Objet

Ce document cadre les prochaines itérations Codex sur le dépôt :

`https://github.com/viper1331/Fusion-Tom-manage.git`

Il complète `AGENTS.md` et fixe un plan d’exécution priorisé à partir de l’état intermédiaire actuel du projet.

Version de référence observée :
- `fusion.version` = `1.2.29`
- point d’entrée standard = `start.lua`
- shim legacy encore présent = `start_menu_pages_live_v7.lua`

---

## État intermédiaire du projet

### Ce qui est déjà considéré comme solide
- architecture modulaire en place :
  - `core/app`
  - `core/runtime`
  - `core/update`
  - `ui/animations`
  - `ui/components`
  - `ui/helpers`
  - `ui/pages`
  - `tools`
- point d’entrée propre `start.lua`
- compatibilité legacy via `start_menu_pages_live_v7.lua`
- mode secours `rescue_update.lua` intégré
- workflow MAJ déjà mature :
  - manifest lu sur branche
  - fichiers téléchargés sur commit figé
  - staging / apply / rollback
  - rescue mode documenté

### Ce qui reste prioritaire
Le chantier principal restant est désormais OVERVIEW, et plus précisément :
1. finalisation des callouts / annotations terrain ;
2. finition visuelle de la scène réacteur + lasers ;
3. validation terrain tm_gpu ;
4. puis seulement nettoyage structurel résiduel.

---

## Priorités absolues

### P1 — OVERVIEW doit être finalisé avant tout autre chantier
Tant que OVERVIEW n’est pas visuellement validé sur machine réelle :
- ne pas relancer de refonte large ;
- ne pas ouvrir un nouveau grand chantier structurel ;
- ne pas toucher au moteur MAJ sauf bug bloquant.

### P2 — Préserver l’existant
Toujours préserver :
1. stabilité runtime ;
2. compatibilité terrain ;
3. moteur MAJ ;
4. `start.lua` ;
5. responsive ;
6. modularité actuelle.

### P3 — Toute itération doit être petite et traçable
Chaque itération doit :
- attaquer un objectif visuel ou technique bien circonscrit ;
- finir par un commit fonctionnel clair ;
- puis un commit de release / manifest si nécessaire ;
- se terminer par push sur `origin/main`.

---

## Plan d’exécution recommandé

## Phase 1 — Finalisation OVERVIEW (priorité maximale)

### Objectif
Obtenir une page OVERVIEW visuellement conforme à la référence utilisateur, lisible, stable, et exploitable sur tm_gpu.

### Sous-phase 1A — Callouts complets
Attendu :
- `T° CASE <valeur>` visible
- `T° CORE <valeur>` visible
- `TRITIUM OUVERT/FERMÉ`
- `DT-FUEL OUVERT/FERMÉ`
- `DEUTERIUM OUVERT/FERMÉ`

Un callout n’est validé que si les 3 éléments sont présents :
1. texte lisible,
2. ligne segmentée complète,
3. cible claire sur la bonne zone.

#### Contraintes de rendu
- la capture annotée utilisateur doit être traitée comme blueprint de placement
- les lignes de liaison doivent être réellement visibles
- style attendu : callouts techniques segmentés, propres, fins, avec cassure nette
- pas de mini segments livrés comme version terminée

#### Source terrain
- `T° CASE` : vraie température case runtime
- `T° CORE` : vraie température cœur/plasma runtime
- états flux : vraie donnée terrain si disponible
- sinon règle d’inférence explicitée noir sur blanc dans le compte rendu

#### Ordre strict des flux bas
- gauche = tritium = vert
- centre = DT-Fuel = violet
- droite = deuterium = rouge

### Sous-phase 1B — Calibration de scène
Attendu :
- la pile laser et le réacteur doivent être correctement alignés
- l’espace entre pile laser et réacteur doit être visuellement cohérent
- les animations doivent être propres sans surcharger la scène
- OVERVIEW doit donner la priorité à la scène réacteur + lasers

### Sous-phase 1C — Responsive OVERVIEW
Attendu :
- grand écran : rendu complet
- compact : labels raccourcis mais complets
- micro : version minimale mais encore lisible
- aucun débordement hors viewport
- aucune collision avec badges ou panneaux

### Critères de validation Phase 1
La phase 1 n’est validée que si :
- les callouts sont visibles avec texte + ligne + cible ;
- les températures sont réellement affichées ;
- les 3 flux sont distincts et lisibles ;
- le style est fidèle à la capture annotée ;
- aucun crash GPU n’apparaît sur clic ou resize.

---

## Phase 2 — Validation terrain tm_gpu

### Objectif
Valider le rendu réel en conditions de jeu.

### Tests à faire
- grand écran
- compact
- micro
- resize successifs
- clic / touch écran
- états runtime :
  - offline
  - formed
  - ignited
  - running
  - warning
  - scram

### À surveiller
- clipping texte
- clipping callouts
- débordements GPU
- VRAM
- lisibilité des labels
- densité des animations
- cohérence des valeurs CASE / CORE / flux

### Critères de validation Phase 2
- pas de crash
- pas de `assets missing` inattendu
- pas de `Out of boundary`
- pas de perte de scène après resize
- callouts lisibles sur les tailles ciblées

---

## Phase 3 — Nettoyage structurel résiduel

### Objectif
Réduire la dette restante une fois OVERVIEW validé.

### Travaux possibles
- alléger encore `start_menu_pages_live_v7_impl.lua`
- centraliser davantage les constantes de calibration OVERVIEW
- ajouter si utile un helper dédié pour callouts
- documenter les règles de placement / calibration dans le code
- compléter la doc opérateur/dev si nécessaire

### Règle
Cette phase ne commence qu’après validation visuelle terrain de la phase 1.

---

## Phase 4 — Outillage de validation (optionnel après stabilisation)

### Objectif
Mieux verrouiller les releases.

### Pistes
- compléter `validate_distribution.ps1`
- ajouter un petit check des assets critiques
- vérifier la présence des modules OVERVIEW nécessaires
- ajouter une validation de cohérence des callouts/configs si utile

---

## Ce qu’il ne faut pas faire maintenant

Tant que OVERVIEW n’est pas validé :
- ne pas refaire une grosse refonte UI ;
- ne pas rouvrir un chantier massif sur le moteur MAJ ;
- ne pas relancer une réorganisation profonde du runtime ;
- ne pas multiplier les améliorations cosmétiques non liées à la capture utilisateur ;
- ne pas déplacer l’objectif vers autre chose que la finition visuelle terrain.

---

## Mode opératoire Codex par itération

À chaque itération :

1. vérifier :
   - branche courante
   - `git status`
   - remote
2. `git pull --ff-only origin main`
3. lire :
   - `AGENTS.md`
   - `PLANS.md`
   - les fichiers de la zone touchée
4. définir un mini-plan
5. coder une itération ciblée
6. vérifier :
   - cohérence Lua
   - impact responsive
   - impact distribution/manifest/version
7. incrémenter `fusion.version` si modification réelle
8. régénérer `fusion.manifest.json`
9. commit + push

---

## Définition de done pour la phase actuelle

La phase actuelle est considérée terminée uniquement si :
- OVERVIEW est fidèle à la capture annotée ;
- les callouts sont complets ;
- les 3 flux sont correctement ordonnés et libellés ;
- `T° CASE` et `T° CORE` sont visibles avec vraies valeurs ;
- le rendu tm_gpu reste stable après clic/resize ;
- aucune régression n’est introduite sur MAJ / start.lua / rescue mode.

---

## Résumé ultra court pour Codex

### Maintenant
Finir OVERVIEW.

### Ensuite
Valider tm_gpu terrain.

### Enfin
Nettoyer le résiduel structurel.

### Pas avant
Ne pas rouvrir de gros chantier hors OVERVIEW.
