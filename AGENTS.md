# AGENTS.md

## Objet

Ce dépôt pilote une interface de gestion de **réacteur à fusion Mekanism** pour **CC:Tweaked**, avec prise en charge prioritaire de **Tom's Peripherals** (`tm_gpu`) et compatibilité avec des écrans de tailles variées.

L'objectif n'est pas seulement de « faire marcher » l'affichage, mais de livrer un système :
- fiable sur le terrain ;
- lisible sur plusieurs tailles d'écran ;
- modulaire ;
- testable ;
- extensible sans casser les comportements déjà validés ;
- maintenable sur la durée.

---

## Dépôt de référence obligatoire

Le dépôt de travail à utiliser est :

`https://github.com/viper1331/Fusion-Tom-manage.git`

Toute itération Codex/agent doit se faire **à partir de ce dépôt** et doit se terminer par une **synchronisation Git complète**, sauf impossibilité technique clairement signalée.

---

## Règle branche brouillon terrain

Pour la phase d'intégration terrain auto-orchestrée, la branche de travail obligatoire est `codex/terrain-auto-orchestration`.

Règle de promotion obligatoire:
1. intégration et correctifs sur la branche brouillon ;
2. validation terrain réelle (NeoForge/ComputerCraft) avec rapports exploitables ;
3. seulement après validation terrain OK, promotion vers `main`.

Interdiction explicite:
- ne jamais développer directement sur `main` tant que la validation terrain brouillon n'est pas validée ;
- ne jamais considérer `main` comme prête tant que la preuve terrain n'est pas disponible.

---

## Workflow terrain réel à deux computers (obligatoire)

Le workflow terrain réel repose sur deux cibles distinctes:
- un **computer de test** ;
- un **computer principal**.

Les deux rôles sont obligatoires et non interchangeables pour la validation finale.

### 1. Validation terrain brouillon (computer de test)
Toute itération de code doit suivre cette boucle:
1. code sur `codex/terrain-auto-orchestration` ;
2. commit/push de la branche brouillon ;
3. publication locale de release ;
4. commande `sync_and_test` vers le computer de test ;
5. lecture de `results` et `reports` ;
6. correction et nouvelle boucle si échec.

Sans validation terrain du computer de test, la promotion vers `main` est interdite.

### 2. Promotion vers main
La promotion vers `main` est autorisée uniquement si:
- la validation terrain du computer de test est OK ;
- les rapports sont exploitables ;
- aucune régression bloquante n'est ouverte.

La promotion vers `main` ne doit jamais être basée uniquement sur:
- un test local ;
- un test statique ;
- une intuition de comportement.

### 3. Déploiement post-main obligatoire
Après promotion vers `main`, Codex doit déclencher le déploiement terrain sur:
1. le computer de test ;
2. le computer principal.

Le déploiement post-main doit inclure:
- sync/update ;
- exécution des suites terrain ;
- remontée d'un statut et d'un report pour chaque computer.

### 4. Critère de fin d'opération
Une opération n'est terminée que si:
1. le brouillon est validé sur le computer de test ;
2. `main` est mise à jour ;
3. le computer de test et le computer principal sont alignés sur la version issue de `main` ;
4. les deux computers ont renvoyé un retour exploitable (`results` et `reports`).

---

## Périmètre technique du projet

Le projet concerne principalement :
- **CC:Tweaked**
- **Tom's Peripherals**
- **Mekanism Fusion Reactor**
- périphériques terrain réels : moniteurs, `tm_gpu`, modems, block readers, relays, logic adapters, induction ports, laser amplifiers
- logique UI responsive
- installateur et configuration
- télémétrie, actions, rendu, animations et update system éventuel.

L'agent doit toujours raisonner en priorité pour cet environnement réel, et non pour un environnement théorique ou purement local.

---

## Règle de priorité absolue

Lors d'une itération, l'agent doit toujours préserver en priorité :
1. la **stabilité du programme** ;
2. la **compatibilité terrain** ;
3. la **lisibilité de l'UI** ;
4. la **modularité du code** ;
5. les **fonctionnalités déjà validées** ;
6. la **cohérence installation / configuration / versioning**.

Ne jamais sacrifier un comportement déjà validé pour un embellissement visuel non demandé.

---

## Source de vérité

