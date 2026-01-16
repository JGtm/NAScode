#!/bin/bash
# shellcheck disable=SC2034
###########################################################
# LOCALE FRANÇAISE (source de vérité)
#
# Ce fichier contient tous les messages utilisateur en français.
# Structure : MSG_<MODULE>_<DESCRIPTION>="Message avec %s placeholders"
#
# Conventions :
#   - Clés en MAJUSCULES avec underscores
#   - Préfixe par module (ARG, UI, CONV, SYS, etc.)
#   - Placeholders printf : %s (string), %d (int), %.2f (float)
###########################################################

###########################################################
# ARGUMENTS / CLI (lib/args.sh)
###########################################################

MSG_ARG_REQUIRES_VALUE="%s doit être suivi d'une valeur"
MSG_ARG_LIMIT_POSITIVE="--limit doit être suivi d'un nombre positif"
MSG_ARG_LIMIT_MIN_ONE="--jobs doit être suivi d'un nombre >= 1"
MSG_ARG_MIN_SIZE_REQUIRED="--min-size doit être suivi d'une taille (ex: 700M, 1G)"
MSG_ARG_MIN_SIZE_INVALID="Taille invalide pour --min-size : '%s' (ex: 700M, 1G, 500000000)"
MSG_ARG_QUEUE_NOT_FOUND="Fichier queue '%s' introuvable"
MSG_ARG_FILE_NOT_FOUND="Fichier '%s' introuvable"
MSG_ARG_AUDIO_INVALID="Codec audio invalide : '%s'. Valeurs acceptées : copy, aac, ac3, eac3, opus"
MSG_ARG_AUDIO_REQUIRES_VALUE="-a/--audio doit être suivi d'un nom de codec (copy, aac, ac3, eac3, opus)"
MSG_ARG_CODEC_INVALID="Codec invalide : '%s'. Valeurs acceptées : hevc, av1, ..."
MSG_ARG_CODEC_REQUIRES_VALUE="--codec doit être suivi d'un nom de codec (hevc, av1)"
MSG_ARG_OFF_PEAK_INVALID="Format invalide pour --off-peak (attendu: HH:MM-HH:MM)"
MSG_ARG_UNKNOWN_OPTION="Option inconnue : %s"
MSG_ARG_UNEXPECTED="Argument inattendu : %s"
MSG_ARG_UNEXPECTED_HINT="Vérifiez que toutes les options sont précédées d'un tiret (ex: -l 3)"
MSG_ARG_LANG_INVALID="Langue invalide : '%s'. Valeurs acceptées : fr, en"

###########################################################
# GENERAL / COMMON
###########################################################

MSG_UNKNOWN="inconnu"

###########################################################
# SYSTÈME / DÉPENDANCES (lib/system.sh)
###########################################################

MSG_SYS_DEPS_MISSING="Dépendances manquantes : %s"
MSG_SYS_ENV_CHECK="Vérification de l'environnement"
MSG_SYS_FFMPEG_VERSION_UNKNOWN="Impossible de déterminer la version de ffmpeg."
MSG_SYS_FFMPEG_VERSION_OLD="Version FFMPEG (%s) < Recommandée (%s)"
MSG_SYS_FFMPEG_VERSION_DETECTED="Version ffmpeg détectée : %s"
MSG_SYS_SOURCE_NOT_FOUND="Source '%s' introuvable."
MSG_SYS_SUFFIX_FORCED="Utilisation forcée du suffixe de sortie : %s"
MSG_SYS_SUFFIX_DISABLED="Suffixe de sortie désactivé"
MSG_SYS_SUFFIX_CONTINUE_NO_SUFFIX="Continuation SANS suffixe. Vérifiez le Dry Run ou les logs."
MSG_SYS_SUFFIX_CANCELLED="Opération annulée. Modifiez le suffixe ou le dossier de sortie."
MSG_SYS_VMAF_NOT_AVAILABLE="VMAF demandé mais libvmaf non disponible dans FFmpeg"
MSG_SYS_ENV_VALIDATED="Environnement validé"
MSG_SYS_CONV_MODE_LABEL="Mode conversion"
MSG_SYS_PLEXIGNORE_EXISTS="Fichier .plexignore déjà présent dans le répertoire de destination"
MSG_SYS_PLEXIGNORE_CREATE="Créer un fichier .plexignore dans le répertoire de destination pour éviter les doublons dans Plex ?"
MSG_SYS_PLEXIGNORE_CREATED="Fichier .plexignore créé dans le répertoire de destination"
MSG_SYS_PLEXIGNORE_SKIPPED="Création de .plexignore ignorée"
MSG_SYS_NO_SUFFIX_ENABLED="Option --no-suffix activée. Le suffixe est désactivé par commande."
MSG_SYS_SUFFIX_ENABLED="Suffixe de sortie activé"
MSG_SYS_SUFFIX_USE="Utiliser le suffixe de sortie ?"
MSG_SYS_OVERWRITE_RISK_TITLE="RISQUE D'ÉCRASEMENT"
MSG_SYS_OVERWRITE_SAME_DIR="Source et sortie IDENTIQUES : %s"
MSG_SYS_OVERWRITE_WARNING="L'absence de suffixe ÉCRASERA les originaux !"
MSG_SYS_DRYRUN_PREVIEW="(MODE DRY RUN) : Visualisez les fichiers qui seront écrasés"
MSG_SYS_CONTINUE_NO_SUFFIX="Continuer SANS suffixe dans le même répertoire ?"
MSG_SYS_COEXIST_MESSAGE="Les fichiers originaux et convertis coexisteront dans le même répertoire."
MSG_SYS_VMAF_ALT_FFMPEG="VMAF via FFmpeg alternatif (libvmaf détecté)"
###########################################################
# QUEUE / INDEX (lib/queue.sh, lib/index.sh)
###########################################################

