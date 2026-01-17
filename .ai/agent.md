# agent.md — Règles de travail (agent/contributeur)

Ce dépôt contient un script Bash **modulaire** de conversion vidéo (HEVC/x265) orienté batch (séries/films).

Ce document décrit l’**intention** et les **garde-fous** à conserver quand tu fais évoluer le code (humain ou agent).

L’objectif n’est pas d’énumérer toutes les actions possibles, mais de rendre explicite la logique derrière les règles du repo : préserver une base stable, compréhensible et testable, même quand les fonctions grossissent.

---

## Rôle

Agir comme un contributeur “senior” Bash/Unix et architecture système.

- Penser en termes de **comportement** (contrats, invariants, erreurs) plutôt que de “lignes de code”.
- Optimiser pour la **maintenance** et la **robustesse** avant la performance (sauf mesure).
- Prioriser la **prévisibilité** : logs, sorties, codes de retour et effets de bord doivent être intentionnels.

## Objectifs (à garder en tête)

1. **Fiabilité opérationnelle** : ne pas casser des conversions en cours, gérer correctement les interruptions, et échouer proprement.
2. **Maintenabilité** : le code doit rester lisible et modulaire quand il grossit (éviter la duplication, isoler les décisions, limiter les globals).
3. **Testabilité** : chaque changement de comportement doit être observable et testable (Bats, mocks, fonctions isolées).
4. **Documentation utile** : documenter ce qui impacte l’UX (CLI/logs/suffixes) et les choix d’architecture, pas le trivial.

Ces objectifs guident les sections ci-dessous ; les listes sont des **heuristiques** et ne remplacent pas le jugement.

---

## Principes Fondamentaux

1. **Work doggedly**: Ton but est d'être autonome. Si tu connais l'objectif global, continue tant que tu peux progresser. Si tu t'arrêtes, justifie pourquoi.
2. **Work smart**: En cas de bug, prends du recul. Ajoute des logs pour vérifier tes hypothèses.
3. **Check your work**: Si tu écris du code, essaie de vérifier qu'il fait ce qui est attendu (ex: simulation, logs).
4. **handoff.md**: À la fin de chaque session, crée/mets à jour `.ai/handoff.md` avec un résumé de ce qui a été fait et des derniers prompts.

## Conduite de l'Agent

- Vérifie tes hypothèses avant d'exécuter des commandes ; signale les incertitudes.
- Demande des clarifications si la demande est ambiguë ou risquée.
- Résume l'intention avant des correctifs multi-étapes.
- Cite les sources (documentation) avec précision.
- Découpe le travail en étapes incrémentales.

## Workflow Loop

**EXPLORE** → **PLAN** → **ACT** → **OBSERVE** → **REFLECT** → **COMMIT**

## Pipeline de développement multimodal (LLM)

Quand l'utilisateur le demande explicitement, appliquer ce pipeline en 4 phases :

1. **Phase de conception (GPT-5.2)** : analyser la requête, produire un plan d'implémentation atomique, identifier les dépendances et les risques. Cette phase est garante de la cohérence de l'architecture.
2. **Phase d'exécution (Claude 4.5 Opus)** : implémenter le code à partir du plan. Priorité à l'adhérence au style local et à la robustesse logique.
3. **Phase de documentation & audit (GPT-5.2)** : relire le travail, compléter/mettre à jour la documentation (README, docs, commentaires/docstrings si applicables) et détecter les régressions potentielles.
4. **Mise à jour du contexte (Agent)** : inscrire les changements clés dans `.ai/DEVBOOK.md` pour conserver une mémoire durable du projet.

Note : ce pipeline complète la section "Règle de planification" plus bas (plan + analyse + options avant exécution pour tout changement non-trivial).

---

## ⛔ RÈGLE OBLIGATOIRE : Ne JAMAIS travailler sur `main`

> **STOP ! Avant TOUTE modification de fichier, vérifie la branche courante.**
>
> Si tu es sur `main`, **crée d'abord une branche** avant d'éditer quoi que ce soit.

Cette règle est **non négociable**. Aucune exception.

### Workflow obligatoire

```bash
# 1. TOUJOURS vérifier la branche courante AVANT de modifier un fichier
git branch --show-current

# 2. Si sur main, créer une branche AVANT toute modification
git checkout -b fix/description-courte   # ou feature/, refactor/, docs/

# 3. Faire les modifications...

# 4. Commit et push
git add . && git commit -m "description"
```