Pour ce projet, la source de vérité doit être appliquée dans cet ordre :
1. **les fichiers locaux présents dans le dépôt cloné** ;
2. **les fichiers explicitement envoyés dans la conversation** ;
3. **les rapports terrain réels** ;
4. **l'état réel décrit par l'utilisateur** ;
5. le dépôt GitHub comme base de synchronisation obligatoire.

Si plusieurs sources divergent :
- le signaler explicitement ;
- ne pas écraser silencieusement l'une au profit de l'autre ;
- expliquer laquelle est retenue pour l'itération et pourquoi.

---

## Workflow Git obligatoire pour chaque itération

### 1. Démarrage obligatoire
Avant toute modification :
- vérifier la branche courante ;
- vérifier `git status` ;
- vérifier le remote configuré ;
- faire un **pull du dépôt distant obligatoire** ;
- confirmer dans le compte rendu quel dépôt distant a été utilisé ;
- vérifier si le dépôt local contient des changements non commités.

### 2. Sécurité Git
Si des changements locaux existent :
- ne jamais les écraser silencieusement ;
- les signaler explicitement ;
- appliquer la stratégie la plus sûre :
  - commit préalable,
  - stash,
  - ou arrêt motivé.

### 3. Lecture projet obligatoire
Avant de modifier le code, lire systématiquement :
- `AGENTS.md`
- `PLANS.md` s'il existe
- les fichiers concernés par l'itération
- tout manifeste / version / installateur si l'itération peut les impacter.

### 4. Plan court avant action
Avant de coder, établir un mini-plan concret :
- ce qui sera lu ;
- ce qui sera modifié ;
- ce qui sera vérifié ;
- ce qui restera volontairement inchangé ;
- comment la validation sera faite.

### 5. Fin d'itération obligatoire
En fin d'itération :
- vérifier l'absence d'erreur évidente ;
- résumer les changements ;
- lister les fichiers modifiés ;
- mettre à jour la version si requis ;
- synchroniser les fichiers de version liés ;
- **committer puis push sur le dépôt obligatoire**.

Le `push` est **obligatoire** sauf impossibilité technique clairement indiquée.

---

## Workflow obligatoire de validation

### Principe général
Pour ce projet, une validation n'est complète que si l'agent distingue clairement :
- ce qui a été vérifié **localement** ;
- ce qui a été validé **structurellement** ;
- ce qui a été validé **sur le terrain réel**.

### Vérifications minimales obligatoires
Toujours vérifier au minimum :
- absence d'erreur Lua évidente dans le code modifié ;
- cohérence des appels entre modules ;
- cohérence des imports / requires ;
- navigation entre pages si touchée ;
- fallback compact / micro écran si touché ;
- chargement des assets si touché ;
- compatibilité avec `fusion_config.lua` et `install.lua` si concernés ;
- cohérence du versioning si touché ;
- cohérence du manifeste / système de mise à jour si touché.

Quand un test réel n'a pas pu être exécuté, le dire clairement.

### Règle spécifique
Pour ce projet :
- **ne pas imposer CraftOS-PC comme étape obligatoire** ;
- ne pas bloquer une itération faute de test CraftOS ;
- privilégier la vérification statique, la cohérence Lua, la compatibilité structurelle et la cohérence du rendu si aucun test réel n'est disponible.

---

## Workflow obligatoire de validation terrain NeoForge / ComputerCraft / MCP

### Principe
Les tests terrain réels se font dans l'environnement Minecraft moddé **NeoForge** via **CC:Tweaked / ComputerCraft** et non via un faux client réseau standard.

### Interdiction de principe
Sauf demande explicite de l'utilisateur, l'agent ne doit pas considérer **Mineflayer** comme méthode principale de validation terrain pour ce dépôt.

Mineflayer peut éventuellement servir à des explorations séparées ou à des prototypes hors environnement réel, mais ne doit pas être présenté comme la méthode de validation terrain de référence pour ce projet.

### Source de vérité terrain pour les tests
Quand une validation terrain est nécessaire, la source de vérité prioritaire doit être :
1. les rapports issus du harness **ComputerCraft** exécuté dans le monde réel ;
2. les retours d'exécution réellement observés en environnement NeoForge ;
3. ensuite seulement les vérifications locales ou statiques.

### Règle de lecture avant correction
Si une itération touche à l'un des points suivants :
- détection de périphériques ;
- moniteurs ;
- `tm_gpu` ;
- rendu Tom's Peripherals ;
- bootstrap ;
- installation terrain ;
- télémétrie réelle ;
- actions relay / block reader / laser / induction ;
- comportement responsive réellement observé sur écran terrain ;
- setup matériel ;
- diagnostics d'environnement réel ;