MSG_QUEUE_FILE_NOT_FOUND="ERREUR : Le fichier queue '%s' n'existe pas."
MSG_QUEUE_FILE_EMPTY="Le fichier queue est vide"
MSG_QUEUE_FORMAT_INVALID="Format du fichier queue invalide (séparateur NUL attendu)"
MSG_QUEUE_VALID="Le fichier queue semble valide (%s fichiers détectés)."
MSG_QUEUE_VALIDATED="Fichier queue validé : %s"
MSG_QUEUE_LIMIT_RANDOM="Sélection de %s fichier(s) maximum"
MSG_QUEUE_LIMIT_NORMAL="%s fichier(s) maximum"
MSG_INDEX_REGEN_FORCED="Regénération de l'index demandée."
MSG_INDEX_NO_META="Pas de métadonnées pour l'index existant, regénération..."
MSG_INDEX_SOURCE_NOT_IN_META="Source non trouvée dans les métadonnées, regénération..."
MSG_INDEX_SOURCE_CHANGED="Source modifiée, regénération automatique de l'index."
MSG_INDEX_SOURCE_CHANGED_DETAIL="La source a changé :"
MSG_INDEX_REGEN_AUTO="Regénération automatique de l'index..."
MSG_INDEX_EMPTY="Index vide, regénération nécessaire..."
MSG_INDEX_CREATED_FOR="Index créé pour"
MSG_INDEX_CURRENT_SOURCE="Source actuelle"
MSG_INDEX_CUSTOM_QUEUE="Utilisation du fichier queue personnalisé : %s"
MSG_INDEX_FORCED_USE="Utilisation forcée de l'index existant"
MSG_INDEX_FOUND_TITLE="Index existant trouvé"
MSG_INDEX_CREATION_DATE="Date de création : %s"
MSG_INDEX_KEEP_QUESTION="Conserver ce fichier index ?"
MSG_INDEX_REGENERATING="Régénération d'un nouvel index..."
MSG_INDEX_KEPT="Index existant conservé"

###########################################################
# LOCK / INTERRUPTION (lib/lock.sh)
###########################################################

MSG_LOCK_INTERRUPT="Interruption détectée, arrêt en cours..."
MSG_LOCK_ALREADY_RUNNING="Le script est déjà en cours d'exécution (PID %s)."
MSG_LOCK_STALE="Fichier lock trouvé mais processus absent. Nettoyage..."

###########################################################
# TRAITEMENT / PROCESSING (lib/processing.sh)
###########################################################

MSG_PROC_INTERRUPTED="Traitement interrompu (arrêt demandé pendant l'attente)"
MSG_PROC_MKFIFO_FAILED="Impossible de créer le FIFO (mkfifo). Bascule en mode --limit sans remplacement dynamique."
MSG_PROC_MKFIFO_NOT_FOUND="mkfifo introuvable : mode --limit sans remplacement dynamique."
MSG_PROC_ALL_OPTIMIZED="Tous les fichiers restants sont déjà optimisés."

###########################################################
# HEURES CREUSES / OFF-PEAK (lib/off_peak.sh)
###########################################################

MSG_OFF_PEAK_STOP="Arrêt demandé pendant l'attente des heures creuses"

###########################################################
# CONVERSION (lib/conversion.sh, lib/finalize.sh)
###########################################################

