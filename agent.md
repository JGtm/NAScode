# agent.md — Règles de travail (agent/contributeur)

Ce dépôt contient un script Bash **modulaire** de conversion vidéo (HEVC/x265) orienté batch (séries/films).

Ce document décrit les attentes lorsque tu fais évoluer le code (humain ou agent).

## Priorités

- Priorité n°1 : **fiabilité** (ne pas casser des conversions en cours).
- Priorité n°2 : **maintenabilité** (modularité, lisibilité, tests).
- Priorité n°3 : performance (uniquement quand c’est mesuré/justifié).

## Principes de conception

- Respecter l’architecture modulaire existante (`convert.sh` charge `lib/*.sh`).
- Éviter les “gros” scripts monolithiques : préférer des helpers dédiés (ex: `_compute_*`, `_build_*`).
- Garder les fonctions **petites** et **testables** (entrées/sorties claires).
- Ne pas casser les interfaces existantes sans raison (noms de variables exportées, signatures de fonctions, logs).
- Ne pas ajouter de dépendances externes sans justification (objectif : GNU/Linux + macOS + Git Bash).

## Commandes essentielles

### Lancer une conversion

```bash
bash convert.sh [options]
```

Exemples courants :

```bash
# Simulation (ne transcode pas)
bash convert.sh -d -s "/chemin/source"

# Mode série (défaut)
bash convert.sh -s "/chemin/vers/series"

# Mode film + VMAF
bash convert.sh -m film -v -s "/chemin/vers/films"

# Test rapide (30s)
bash convert.sh -t -r -l 5
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

- `convert.sh` : point d’entrée, charge les modules `lib/`.
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

En cas de blocage après un crash (si aucun `convert.sh` ne tourne) :

```bash
rm -f /tmp/conversion_video.lock /tmp/conversion_stop_flag
```

### Windows (Git Bash / WSL)

- Chemins : éviter les chemins relatifs ambiguës ; `convert.sh` convertit `SOURCE` en chemin absolu.
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
- **Toute nouvelle fonction doit être couverte par des tests unitaires** dans `tests/`.
- Si la fonction impacte le workflow complet (CLI, conversion, résumé), ajouter aussi un **test e2e** si applicable.- Si une fonction change (signature/comportement/side effects), mettre à jour ou ajouter les tests Bats correspondants dans `tests/`.
- Si une option CLI, un mode, un suffixe, ou une convention de log change : mettre à jour `README.md`.
- Ne pas “corriger” les tests en les affaiblissant : préférer rendre le code plus déterministe/robuste.

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
| Preset | medium | slow |
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
