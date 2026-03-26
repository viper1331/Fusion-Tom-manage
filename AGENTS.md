# AGENTS.md

## Objet
Ce dépôt pilote une interface de gestion de **réacteur à fusion Mekanism** pour **CC:Tweaked**, avec prise en charge prioritaire de **Tom's Peripherals** (`tm_gpu`) et compatibilité avec une UI plus compacte selon la taille de l'écran.

L'objectif n'est pas seulement de « faire marcher » l'affichage, mais de livrer un système :
- fiable sur le terrain ;
- lisible sur plusieurs tailles d'écran ;
- modulaire ;
- testable ;
- extensible sans casser les pages déjà validées.

---

## Dépôt de référence obligatoire
Le dépôt de travail à utiliser est :

`https://github.com/viper1331/Fusion-Tom-manage.git`

Toute itération Codex/agent doit se faire **à partir de ce dépôt** et doit se terminer par une **synchronisation Git complète**, sauf impossibilité technique clairement signalée.

---

## Règle de priorité absolue
Lors d'une itération, l'agent doit toujours préserver en priorité :
1. la **stabilité du programme** ;
2. la **compatibilité terrain** ;
3. la **lisibilité de l'UI** ;
4. la **modularité du code** ;
5. les **fonctionnalités déjà validées**.

Ne jamais sacrifier un comportement déjà validé pour un embellissement visuel non demandé.

---

## Source de vérité
Pour ce projet, la source de vérité doit être appliquée dans cet ordre :
1. **les fichiers locaux présents dans le dépôt cloné** ;
2. **les fichiers explicitement envoyés dans la conversation** ;
3. **l'état réel décrit par l'utilisateur** ;
4. le dépôt GitHub comme base de synchronisation obligatoire.

Si les fichiers locaux et les fichiers envoyés divergent, l'agent doit le signaler explicitement avant modification.

---

## Workflow Git obligatoire pour chaque itération
### 1. Démarrage obligatoire
Avant toute modification :
- vérifier la branche courante ;
- vérifier `git status` ;
- vérifier le remote configuré ;
- faire un **pull du dépôt distant obligatoire** ;
- confirmer dans le compte rendu quel dépôt distant a été utilisé.

### 2. Sécurité Git
Si des changements locaux existent :
- ne jamais les écraser silencieusement ;
- les signaler explicitement ;
- appliquer la stratégie la plus sûre :
  - commit préalable,
  - stash,
  - ou arrêt motivé.

### 3. Lecture projet
Avant de modifier le code, lire systématiquement :
- `AGENTS.md`
- `PLANS.md` s'il existe
- les fichiers concernés par l'itération

### 4. Plan court avant action
Avant de coder, établir un mini-plan concret :
- ce qui sera lu ;
- ce qui sera modifié ;
- ce qui sera vérifié ;
- ce qui restera volontairement inchangé.

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

## Vérifications obligatoires
### Règle spécifique
Pour ce projet :
- **ne pas imposer CraftOS-PC comme étape obligatoire** ;
- ne pas bloquer une itération faute de test CraftOS ;
- privilégier la vérification statique, la cohérence Lua, la compatibilité structurelle et la cohérence du rendu.

### Vérifications minimales
Toujours vérifier au minimum :
- absence d'erreur Lua évidente dans le code modifié ;
- cohérence des appels entre modules ;
- navigation entre pages si touchée ;
- fallback compact / micro écran si touché ;
- chargement des assets si touché ;
- compatibilité avec `fusion_config.lua` et `install.lua` si concernés.

Quand un test réel n'a pas pu être exécuté, le dire clairement.

---

## Règles de modularisation
Le programme doit rester **strictement modulaire**.

Éviter les gros fichiers monolithiques quand une extraction logique est possible.

Séparer autant que possible :
- lecture télémétrie ;
- configuration ;
- logique d'actions ;
- layout responsive ;
- rendu graphique ;
- animation ;
- pages UI ;
- installateur.

### Architecture cible recommandée
Quand une refonte ou une extraction est demandée, viser une structure proche de :
- `core/` : logique métier et runtime ;
- `ui/` : rendu et pages ;
- `ui/toms/` : rendu `tm_gpu` ;
- `assets/` : PNG et variantes ;
- `config/` ou fichier de config runtime ;
- `install.lua` : assistant d'installation/configuration.

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

### Cohérence visuelle
Les animations doivent être :
- positionnées exactement sur les zones concernées ;
- cohérentes avec l'état réel du système ;
- sobres si le réacteur est simplement stable ;
- plus marquées seulement dans les cas de charge, tir laser ou changement d'état.

Ne jamais ajouter une animation arbitraire qui ne correspond pas aux données ou au montage représenté.

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

L'installateur doit rester simple, robuste et compréhensible.

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

### Actions
Ne jamais inventer les faces de relais.
Si une action dépend d'un `side` non confirmé :
- le rendre configurable ;
- ou désactiver proprement l'action jusqu'à confirmation.

---

## Versioning
À chaque itération demandant une modification du projet :
- incrémenter `fusion.version` avec une version strictement supérieure ;
- synchroniser tout fichier de manifeste/version lié ;
- garder `install.lua` cohérent avec l'état réel du programme si ses capacités changent.

Ne jamais modifier la version sans refléter un vrai changement du code ou du comportement.

---

## Règles de compte rendu
Après intervention, toujours fournir un résumé clair contenant :
- ce qui a été fait ;
- ce qui a été vérifié ;
- ce qui n'a pas pu être validé ;
- les fichiers modifiés ;
- le statut Git final ;
- le statut du commit/push ;
- les points restants éventuels.

Le résumé doit être utile pour reprendre rapidement l'itération suivante.

---

## Interdictions
L'agent ne doit jamais :
- ignorer le `pull` initial ;
- ignorer le `push` final sans le signaler ;
- écraser silencieusement des changements locaux ;
- supprimer une fonctionnalité validée sans demande explicite ;
- casser la compatibilité petit écran par ajout visuel ;
- durcir le code contre le terrain réel avec des valeurs trop figées si une détection est possible.