MSG_CONV_EMPTY_ENTRY="Entrée vide détectée dans la queue, skip."
MSG_CONV_FILE_NOT_FOUND="Fichier introuvable, skip : %s"
MSG_CONV_METADATA_ERROR="Impossible de lire les métadonnées, skip : %s"
MSG_CONV_PREP_FAILED="Préparation des chemins impossible : %s"
MSG_CONV_TMP_NOT_FOUND="ERREUR: Fichier temporaire introuvable après encodage: %s"
MSG_CONV_GAIN_REDIRECT="Gain insuffisant : sortie redirigée vers %s"
MSG_CONV_FAILED="Échec de la conversion : %s"
MSG_CONV_INTERRUPTED="Conversion interrompue, fichier temporaire conservé: %s"
MSG_CONV_MOVE_ERROR="ERREUR Impossible de déplacer (custom_pv) : %s"

###########################################################
# TRANSCODAGE (lib/transcode_video.sh)
###########################################################

MSG_TRANSCODE_UNKNOWN_MODE="Mode d'encodage inconnu: %s"
MSG_TRANSCODE_PASS1_ERROR="Erreur lors de l'analyse (pass 1)"

###########################################################
# FFMPEG PIPELINE (lib/ffmpeg_pipeline.sh)
###########################################################

MSG_FFMPEG_UNKNOWN_MODE="Mode FFmpeg inconnu: %s"
MSG_FFMPEG_SHORT_VIDEO="Vidéo courte : segment de %ss à partir de %s"
MSG_FFMPEG_REMUX_ERROR="Erreur lors du remuxage"
MSG_PROGRESS_DONE="Terminé ✅"
MSG_PROGRESS_ANALYSIS_OK="Analyse OK"
###########################################################
# VMAF (lib/vmaf.sh)
###########################################################

MSG_VMAF_FPS_IGNORED="VMAF ignoré (FPS modifié: %s → %s)"
MSG_VMAF_FILE_NOT_FOUND="NA (fichier introuvable)"
MSG_VMAF_FILE_EMPTY="NA (fichier vide)"
MSG_VMAF_QUALITY_EXCELLENT="Excellent"
MSG_VMAF_QUALITY_VERY_GOOD="Très bon"
MSG_VMAF_QUALITY_GOOD="Bon"
MSG_VMAF_QUALITY_DEGRADED="Dégradé"
MSG_VMAF_QUALITY_NA="NA"

###########################################################
# CONFIGURATION (lib/config.sh)
###########################################################

MSG_CFG_UNKNOWN_MODE="Mode de conversion inconnu : %s"
MSG_CFG_ENCODER_INVALID="Configuration codec invalide. Vérifiez que FFmpeg supporte l'encodeur %s."
MSG_CFG_CODEC_UNSUPPORTED="Codec non supporté : %s"
MSG_CFG_CODEC_AVAILABLE="Codecs disponibles : %s"
MSG_CFG_ENCODER_UNAVAILABLE="Encodeur non disponible dans FFmpeg : %s"

###########################################################
# UI / AFFICHAGE (lib/ui.sh)
###########################################################

MSG_UI_REDIRECT_TITLE="Sortie redirigée"
MSG_UI_REDIRECT_MSG="Gain insuffisant : fichier déplacé vers %s"
MSG_UI_COEXIST_TITLE="Coexistence de fichiers"
MSG_UI_TASKS_END="Fin des tâches"

###########################################################
# NASCODE (point d'entrée)
###########################################################

MSG_MAIN_LIB_NOT_FOUND="ERREUR : Répertoire lib introuvable : %s"
MSG_MAIN_LIB_HINT="Assurez-vous que tous les modules sont présents dans le dossier lib/"
MSG_MAIN_PATH_INVALID="ERREUR: Chemin de fichier invalide : %s"
MSG_MAIN_FILE_NOT_EXIST="ERREUR: Le fichier source n'existe pas : %s"
MSG_MAIN_DIR_NOT_EXIST="ERREUR: Le répertoire source n'existe pas : %s"
MSG_MAIN_SOURCE_EXCLUDED="ERREUR: Le répertoire source est exclu par la configuration (EXCLUDES) : %s"
MSG_MAIN_STOP_BEFORE_PROC="Arrêt demandé avant le début du traitement."
MSG_MAIN_DRYRUN_DONE="🧪 Dry run terminé"

###########################################################
# AIDE CLI (show_help)
###########################################################