alors l'agent doit, si disponible :
- lire le dernier rapport terrain MCP ;
- s'appuyer dessus avant de conclure ;
- signaler explicitement si aucun rapport terrain récent n'est disponible.

### Règle de validation après correction
Après un correctif touchant au terrain, l'agent doit :
- demander ou exploiter une nouvelle validation terrain ;
- distinguer clairement ce qui a été validé localement de ce qui a été validé en monde réel ;
- ne jamais présenter une hypothèse locale comme une validation terrain effective.

### Ordre obligatoire de validation
L'ordre de validation attendu est :
1. lecture de `AGENTS.md` et des fichiers concernés ;
2. analyse locale du code ;
3. lecture du dernier rapport terrain si disponible ;
4. correctif ;
5. vérification locale minimale ;
6. nouvelle validation terrain si le périmètre le justifie ;
7. conclusion claire sur le niveau réel de validation atteint.

### Règle de priorité en cas de divergence
En cas de divergence entre :
- test local ;
- simulation ;
- hypothèse statique ;
- et retour terrain réel,

le **retour terrain réel** doit être considéré comme prioritaire.

### Compte rendu obligatoire sur la validation
Le compte rendu de l'agent doit préciser explicitement :
- ce qui a été validé localement ;
- ce qui a été validé via rapport terrain ;
- ce qui reste non validé en environnement réel ;
- si la conclusion repose sur une preuve terrain ou sur une hypothèse.

### Règle promotion et déploiement terrain
La validation terrain doit être distinguée en 3 étapes obligatoires:
1. validation terrain de la branche brouillon sur le computer de test ;
2. promotion vers `main` uniquement après preuve terrain du computer de test ;
3. déploiement post-main sur computer de test puis computer principal avec statuts/reports exploitables.

Une itération ne peut pas être considérée comme terminée si l'une de ces étapes manque.

---

## Règle absolue anti-monolithe

### Principe directeur
Le programme doit rester **strictement modulaire**.

Toute nouvelle fonctionnalité, correction, instrumentation ou amélioration doit être ajoutée :
- soit dans un module déjà cohérent ;
- soit dans un nouveau module dédié ;
- mais **jamais** en recréant un gros bloc central fourre-tout si une extraction logique est possible.

### Interdiction explicite
Il est interdit de :
- profiter d'une itération pour recoller de la logique dans un gros fichier central par facilité ;
- ajouter des blocs massifs inline dans `start_menu_pages_live_v7_impl.lua` ou tout équivalent ;
- fusionner dans un même fichier plusieurs responsabilités distinctes ;
- traiter un fichier d'implémentation central comme une zone tampon permanente.

### Règle obligatoire de décision
Avant toute modification, l'agent doit se demander :
1. cette logique appartient-elle déjà à un module existant ?
2. faut-il créer un helper dédié ?
3. faut-il créer un module dédié ?
4. l'ajout dans le fichier central est-il réellement inévitable ?

Si l'extraction est raisonnablement possible, **elle est obligatoire**.

### Fichiers sensibles
Les fichiers suivants sont considérés comme sensibles au risque de remonolithisation :
- `start_menu_pages_live_v7_impl.lua`
- tout routeur central
- toute boucle principale
- tout renderer global
- tout fichier `app.lua` ou `main.lua` servant d'assemblage
- tout module de bootstrap.

Si une itération touche à un de ces fichiers, l'agent doit :
- justifier pourquoi la modification doit y rester ;
- limiter le changement à du câblage léger ou à un wrapper ;
- préférer un appel vers un module extrait ;
- expliquer dans le compte rendu pourquoi la modularisation a été préservée.

---

## Règles de modularisation

### Programme strictement modulaire
Séparer autant que possible :
- lecture télémétrie ;
- configuration ;
- logique d'actions ;
- layout responsive ;
- rendu graphique ;
- animation ;
- pages UI ;
- installateur ;
- logging ;
- helpers GPU safe ;
- helpers de clamp ;
- helpers de formatage ;
- annotations / callouts ;
- moteur de mise à jour ;
- collecte / interprétation de rapports terrain.

