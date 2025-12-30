# PLAN — Smart skip « sortie équivalente déjà présente » (base_name)

Date: 2025-12-30
Branche de travail: `feature/smart-skip-best-existing`

## Objectif
Quand le fichier de sortie exact (calculé via suffix dynamique + options) **n’existe pas**, éviter une reconversion inutile si une variante **équivalente et conforme** existe déjà dans le **bon sous-dossier de sortie**.

Cas typique: plusieurs fichiers de sortie pour le même épisode (variantes de sous-titres / audio / suffix non standard), mais la vidéo et l’audio sont déjà dans les critères NAScode.

Contraintes:
- Pas de scan global d’`OUTPUT_DIR` au démarrage (ne pas ralentir le script).
- Fonctionne avec arborescence: `SOURCE/Serie/Saison/Episode.mkv` → `OUTPUT_DIR/Serie/Saison/Episode...mkv`.
- Ne dépend pas du suffix (peut être absent ou non standard).
- Ignore les sous-titres (ils ne doivent pas empêcher le skip).

## Définition de « conforme » (cohérente NAScode)
On considère un candidat existant comme acceptable si **NAScode aurait skippé ce candidat** selon ses règles actuelles:

- Vidéo:
  - codec meilleur ou égal au codec cible (ex: AV1 >= HEVC),
  - bitrate vidéo sous le seuil dynamique (MAXRATE * (1 + tolérance)).
- Audio:
  - logique smart codec/bitrate existante (codec et bitrate « OK » selon les règles),
  - optionnel: refuser si > 2 pistes audio (si règle activée).

Remarque CRF:
- CRF exact est rarement fiable/portable à lire depuis un fichier encodé. Le design n’en dépend pas.

## Principe « lazy » (zéro coût au démarrage)
La logique s’exécute **uniquement** pour un fichier en cours de traitement, et uniquement si:
1) `final_output` n’existe pas,
2) `final_dir` existe (dossier de sortie correspondant au fichier),
3) `base_name` non vide.

## Anti-confusion (E01/E02): matching exact par préfixe
Pour éviter de mélanger Episode 01 et Episode 02, on ne fait **pas** de fuzzy matching.

On ne retient que les candidats `.mkv` dont le nom commence par **exactement** `base_name`.

Ex:
- `base_name = Show.S01E01`
  - OK: `Show.S01E01_x265_2070k_1080p.mkv`, `Show.S01E01 (FR).mkv`
  - KO: `Show.S01E02_x265_...mkv`

Important: utiliser un test de préfixe **littéral** (pas de glob) pour éviter les problèmes avec `[` `]` etc.

## Garde-fou « même contenu »
Comparer le candidat à la source avant de conclure:
- Durée: |durée_source - durée_candidat| <= tolérance (ex: 2s)
- Optionnel (recommandé): résolution identique (ou au moins très proche) pour encore réduire les faux positifs.

Note perf:
- Lire `duration/width/height/codec/bitrate/audio` via ffprobe **ne décode pas** la vidéo; c’est de la métadonnée.
- On peut récupérer toutes ces valeurs en un seul ffprobe (helper `get_full_media_metadata`).

## Sélection « top N » + probes bornés
Même si on ne match que `base_name*`, il peut rester plusieurs variantes du même épisode.

Pour limiter ffprobe:
1) lister les `.mkv` du `final_dir` (limite `MAX_CANDIDATES`, ex: 120),
2) score “cheap” par nom (sans ffprobe) pour prioriser les candidats plausibles,
3) ne prober que les top N (ex: 12),
4) early-exit dès qu’un candidat conforme est trouvé.

### Score “cheap” proposé (ne doit pas être bloquant)
Exemples de bonus (si présents):
- contient `_${codec_suffix}_` (ex: `_x265_` / `_av1_`)
- contient `1080p` / `720p`
- contient `_${TARGET_BITRATE_KBPS}k`

Si ces indices n’existent pas, on garde un score neutre: la robustesse vient des garde-fous durée + décision codec/bitrate/audio.

## Paramètres / configuration (proposés)
À valider avant implémentation:
- `SMART_SKIP_BASENAME` (bool, défaut: true)
- `SMART_SKIP_BASENAME_MAX_CANDIDATES` (int, défaut: 120)
- `SMART_SKIP_BASENAME_MAX_PROBES` (int, défaut: 12)
- `SMART_SKIP_BASENAME_DURATION_TOLERANCE_SECS` (int, défaut: 2)
- `SMART_SKIP_BASENAME_CHECK_RESOLUTION` (bool, défaut: true)
- Optionnel: `SMART_SKIP_BASENAME_MAX_AUDIO_STREAMS` (int, défaut: 2; ou 0 = désactivé)