MSG_HELP_USAGE="Usage :"
MSG_HELP_OPTIONS="Options :"
MSG_HELP_SOURCE="Dossier source (ARG) [défaut : dossier parent]"
MSG_HELP_OUTPUT="Dossier de destination (ARG) [défaut : \`Converted\` au même niveau que le script]"
MSG_HELP_EXCLUDE="Ajouter un pattern d'exclusion (ARG)"
MSG_HELP_MODE="Mode de conversion : film, adaptatif, serie (ARG) [défaut : serie]"
MSG_HELP_MIN_SIZE="Filtrer l'index/queue : ne garder que les fichiers >= SIZE (ex: 700M, 1G)"
MSG_HELP_DRYRUN="Mode simulation sans conversion (FLAG)"
MSG_HELP_SUFFIX="Activer un suffixe dynamique ou définir un suffixe personnalisé (ARG optionnel)"
MSG_HELP_NO_SUFFIX="Désactiver le suffixe _x265 (FLAG)"
MSG_HELP_RANDOM="Tri aléatoire : sélectionne des fichiers aléatoires (FLAG) [défaut : 10]"
MSG_HELP_LIMIT="Limiter le traitement à N fichiers (ARG)"
MSG_HELP_JOBS="Nombre de conversions parallèles (ARG) [défaut : 1]"
MSG_HELP_QUEUE="Utiliser un fichier queue personnalisé (ARG)"
MSG_HELP_NO_PROGRESS="Désactiver l'affichage des indicateurs de progression (FLAG)"
MSG_HELP_QUIET="Mode silencieux : n'affiche que les warnings/erreurs (FLAG)"
MSG_HELP_HELP="Afficher cette aide (FLAG)"
MSG_HELP_KEEP_INDEX="Conserver l'index existant sans demande interactive (FLAG)"
MSG_HELP_REGEN_INDEX="Forcer la régénération de l'index au démarrage (FLAG)"
MSG_HELP_VMAF="Activer l'évaluation VMAF de la qualité vidéo (FLAG) [désactivé par défaut]"
MSG_HELP_SAMPLE="Mode test : encoder seulement 30s à une position aléatoire (FLAG)"
MSG_HELP_FILE="Convertir un fichier unique (bypass index/queue) (ARG)"
MSG_HELP_AUDIO="Codec audio cible : copy, aac, ac3, eac3, opus (ARG) [défaut : aac]"
MSG_HELP_AUDIO_HINT="Multi-channel (5.1+) : cible par défaut = EAC3 384k\n                                 AAC en multi-channel : uniquement avec -a aac --force-audio"
MSG_HELP_TWO_PASS="Forcer le mode two-pass (défaut : single-pass CRF 21 pour séries)"
MSG_HELP_CODEC="Codec vidéo cible : hevc, av1 (ARG) [défaut : hevc]"
MSG_HELP_OFF_PEAK="Mode heures creuses : traitement uniquement pendant les heures creuses"
MSG_HELP_OFF_PEAK_HINT="PLAGE au format HH:MM-HH:MM (ARG optionnel) [défaut : 22:00-06:00]"
MSG_HELP_FORCE_AUDIO="Forcer la conversion audio vers le codec cible (bypass smart codec)"
MSG_HELP_FORCE_VIDEO="Forcer le réencodage vidéo (bypass smart codec)"
MSG_HELP_FORCE="Raccourci pour --force-audio et --force-video"
MSG_HELP_NO_LOSSLESS="Convertir les codecs lossless/premium (DTS/DTS-HD/TrueHD/FLAC)"
MSG_HELP_NO_LOSSLESS_HINT="Stéréo → codec cible, Multi-channel → EAC3 384k 5.1"
MSG_HELP_EQUIV_QUALITY="Activer le mode \"qualité équivalente\" (audio + cap vidéo)"
MSG_HELP_NO_EQUIV_QUALITY="Désactiver le mode \"qualité équivalente\" (audio + cap vidéo)"
MSG_HELP_EQUIV_QUALITY_HINT="Ignoré en mode adaptatif (reste activé)"
MSG_HELP_LANG="Langue de l'interface : fr, en (ARG) [défaut : fr]"

MSG_HELP_SHORT_OPTIONS_TITLE="Remarque sur les options courtes groupées :"
MSG_HELP_SHORT_OPTIONS_DESC="Les options courtes peuvent être groupées lorsque ce sont des flags (sans argument),\n        par exemple : -xdrk est équivalent à -x -d -r -k."
MSG_HELP_SHORT_OPTIONS_ARG="Les options qui attendent un argument (marquées (ARG) ci-dessus : -s, -o, -e, -m, -l, -j, -q)\n        doivent être fournies séparément avec leur valeur, par exemple : -l 5 ou --limit 5."
MSG_HELP_SHORT_OPTIONS_EXAMPLE="par exemple : ./conversion.sh -xdrk -l 5  (groupement de flags puis -l 5 séparé),\n                      ./conversion.sh --source /path --limit 10."