### Architecture cible recommandée
Quand une refonte ou une extraction est demandée, viser une structure proche de :
- `core/` : logique métier et runtime ;
- `core/app/` : bootstrap, router, loop ;
- `core/runtime/` : télémétrie, actions, états dérivés ;
- `core/update/` : moteur MAJ ;
- `ui/pages/` : rendu des pages ;
- `ui/helpers/` : layout, callouts, GPU safe, formatters ;
- `ui/components/` : navigation et éléments UI réutilisables ;
- `ui/animations/` : cœur, flux électriques, flux gaz ;
- `assets/` : PNG et variantes ;
- `tools/` : génération / validation / release ;
- `install.lua` : assistant d'installation/configuration.

### Répartition obligatoire des responsabilités
- la **télémétrie** va dans `core/runtime/`
- les **actions terrain/UI** vont dans `core/runtime/`
- le **layout** va dans `ui/helpers/` ou `ui/pages/`
- les **animations** vont dans `ui/animations/`
- les **callouts / annotations / formatters visuels** vont dans `ui/helpers/` ou `ui/pages/`
- le **bootstrap / routing / loop** va dans `core/app/`
- les **outils release** vont dans `tools/`
- la **logique de mise à jour** va dans `core/update/`
- la **lecture de rapports terrain** va dans un module dédié et non dans le routeur principal.

Le fichier principal doit rester un point d'entrée / d'assemblage, pas redevenir un monolithe.

---

## Règles UI / UX

### Responsive
Toute UI doit être pensée pour plusieurs tailles :
- grand écran ;
- écran compact ;
- micro écran.

### Priorité visuelle en OVERVIEW
Dans la page `OVERVIEW`, le **réacteur** et les **modules laser** doivent toujours rester la priorité visuelle.

Si l'espace manque :
- réduire d'abord les blocs d'information secondaires ;
- simplifier les jauges ;
- compacter les libellés ;
- réduire les modules visibles graphiquement si nécessaire, tout en conservant le **compteur réel**.

### Lisibilité
Toujours privilégier :
- textes lisibles ;
- contrastes suffisants ;
- absence de chevauchements ;
- labels non tronqués si cela peut être évité ;
- hiérarchie visuelle claire.

### Cohérence visuelle
Les animations doivent être :
- positionnées exactement sur les zones concernées ;
- cohérentes avec l'état réel du système ;
- sobres si le réacteur est simplement stable ;
- plus marquées seulement dans les cas de charge, tir laser ou changement d'état.

Ne jamais ajouter une animation arbitraire qui ne correspond pas aux données ou au montage représenté.

### Règle terrain pour les animations
Les animations doivent être pilotées par le réel terrain dès que possible :
- cœur animé seulement si l'état réacteur le justifie réellement ;
- flux gaz animés seulement si la ligne est réellement ouverte ;
- flux électriques animés seulement si la charge induction / laser le justifie.

---

## Règles sur les assets PNG

Tom's Peripherals ne doit pas être supposé redimensionner proprement les PNG à la volée.

Donc :
- prévoir plusieurs variantes d'assets ;
- choisir dynamiquement la meilleure taille ;
- conserver un fond cohérent avec la page ;
- limiter l'espace mort autour des assets.

Pour les assets critiques, prévoir au besoin :
- `micro`
- `tiny`
- `xsmall`
- `small`
- `medium`
- `large`

Si un asset devient critique pour le responsive :
- l'extraction vers des variantes dédiées est préférable à un redimensionnement agressif ;
- l'agent doit limiter les hypothèses sur le comportement de rendu réel de `tm_gpu`.

---

## Configuration et installation

### `fusion_config.lua`
Le programme doit respecter la configuration utilisateur et ne pas l'écraser sans demande explicite.

### `install.lua`
L'installateur doit permettre de configurer au minimum :
- le `tm_gpu` ;
- le modem utilisé ;
- les périphériques principaux ;
- les block readers ;
- les redstone relays ;
- les sides des relays ;
- les paramètres de polling ;
- la durée du pulse laser ;
- la puissance analogique ;
- le **nombre de modules laser** installés sur le terrain ;
- la page de démarrage si prévu.

L'installateur doit rester :
- simple ;
- robuste ;
- compréhensible ;
- cohérent avec les capacités réelles du programme.

### Règle installateur
Si l'itération change la structure de configuration, l'agent doit vérifier si :
- `install.lua` doit être adapté ;
- les valeurs existantes doivent être préservées ;
- une migration douce est nécessaire ;
- la rétrocompatibilité avec une config existante doit être assurée.

---

## Données terrain et périphériques

L'agent doit privilégier les données réellement disponibles sur le terrain.