### Si tu as modifié main par erreur

```bash
# Déplacer les changements vers une nouvelle branche
git stash
git checkout -b fix/nom-approprié
git stash pop
```

### Pourquoi ?

- `main` doit toujours être stable et déployable
- Les branches permettent la review avant merge
- Évite les conflits et les régressions

### Exception : opérations Git sur `main`

Les **opérations Git** suivantes sont autorisées directement sur `main` **si l'utilisateur le demande explicitement** :

- `git merge <branche>` — fusionner une branche validée
- `git pull` — récupérer les mises à jour distantes
- `git rebase` — réorganiser l'historique (avec précaution)

Ces opérations ne modifient pas directement le code mais gèrent l'historique Git.

**Attention** : toute modification de fichier (code, docs, config) reste interdite sur `main`.

---

## Priorités

- Priorité n°1 : **fiabilité** (ne pas casser des conversions en cours).
- Priorité n°2 : **maintenabilité** (modularité, lisibilité, tests).
- Priorité n°3 : performance (uniquement quand c’est mesuré/justifié).

## Principes de conception & Style

- **Blend in, don’t reinvent**: Respecte le style existant, le nommage et l'architecture modulaire (`nascode` charge `lib/*.sh`).
- **Re-use before you write**: Préfère les helpers existants (`_compute_*`, `_build_*`).
- **Propose, then alter**: Les refactors majeurs nécessitent une validation préalable.
- Garder les fonctions **petites** et **testables** (entrées/sorties claires).
- Ne pas casser les interfaces existantes sans raison (noms de variables exportées, signatures de fonctions, logs).
- Ne pas ajouter de dépendances externes sans justification (objectif : GNU/Linux + macOS + Git Bash).

## Commandes essentielles

### Lancer une conversion

```bash
bash nascode [options]
```

Exemples courants :

```bash
# Simulation (ne transcode pas)
bash nascode -d -s "/chemin/source"

# Mode série (défaut)
bash nascode -s "/chemin/vers/series"

# Mode film + VMAF
bash nascode -m film -v -s "/chemin/vers/films"

# Test rapide (30s)
bash nascode -t -r -l 5
```

### Lancer les tests

Le repo utilise **Bats**.

```bash
bash run_tests.sh

# Verbose
bash run_tests.sh -v

# Filtrer
bash run_tests.sh -f "queue"  # exemple
```

Sur Git Bash / Windows, `run_tests.sh` essaie aussi `${HOME}/.local/bin/bats` si `bats` n’est pas sur le PATH.

## Dossiers et fichiers clés

- `nascode` : point d’entrée, charge les modules `lib/`.
- `lib/config.sh` : configuration globale, paramètres par mode (`serie` / `film`).
- `lib/transcode_video.sh` : logique vidéo (pix_fmt, downscale 1080p, suffixe effectif, adaptation bitrate 720p).
- `lib/conversion.sh` : orchestration FFmpeg (construction des commandes, passes, etc.).
- `lib/queue.sh` : index + file d’attente.
- `logs/` : logs d’exécution + index persistants.
- `Converted/` : sortie par défaut.

## Pièges connus (à vérifier avant de modifier)

### Lockfile / arrêt

- Lockfile : `/tmp/conversion_video.lock`
- Stop flag : `/tmp/conversion_stop_flag`

En cas de blocage après un crash (si aucun `nascode` ne tourne) :

```bash
rm -f /tmp/conversion_video.lock /tmp/conversion_stop_flag
```

### Windows (Git Bash / WSL)

- Chemins : éviter les chemins relatifs ambiguës ; `nascode` convertit `SOURCE` en chemin absolu.
- Outils : `ffmpeg`, `ffprobe`, `awk`, `stat` doivent être disponibles.

## Conventions de code (Bash)

- Toujours citer les variables : `"$var"`.
- Préférer `[[ ... ]]` à `[ ... ]`.
- Préférer des fonctions pures quand possible (ex: helpers `_compute_*`).
- Ne pas ajouter de dépendances externes sans justification (le script vise GNU/Linux/macOS/Git Bash).
- Éviter les changements de formatage “massifs” : PR/patchs focalisés.

## Règle de planification (avant “gros travail”)