MSG_HELP_SMART_CODEC_TITLE="Logique Smart Codec (audio) :"
MSG_HELP_SMART_CODEC_DESC="Par défaut, si la source a un codec audio plus efficace que la cible, il est conservé.\n  Hiérarchie (du meilleur au moins bon) : Opus > AAC > E-AC3 > AC3\n  Le bitrate est limité selon le codec effectif (ex: Opus max 128k, AAC max 160k).\n  Utilisez --force-audio pour toujours convertir vers le codec cible."

MSG_HELP_MODES_TITLE="Modes de conversion :"
MSG_HELP_MODE_FILM="Qualité maximale (two-pass ABR, bitrate fixe)"
MSG_HELP_MODE_ADAPTATIF="Bitrate adaptatif par fichier selon complexité (CRF contraint)"
MSG_HELP_MODE_SERIE="Bon compromis taille/qualité [défaut]"

MSG_HELP_OFF_PEAK_TITLE="Mode heures creuses :"
MSG_HELP_OFF_PEAK_DESC="Limite le traitement aux périodes définies (par défaut 22h-6h).\n  Si un fichier est en cours quand les heures pleines arrivent, il termine.\n  Le script attend ensuite le retour des heures creuses avant de continuer."

MSG_HELP_EXAMPLES_TITLE="Exemples :"

###########################################################
# AVERTISSEMENTS GÉNÉRIQUES
###########################################################

MSG_WARN_VMAF_DRYRUN="VMAF désactivé en mode dry-run"
MSG_WARN_SAMPLE_DRYRUN="Mode sample ignoré en mode dry-run"

###########################################################
# UI OPTIONS (lib/ui_options.sh)
###########################################################

MSG_UI_OPT_ACTIVE_PARAMS="Paramètres actifs"
MSG_UI_OPT_VMAF_ENABLED="Évaluation VMAF activée"
MSG_UI_OPT_LIMIT="LIMITATION"
MSG_UI_OPT_RANDOM_MODE="Mode aléatoire : activé"
MSG_UI_OPT_SORT_RANDOM="aléatoire (sélection)"
MSG_UI_OPT_SORT_SIZE_DESC="taille décroissante"
MSG_UI_OPT_SORT_SIZE_ASC="taille croissante"
MSG_UI_OPT_SORT_NAME_ASC="nom ascendant"
MSG_UI_OPT_SORT_NAME_DESC="nom descendant"
MSG_UI_OPT_SORT_QUEUE="Tri de la queue"
MSG_UI_OPT_SAMPLE="Mode échantillon : 30s à position aléatoire"
MSG_UI_OPT_DRYRUN="Mode dry-run : simulation sans conversion"
MSG_UI_OPT_VIDEO_CODEC="Codec vidéo"
MSG_UI_OPT_AUDIO_CODEC="Codec audio"
MSG_UI_OPT_SOURCE="Source"
MSG_UI_OPT_DEST="Destination"
MSG_UI_OPT_FILE_COUNT="Compteur de fichiers à traiter"
MSG_UI_OPT_HFR_LIMITED="Vidéos HFR : limitées à %s fps"
MSG_UI_OPT_HFR_BITRATE="Vidéos HFR : bitrate ajusté (fps original conservé)"

###########################################################
# UI MESSAGES (lib/ui.sh)
###########################################################

