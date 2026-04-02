# PLANS.md

## Objet

Ce document fixe le plan de travail immédiat pour Codex sur le dépôt :

`https://github.com/viper1331/Fusion-Tom-manage.git`

Il complète `AGENTS.md` et remplace les priorités précédentes par un plan recentré sur les constats terrain les plus récents.

---

## État intermédiaire retenu

### Ce qui est déjà considéré comme solide
- architecture modulaire en place (`core`, `ui`, `tools`, `assets`)
- point d’entrée standard `start.lua`
- workflow MAJ manifest-driven déjà opérationnel
- mode secours `rescue_update.lua` présent
- logs runtime exploitables désormais disponibles

### Ce qui reste prioritaire
Le chantier principal n’est plus le socle technique.
Le chantier principal est maintenant la fidélité terrain du rendu OVERVIEW.

Les derniers constats montrent trois verrous majeurs :
1. le loader sélectionne parfois correctement une scène `pair`, mais le layout compact la dégrade encore en `reactor-only`
2. des reloads d’assets sont encore tentés avec des tailles écran invalides (`0x0`)
3. les animations et annotations ne sont pas encore totalement branchées sur l’état terrain réel

---

## Priorités absolues

### P1 — Corriger les conditions invalides avant tout
Tant qu’un écran `0x0` ou un viewport absurde peut déclencher un reload :
- ne pas considérer OVERVIEW comme stabilisé
- ne pas lancer d’autre gros chantier visuel

### P2 — La scène `pair` doit être réellement respectée
Si le loader a sélectionné une scène `pair` exploitable :
- le layout ne doit pas la dégrader inutilement en `reactor-only`
- sauf impossibilité réelle de viewport clairement justifiée

### P3 — Les animations doivent refléter le terrain réel
Les animations ne doivent plus être principalement décoratives.
Elles doivent être pilotées par des états runtime cohérents et documentés.

---

## Plan d’exécution recommandé

# Phase 1 — Stabilisation du layout OVERVIEW

## Objectif
Supprimer les incohérences entre :
- scène sélectionnée par le loader
- scène effectivement rendue par OVERVIEW

## Sous-phase 1A — Garde-fou taille écran invalide
### À faire
- interdire tout reload asset si la taille détectée est invalide (`0x0`, viewport trop petit, dimensions absurdes)
- conserver l’état visuel précédent si disponible
- logger explicitement :
  - taille rejetée
  - raison du rejet
  - conservation éventuelle de la scène précédente

### Critère de validation
- plus aucun cycle de chargement ne doit partir sur un viewport artificiel de type `8x8`
- plus de faux `assets missing` causés par un état écran transitoire

## Sous-phase 1B — Cohérence loader -> layout
### À faire
- si le loader sélectionne `sceneMode=pair`, le layout doit essayer sérieusement de le rendre
- ne passer en `reactor-only` qu’après échec réel, documenté, du layout pair
- journaliser la raison exacte du fallback layout :
  - overflow réel
  - collision non résolue
  - contrainte micro écran
  - autre raison explicite

### Critère de validation
- plus de cas ambigus du type :
  - `sceneMode=pair` en entrée
  - `layoutLaser=no`
  - `sceneMode=reactor-only` en sortie
sans raison claire et justifiée

## Sous-phase 1C — Compact / micro
### À faire
- définir une stratégie claire :
  - grand écran = pair complet
  - compact = pair réduit si possible
  - micro = pair simplifié si possible, sinon fallback justifié
- documenter les règles de dégradation

### Critère de validation
- le mode compact ne doit plus abandonner trop tôt la pile laser
- les offsets et espacements doivent rester cohérents

---

# Phase 2 — Brancher les animations sur le terrain réel

## Objectif
Faire en sorte que le rendu animé reflète les états runtime réels.

## Sous-phase 2A — Cœur réacteur
### Attendu
Le cœur doit être animé uniquement quand l’état terrain le justifie.

### Règle recommandée
- cœur OFF si le réacteur n’est pas formé ou pas ignité
- cœur ON si `formed=true` et `ignited=true`
- modulation d’intensité possible selon :
  - `plasmaMK`
  - `status`
  - `alerts`

### À documenter
- la règle exacte retenue
- les champs runtime utilisés

## Sous-phase 2B — Flux gaz
### Attendu
Chaque flux bas doit être animé uniquement s’il est réellement `open`.