Avant toute modification non-triviale (multi-fichiers, changement de comportement, refactor, nouvelle option CLI, etc.) :

1. Établir un **plan** (phases + fichiers touchés + risques + validation).
2. Faire une **analyse** courte (où est le bon endroit, quelles contraintes, impacts Windows/macOS).
3. Proposer **2–3 options** si plusieurs approches sont possibles (avec compromis).
4. Attendre validation/accord avant exécution.

Pour les petits changements (typo, ajustement local, test manquant évident) : plan léger ou exécution directe si c’est clairement sans risque.

## Politique de tests et documentation

> **Note importante** : L'agent ne lance pas les tests automatiquement sauf demande explicite. C'est l'utilisateur qui lance `run_tests.sh` et partage les logs.

- **Création de tests** : Toute nouvelle fonction ou correction de bug doit être accompagnée d'un test unitaire ou e2e dans `tests/`.
- **Documentation** : Si une option CLI, un mode, un suffixe, ou une convention de log change : mettre à jour `README.md`.
- **Robustesse** : Ne pas “corriger” les tests en les affaiblissant : préférer rendre le code plus déterministe/robuste.

## ⛔ RÈGLE OBLIGATOIRE AVANT MERGE : Mettre à jour le DEVBOOK

Avant tout merge (ou avant de demander une review pour merge), **mettre à jour obligatoirement** `.ai/DEVBOOK.md`.

- Objectif : conserver une mémoire durable des décisions et changements qui impactent UX/CLI/tests/archi.
- Contenu attendu : *quoi*, *où* (fichiers), *pourquoi*, et *impact* (tests/doc/risques).
- Cette étape est requise même si les changements semblent “mineurs” dès lors qu’ils modifient le comportement, les logs, ou l’UX.

## Règle après merge avec `main`

Après chaque merge (ou rebase) depuis `main`, faire systématiquement une passe de cohérence :

- Relire `README.md` : options, exemples, prérequis, chemins par défaut, sections “Dépannage”.
- Vérifier que les fonctionnalités documentées correspondent au comportement réel.
- Mettre à jour `README.md` si nécessaire (même si le merge ne touche “que” du code).
- Relancer les tests : `bash run_tests.sh`.

## Conventions de commits

- Commits **explicites**, un sujet/problème par commit.
- Message de commit : sujet court + corps structuré.
- Dans le corps : **un point (bullet) par ligne**.

Exemple :

```text
fix(queue): stabilise la génération d’index

- Empêche les doublons quand l’index existe déjà
- Ajoute un test Bats sur le cas “index présent”
- Met à jour la doc de l’option --keep-index
```

### Template de commit

Le repo fournit un template prêt à l’emploi : `.gitmessage.txt`.

Pour l’activer localement :

```bash
git config commit.template .gitmessage.txt
```

## Checklist avant de proposer un changement

- Le changement est-il compatible macOS + GNU/Linux + Git Bash ?
- Les tests Bats passent : `bash run_tests.sh`.
- Pas de modification “silencieuse” des chemins, suffixes, ou conventions de logs sans doc.
- Si le comportement change : mise à jour de `README.md`.

## Paramètres de conversion (référence rapide)

| Paramètre | Mode `serie` | Mode `film` |
|-----------|--------------|-------------|
| Bitrate cible | 2070 kbps | 2035 kbps |
| Maxrate | 2520 kbps | 3200 kbps |
| Preset | medium | medium |
| Keyint (GOP) | 600 (~25s) | 240 (~10s) |
| Tune fastdecode | Oui | Non |
| X265 tuned | Oui | Non |
| Pass 1 rapide | Oui | Non |
| Mode par défaut | Single-pass CRF | Two-pass |

## Politique de tests (bonnes pratiques)

- **Tests par comportement** : vérifier des plages et relations (`MAXRATE > TARGET`), pas des valeurs en dur.
- **Tests robustes** : un changement de config ne doit pas casser les tests si le comportement reste correct.
- **Logs de tests** : les résultats sont enregistrés dans `logs/tests/tests_YYYYMMDD_HHMMSS.log`.

## Notes de debugging

- Pour inspecter une commande FFmpeg générée : activer/consulter les logs dans `logs/`.
- En cas de comportement inattendu sur un fichier précis : lancer une exécution limitée (`-l 1`) et/ou un sample (`-t`).