MSG_UI_DOWNLOAD_TEMP="Téléchargement vers dossier temporaire"
MSG_UI_FILES_INDEXED="%d fichiers indexés"
MSG_UI_SUMMARY_TITLE="RÉSUMÉ DE CONVERSION"
MSG_UI_TRANSFERS_DONE="Tous les transferts terminés"
MSG_UI_VMAF_DONE="Analyses VMAF terminées"
MSG_UI_VMAF_TITLE="ANALYSE VMAF"
MSG_UI_CONVERSIONS_DONE="Toutes les conversions terminées"
MSG_UI_SKIP_NO_VIDEO="SKIPPED (Pas de flux vidéo)"
MSG_UI_SKIP_EXISTS="SKIPPED (Fichier de sortie déjà existant)"
MSG_UI_SKIP_HEAVIER_EXISTS="SKIPPED (Sortie 'Heavier' déjà existante)"
MSG_UI_VIDEO_PASSTHROUGH="Audio à optimiser"
MSG_UI_REENCODE_BITRATE="Bitrate trop élevé"
MSG_UI_CONVERSION_AUDIO_ONLY="Conversion requise : audio à optimiser (vidéo conservée)"
MSG_UI_NO_CONVERSION="Pas de conversion nécessaire"
MSG_UI_DOWNSCALE="Downscale activé : %sx%s → Max %sx%s"
MSG_UI_10BIT="Sortie 10-bit activée"
MSG_UI_AUDIO_DOWNMIX="Audio multicanal (%sch) → Downmix stéréo"
MSG_UI_AUDIO_KEEP_LAYOUT="Audio multicanal 5.1 (%sch) → Layout conservé (pas de downmix stéréo)"
MSG_UI_VIDEO_OPTIMIZED="Codec vidéo déjà optimisé → Conversion audio seule"
MSG_UI_START_FILE="Démarrage du fichier"
MSG_UI_FILES_TO_PROCESS="%s fichier(s) à traiter"
MSG_UI_INDEXING="Indexation"
MSG_UI_FILES="fichiers"
MSG_UI_PROGRESS_PROCESSING="Traitement en cours"
MSG_UI_REASON_NO_VIDEO="Pas de flux vidéo"
MSG_UI_REASON_ALREADY_OPTIMIZED="Déjà %s & bitrate optimisé"
MSG_UI_REASON_ALREADY_OPTIMIZED_ADAPTIVE="Déjà %s & bitrate optimisé (adaptatif)"
MSG_UI_CONVERSION_REQUIRED="Conversion requise"
MSG_UI_CONVERSION_REQUIRED_CODEC="Conversion requise : codec %s → %s (source : %s kbps)"
MSG_UI_CONVERSION_REQUIRED_BITRATE="Conversion requise : bitrate %s kbps (%s) > %s kbps (%s)"
MSG_UI_CONVERSION_REQUIRED_BITRATE_NO_DOWNGRADE="Conversion non requise : bitrate %s kbps (%s) ≤ %s kbps (%s) (pas de downgrade pour %s)"
MSG_UI_FILES_PENDING="%s fichier(s) en attente"
MSG_UI_FILES_TO_ANALYZE="%s fichier(s) à analyser"

###########################################################
# SUMMARY (lib/summary.sh)
###########################################################

MSG_SUMMARY_TITLE="Résumé"
MSG_SUMMARY_DURATION="Durée"
MSG_SUMMARY_RESULT="Résultat"
MSG_SUMMARY_ANOMALIES="Anomalies"
MSG_SUMMARY_SPACE="Espace"
MSG_SUMMARY_NO_FILES="Aucun fichier à traiter"
MSG_SUMMARY_END_DATE_LABEL="Date fin"
MSG_SUMMARY_TOTAL_DURATION_LABEL="Durée totale"
MSG_SUMMARY_SUCCESS_LABEL="Succès"
MSG_SUMMARY_SKIPPED_LABEL="Ignorés"
MSG_SUMMARY_ERRORS_LABEL="Erreurs"
MSG_SUMMARY_ANOMALIES_TITLE="Anomalies"
MSG_SUMMARY_ANOM_SIZE_LABEL="Taille"
MSG_SUMMARY_ANOM_INTEGRITY_LABEL="Intégrité"
MSG_SUMMARY_ANOM_VMAF_LABEL="VMAF"
MSG_SUMMARY_SPACE_SAVED_LABEL="Espace économisé"

###########################################################
# COMPLEXITY (lib/complexity.sh)
###########################################################

MSG_COMPLEX_ANALYZING="Analyse de complexité du fichier"
MSG_COMPLEX_RESULTS="Résultats d'analyse"
MSG_COMPLEX_SPATIAL="Complexité spatiale (SI)"
MSG_COMPLEX_TEMPORAL="Complexité temporelle (TI)"
MSG_COMPLEX_VALUE="Complexité (C)"
MSG_COMPLEX_PROGRESS_RUNNING="Calcul en cours..."
MSG_COMPLEX_PROGRESS_DONE="Calcul terminé"
MSG_COMPLEX_SITI_RUNNING="Analyse SI/TI..."
MSG_COMPLEX_SITI_DONE="SI/TI terminé"
MSG_COMPLEX_STDDEV_LABEL="Coefficient de variation (stddev)"
MSG_COMPLEX_TARGET_BITRATE_LABEL="Bitrate cible (encodage)"
MSG_COMPLEX_DESC_STATIC="statique → scène simple, peu de mouvement, facile à compresser"
MSG_COMPLEX_DESC_STANDARD="standard → mouvement normal, compressibilité moyenne"
MSG_COMPLEX_DESC_COMPLEX="complexe → beaucoup de mouvement/détails, plus difficile à compresser"