### Source de télémétrie prioritaire
Utiliser en priorité les périphériques les plus fiables pour chaque type d'information.

En général :
- `fusionReactorLogicAdapter_*` pour l'état réacteur ;
- `inductionPort_*` pour l'énergie globale ;
- `laserAmplifier_*` pour l'état de charge laser ;
- `block_reader_*` pour les réservoirs / états spécifiques ;
- `redstone_relay_*` pour les actions terrain.

### Règle de prudence
Ne jamais inventer une méthode, un nom de périphérique ou une capacité périphérique non confirmée.

### Actions
Ne jamais inventer les faces de relais.
Si une action dépend d'un `side` non confirmé :
- le rendre configurable ;
- ou désactiver proprement l'action jusqu'à confirmation.

### Détection
Quand une détection terrain est possible, elle doit être préférée à une valeur figée.
Le code doit rester permissif quand le setup réel peut varier.

---

## Système de mise à jour / manifeste / release

Si le projet utilise :
- `fusion.version`
- un manifeste
- un système de mise à jour
- un mécanisme d'application / rollback

alors toute itération concernée doit vérifier la cohérence entre :
- le code réel ;
- la version déclarée ;
- le manifeste ;
- l'installateur si nécessaire ;
- les chemins et fichiers réellement livrés.

### Règle release
Ne jamais livrer un changement de comportement sans vérifier si :
- `fusion.version` doit être incrémenté ;
- le manifeste doit être régénéré ;
- l'installateur doit être adapté ;
- la logique de rollback doit être préservée.

---

## Versioning

À chaque itération demandant une modification du projet :
- incrémenter `fusion.version` avec une version strictement supérieure ;
- synchroniser tout fichier de manifeste/version lié ;
- garder `install.lua` cohérent avec l'état réel du programme si ses capacités changent.

Ne jamais modifier la version sans refléter un vrai changement du code ou du comportement.

---

## Règles de documentation et de compte rendu

Après intervention, toujours fournir un résumé clair contenant :
- ce qui a été fait ;
- ce qui a été vérifié ;
- ce qui n'a pas pu être validé ;
- les fichiers modifiés ;
- le statut Git final ;
- le statut du commit/push ;
- les points restants éventuels.

### Obligation supplémentaire
Le résumé doit aussi préciser :
- dans quel module la logique a été ajoutée ;
- pourquoi ce module est le bon emplacement ;
- pourquoi la modification ne remonolithise pas le projet ;
- ce qui repose sur validation locale ;
- ce qui repose sur validation terrain brouillon (computer de test) ;
- si la promotion vers `main` a été faite ou non ;
- si le déploiement post-main sur computer de test et computer principal a été exécuté ;
- ce qui reste à vérifier sur le terrain.

Le résumé doit être utile pour reprendre rapidement l'itération suivante.

### Règle de transparence
L'agent doit toujours :
- signaler clairement ses limites de validation ;
- distinguer fait, déduction et hypothèse ;
- éviter toute formulation qui laisse croire qu'un test réel a eu lieu si ce n'est pas le cas.

---

## Interdictions

L'agent ne doit jamais :
- ignorer le `pull` initial ;
- ignorer le `push` final sans le signaler ;
- écraser silencieusement des changements locaux ;
- supprimer une fonctionnalité validée sans demande explicite ;
- casser la compatibilité petit écran par ajout visuel ;
- durcir le code contre le terrain réel avec des valeurs trop figées si une détection est possible ;
- recréer un monolithe par accumulation de logique dans un fichier central ;
- choisir la solution la plus rapide si elle dégrade la modularité durablement ;
- utiliser un faux client non compatible avec l'environnement NeoForge comme preuve de validation terrain ;
- conclure à une compatibilité terrain sans rapport MCP, test réel ou retour utilisateur explicite ;
- présenter une hypothèse locale comme une preuve terrain ;
- promouvoir vers `main` sans validation terrain préalable du computer de test ;
- considérer `main` comme déployée tant que le computer principal n'est pas synchronisé ;
- oublier de redéployer le computer de test après une promotion vers `main` ;
- committer `tools/terrain_bridge/data/` ;
- modifier silencieusement la structure de configuration sans évaluer l'impact sur `install.lua` et la configuration existante ;
- modifier la version ou le manifeste sans lien réel avec le comportement du programme ;
- contourner l'architecture modulaire existante par facilité ;
- laisser croire qu'un point est validé si aucune preuve locale ou terrain ne l'étaye.