### Ordre strict
- gauche = tritium = vert
- centre = DT-Fuel = violet
- droite = deuterium = rouge

### Source de vérité
- utiliser une vraie donnée terrain si disponible
- sinon documenter la règle d’inférence exacte

### Critère de validation
- un flux `closed` ne doit plus paraître actif visuellement
- un flux `open` doit être animé clairement

## Sous-phase 2C — Flux électriques
### Attendu
Les flux électriques doivent être actifs seulement si la charge terrain le justifie.

### Source de vérité recommandée
- charge induction
- état laser
- `laserReady`
- `energyPct`
- ou autre état métier plus pertinent s’il existe déjà

### Critère de validation
- pas de flux électrique permanent décoratif
- animation plus forte quand la charge réelle existe
- animation faible ou absente sinon

---

# Phase 3 — Normalisation des annotations OVERVIEW

## Objectif
Rendre les annotations lisibles, justes et cohérentes avec les données affichées.

## Sous-phase 3A — T° CASE / T° CORE
### À faire
- vérifier que les unités affichées sont correctes
- éviter l’affichage de valeurs brutes incohérentes
- si nécessaire, normaliser / formatter avant affichage
- conserver les callouts existants

### Critère de validation
- labels lisibles
- unités cohérentes
- pas de doute sur ce que représente la valeur

## Sous-phase 3B — Flux ouverts / fermés
### À faire
- afficher clairement l’état de chaque ligne
- documenter la règle terrain ou d’inférence
- conserver l’ordre strict des trois flux

### Critère de validation
- lecture immédiate :
  - quel gaz
  - quel état
  - quelle couleur

---

# Phase 4 — Validation terrain

## Objectif
Valider le comportement réel tm_gpu après correction.

## Tests à faire
- écran grand
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

## À surveiller
- plus de `0x0` destructeur
- plus de fallback incohérent `pair -> reactor-only`
- cohérence des animations avec le réel terrain
- cohérence CASE / CORE / flux
- absence de crash GPU / texte / clamp

---

# Phase 5 — Nettoyage résiduel

## Objectif
Nettoyer le code une fois les phases précédentes validées.

## Travaux possibles
- centraliser davantage les règles de layout OVERVIEW
- centraliser les règles d’animation terrain
- commenter les règles d’inférence des flux
- alléger encore l’implémentation centrale si nécessaire

## Règle
Pas de nettoyage structurel lourd tant que les phases 1 à 4 ne sont pas validées.

---

## Ce qu’il ne faut pas faire maintenant

Tant que les phases 1 à 4 ne sont pas validées :
- ne pas rouvrir un gros chantier moteur MAJ
- ne pas refaire une refonte générale UI
- ne pas disperser le travail sur plusieurs zones non liées
- ne pas ajouter de nouvelles features non demandées
- ne pas traiter les animations comme pure décoration

---

## Mode opératoire Codex par itération

À chaque itération :
1. vérifier la branche courante
2. vérifier `git status`
3. vérifier le remote
4. faire `git pull --ff-only origin main`
5. lire `AGENTS.md`
6. lire `PLANS.md`
7. définir un mini-plan court
8. modifier uniquement la zone ciblée
9. vérifier impact runtime / responsive / distribution
10. incrémenter `fusion.version` si modification réelle
11. régénérer `fusion.manifest.json`
12. commit + push

---

## Définition de done pour la phase actuelle

La phase actuelle est considérée terminée uniquement si :
- aucun reload asset n’est tenté sur taille écran invalide
- la scène `pair` reste affichée quand elle est réellement possible
- le cœur ne s’anime que si le réacteur tourne réellement
- les flux gaz ne s’animent que s’ils sont réellement ouverts
- les flux électriques reflètent la charge réelle induction / laser
- `T° CASE` et `T° CORE` sont lisibles et correctement normalisés
- aucune régression n’est introduite sur MAJ / start.lua / rescue mode

---

## Résumé ultra court pour Codex

### Maintenant
1. Bloquer les reloads écran invalides
2. Corriger le fallback abusif `pair -> reactor-only`
3. Brancher les animations sur le terrain réel
4. Normaliser les annotations

### Ensuite
Valider tm_gpu terrain

### Enfin
Nettoyer le résiduel structurel