###########################################################
# TRANSFERT (lib/transfer.sh)
###########################################################

MSG_TRANSFER_REMAINING="%s transfert(s) restant(s)..."
MSG_TRANSFER_BG_STARTED="Transfert lancé en arrière-plan"
MSG_TRANSFER_WAIT="Attente fin de transfert... (%s en cours)"
MSG_TRANSFER_SLOT_AVAILABLE="Slot de transfert disponible"

###########################################################
# OFF-PEAK (lib/off_peak.sh) - compléments
###########################################################

MSG_OFF_PEAK_WAIT_PERIODS="Périodes d'attente"
MSG_OFF_PEAK_TOTAL="total"
MSG_OFF_PEAK_MODE_TITLE="MODE HEURES CREUSES ACTIVÉ"
MSG_OFF_PEAK_STATUS="Statut"
MSG_OFF_PEAK_IMMEDIATE="Heures creuses - démarrage immédiat"
MSG_OFF_PEAK_MODE_LABEL="Mode heures creuses"
MSG_OFF_PEAK_RANGE_LABEL="Plage horaire"
MSG_OFF_PEAK_STATUS_ACTIVE="Heures creuses (actif)"
MSG_OFF_PEAK_STATUS_WAIT="Heures pleines (attente ~%s)"
MSG_OFF_PEAK_DETECTED="Heures pleines détectées (%s = heures creuses)"
MSG_OFF_PEAK_WAIT_EST="Attente estimée : %s (reprise à %s)"
MSG_OFF_PEAK_CHECK_INTERVAL="Vérification toutes les %ss... (Ctrl+C pour annuler)"
MSG_OFF_PEAK_REMAINING="Temps restant estimé : %s"
MSG_OFF_PEAK_RESUME="Heures creuses ! Reprise du traitement (attendu %s)"

###########################################################
# NOTIFY FORMAT (lib/notify_format.sh)
###########################################################

MSG_NOTIFY_FILE_START="Démarrage du fichier"
MSG_NOTIFY_CONV_DONE="Conversion terminée en"
MSG_NOTIFY_TRANSFERS_DONE="Transferts terminés"
MSG_NOTIFY_ANALYSIS_START="Début d'analyse"
MSG_NOTIFY_ANALYSIS_STARTED="Analyse de complexité…"
MSG_NOTIFY_DISABLED="désactivé"
MSG_NOTIFY_SUMMARY_TITLE="Résumé"
MSG_NOTIFY_END_LABEL="Fin"
MSG_NOTIFY_DURATION_LABEL="Durée"
MSG_NOTIFY_RESULTS_LABEL="Résultats"
MSG_NOTIFY_SUCCESS_LABEL="Succès"
MSG_NOTIFY_SKIPPED_LABEL="Ignorés"
MSG_NOTIFY_ERRORS_LABEL="Erreurs"
MSG_NOTIFY_ANOMALIES_LABEL="Anomalies"
MSG_NOTIFY_ANOM_SIZE_LABEL="Taille"
MSG_NOTIFY_ANOM_INTEGRITY_LABEL="Intégrité"
MSG_NOTIFY_ANOM_VMAF_LABEL="VMAF"
MSG_NOTIFY_SPACE_SAVED_LABEL="Espace économisé"
MSG_NOTIFY_SESSION_DONE_OK="Session terminée"
MSG_NOTIFY_SESSION_DONE_INTERRUPTED="Session interrompue"
MSG_NOTIFY_SESSION_DONE_ERROR="Session en erreur (code %s)"
MSG_NOTIFY_SKIPPED_TITLE="Ignoré"
MSG_NOTIFY_REASON_LABEL="Raison"
MSG_NOTIFY_RUN_TITLE="Exécution"
MSG_NOTIFY_START_LABEL="Début"
MSG_NOTIFY_ACTIVE_PARAMS_LABEL="Paramètres actifs"
MSG_NOTIFY_MODE_LABEL="Mode"
MSG_NOTIFY_SOURCE_LABEL="Source"
MSG_NOTIFY_DEST_LABEL="Destination"
MSG_NOTIFY_VIDEO_CODEC_LABEL="Codec vidéo"
MSG_NOTIFY_AUDIO_CODEC_LABEL="Codec audio"
MSG_NOTIFY_HFR_LABEL="HFR"
MSG_NOTIFY_HFR_LIMITED="Limité à %s fps"
MSG_NOTIFY_HFR_ADJUSTED="Bitrate ajusté (fps original conservé)"
MSG_NOTIFY_LIMIT_LABEL="Limite"
MSG_NOTIFY_LIMIT_MAX="max %s"
MSG_NOTIFY_DRYRUN_LABEL="Dry-run"
MSG_NOTIFY_SAMPLE_LABEL="Mode sample"
MSG_NOTIFY_VMAF_LABEL="VMAF"
MSG_NOTIFY_OFF_PEAK_LABEL="Heures creuses"
MSG_NOTIFY_JOBS_LABEL="Jobs parallèles"
MSG_NOTIFY_QUEUE_TITLE="File d'attente"
MSG_NOTIFY_CONV_LAUNCH="Lancement de la conversion"
MSG_NOTIFY_SPEED_LABEL="Vitesse"
MSG_NOTIFY_ETA_LABEL="Durée estimée"
MSG_NOTIFY_FILES_COUNT="%s fichiers"
MSG_NOTIFY_TRANSFERS_PENDING="Transferts en attente"
MSG_NOTIFY_VMAF_STARTED_TITLE="VMAF démarré"
MSG_NOTIFY_FILES_LABEL="Fichiers"
MSG_NOTIFY_FILE_LABEL="Fichier"
MSG_NOTIFY_VMAF_DONE_TITLE="VMAF terminé"
MSG_NOTIFY_VMAF_ANALYZED_LABEL="Analysés"
MSG_NOTIFY_VMAF_AVG_LABEL="Moyenne"
MSG_NOTIFY_VMAF_MINMAX_LABEL="Min / Max"
MSG_NOTIFY_VMAF_DEGRADED_LABEL="Dégradés"
MSG_NOTIFY_VMAF_WORST_LABEL="Pires fichiers"
MSG_NOTIFY_PEAK_PAUSE_TITLE="Pause (heures pleines)"
MSG_NOTIFY_PEAK_RESUME_TITLE="Reprise (heures creuses)"
MSG_NOTIFY_OFF_PEAK_RANGE_LABEL="Plage heures creuses"
MSG_NOTIFY_WAIT_ESTIMATED_LABEL="Attente estimée"
MSG_NOTIFY_RESUME_AT_LABEL="Reprise à"
MSG_NOTIFY_CHECK_EVERY_LABEL="Vérifier toutes les"
MSG_NOTIFY_SECONDS="%ss"
MSG_NOTIFY_WAIT_ACTUAL_LABEL="Attente réelle"
MSG_NOTIFY_RUN_END_OK="Fin"
MSG_NOTIFY_RUN_END_INTERRUPTED="Interrompu"
MSG_NOTIFY_RUN_END_ERROR="Erreur (code %s)"