## Points d’injection (où brancher)
Dans la chaîne de traitement par fichier, après avoir calculé:
- `final_dir`, `base_name`, `final_output`

Ordre proposé:
1) check “final_output existe” (comportement actuel)
2) smart-skip: si final_output absent, chercher un candidat “équivalent” dans final_dir
3) dry-run handler
4) suite normale (temp files, conversion…)

Pourquoi ici:
- on a déjà `final_dir`/`base_name`/métadonnées source,
- on ne crée pas de fichiers temporaires inutilement.

## Pseudo-code (version lisible)

Entrées: `file_original`, `final_dir`, `base_name`, `final_output`, métadonnées source (si déjà lues)

1. Si `final_output` existe → skip (log standard)
2. Si `SMART_SKIP_BASENAME=false` → continuer
3. Lister candidats dans `final_dir`:
   - `.mkv` seulement
   - nom commence par `base_name`
   - limiter à `MAX_CANDIDATES`
4. Trier candidats par score “cheap”
5. Pour chaque candidat dans top `MAX_PROBES`:
   - récupérer métadonnées candidat (idéalement via helper unique)
   - vérifier durée (±tol)
   - (option) vérifier résolution
   - (option) vérifier nb pistes audio <= max
   - appliquer décision “serait-ce SKIP selon les règles NAScode ?”
     - si oui → log smart-skip + return skip
6. Sinon → continuer conversion normale

## Décision « serait-ce skip ? » (réutilisation de logique)
Idée: utiliser la logique existante de décision (ex: `_determine_conversion_mode`) sur le candidat.

Important:
- Ne pas dépendre d’un suffix.
- Ne pas confondre “source en cours” vs “candidat existant”: la décision doit s’appliquer au candidat.
- Si la fonction de décision modifie une variable globale (ex: `CONVERSION_ACTION`), sauvegarder/restaurer pour ne pas perturber la suite.

## Logging
Ajouter un log explicite (stdout/stderr) + session log:
- `SKIPPED (Sortie équivalente déjà présente: <nom_fichier>)`

En mode `--limit`:
- déclencher le même mécanisme `update_queue` que les autres skips (comportement cohérent).

## Tests Bats (à écrire)
Niveau visé: tests unitaires + stubs ffprobe (pas besoin de vrais fichiers lourds).

Cas minimum:
1) `final_output` existe → skip inchangé
2) `final_output` absent mais `base_name*.mkv` conforme existe → smart-skip
3) candidat présent mais durée différente → pas de smart-skip
4) candidat présent mais audio non conforme → pas de smart-skip
5) (option) candidat > 2 pistes audio → pas de smart-skip si règle activée

Stratégie de test:
- Utiliser le harness existant dans `tests/test_conversion.bats`.
- Stub `ffprobe` pour:
  - renvoyer durée/bitrate/codec prévisibles
  - simuler audio codec/bitrate
- Créer des fichiers dummy dans un `final_dir` temporaire (touch + noms contrôlés).

## Documentation (README)
Ajouter une petite section:
- “Smart skip: sortie équivalente déjà présente (même base_name)”,
- mention de la vérif durée (et résolution si activée),
- mention que les sous-titres ne sont pas pris en compte.

## Risques / points d’attention
- Faux positifs si deux contenus différents ont exactement le même `base_name` dans le même dossier.
  - Mitigation: durée ±2s + (option) résolution.
- `base_name` non normalisé (E1 vs E01) → pas de match.
  - Hors-scope initial; possible amélioration: normalisation SxxEyy.
- Performance: `find` + tri dans un dossier.
  - Mitigation: max candidates + top N probes + early-exit.

## Critères d’acceptation
- Ne modifie pas le comportement si `final_output` existe (skip identique).
- Ajoute seulement un skip supplémentaire dans le cas “sortie équivalente déjà présente”.
- Ne ralentit pas le démarrage (aucun scan global).
- Fonctionne sur une arborescence profonde (séries/saisons).
- Tests Bats couvrent au moins 3 cas (exist, smart-skip, durée mismatch).