###########################################################
# FFMPEG PIPELINE (lib/ffmpeg_pipeline.sh) - compléments
###########################################################

MSG_FFMPEG_SEGMENT="Segment de %ss à partir de %s"

###########################################################
# FINALIZE (lib/finalize.sh) - compléments
###########################################################

MSG_FINAL_GENERATED="GÉNÉRÉ"
MSG_FINAL_ANOMALY_COUNT="%d ANOMALIE(S) de nommage trouvée(s)."
MSG_FINAL_ANOMALY_HINT="Veuillez vérifier les caractères spéciaux ou les problèmes d'encodage pour ces fichiers."
MSG_FINAL_NO_ANOMALY="Aucune anomalie de nommage détectée."
MSG_FINAL_COMPARE_IGNORED="Comparaison des noms ignorée."
MSG_FINAL_FFMPEG_ERROR="Erreur détaillée FFMPEG"
MSG_FINAL_INTERRUPTED="INTERRUPTED"
MSG_FINAL_TEMP_KEPT="fichier temp conservé"
MSG_FINAL_TEMP_MISSING="fichier temp absent"
MSG_FINAL_CONV_DONE="Conversion terminée en %s"
MSG_FINAL_SHOW_COMPARISON="Afficher la comparaison des noms de fichiers originaux et générés ?"
MSG_LOG_HEAVIER_FILE="FICHIER PLUS LOURD"
MSG_LOG_DISK_SPACE="Espace disque insuffisant dans %s (%s MB libres)"
MSG_FINAL_FILENAME_SIM_TITLE="SIMULATION DES NOMS DE FICHIERS"

###########################################################
# QUEUE (lib/queue.sh) - compléments
###########################################################

MSG_QUEUE_NO_FILES="Aucun fichier à traiter trouvé (vérifiez les filtres ou la source)."
MSG_QUEUE_RANDOM_SELECTED="Fichiers sélectionnés aléatoirement"

###########################################################
# TRANSCODE VIDEO (lib/transcode_video.sh) - compléments
###########################################################

MSG_TRANSCODE_FFMPEG_LOG="Dernières lignes du log ffmpeg (%s)"
