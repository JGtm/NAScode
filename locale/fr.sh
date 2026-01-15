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
# SYSTÈME / DÉPENDANCES (lib/system.sh)
###########################################################

MSG_SYS_DEPS_MISSING="Dépendances manquantes : %s"
MSG_SYS_FFMPEG_VERSION_UNKNOWN="Impossible de déterminer la version de ffmpeg."
MSG_SYS_FFMPEG_VERSION_OLD="Version FFMPEG (%s) < Recommandée (%s)"
MSG_SYS_FFMPEG_VERSION_DETECTED="Version ffmpeg détectée : %s"
MSG_SYS_SOURCE_NOT_FOUND="Source '%s' introuvable."
MSG_SYS_SUFFIX_FORCED="Utilisation forcée du suffixe de sortie : %s"
MSG_SYS_SUFFIX_DISABLED="Suffixe de sortie désactivé"
MSG_SYS_SUFFIX_CONTINUE_NO_SUFFIX="Continuation SANS suffixe. Vérifiez le Dry Run ou les logs."
MSG_SYS_SUFFIX_CANCELLED="Opération annulée. Modifiez le suffixe ou le dossier de sortie."
MSG_SYS_VMAF_NOT_AVAILABLE="VMAF demandé mais libvmaf non disponible dans FFmpeg"

###########################################################
# QUEUE / INDEX (lib/queue.sh, lib/index.sh)
###########################################################

MSG_QUEUE_FILE_NOT_FOUND="ERREUR : Le fichier queue '%s' n'existe pas."
MSG_QUEUE_FILE_EMPTY="Le fichier queue est vide"
MSG_QUEUE_FORMAT_INVALID="Format du fichier queue invalide (séparateur NUL attendu)"
MSG_INDEX_REGEN_FORCED="Régénération forcée de l'index demandée."
MSG_INDEX_NO_META="Pas de métadonnées pour l'index existant, régénération..."
MSG_INDEX_SOURCE_NOT_IN_META="Source non trouvée dans les métadonnées, régénération..."
MSG_INDEX_SOURCE_CHANGED="La source a changé, régénération automatique de l'index."
MSG_INDEX_SOURCE_CHANGED_DETAIL="La source a changé :"
MSG_INDEX_REGEN_AUTO="Régénération automatique de l'index..."
MSG_INDEX_EMPTY="Index vide, régénération nécessaire..."

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

###########################################################
# VMAF (lib/vmaf.sh)
###########################################################

MSG_VMAF_FPS_IGNORED="VMAF ignoré (FPS modifié: %s → %s)"

###########################################################
# CONFIGURATION (lib/config.sh)
###########################################################

MSG_CFG_UNKNOWN_MODE="Mode de conversion inconnu : %s"
MSG_CFG_ENCODER_INVALID="Configuration codec invalide. Vérifiez que FFmpeg supporte l'encodeur %s."

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

###########################################################
# SUMMARY (lib/summary.sh)
###########################################################

MSG_SUMMARY_TITLE="Résumé"
MSG_SUMMARY_DURATION="Durée"
MSG_SUMMARY_RESULT="Résultat"
MSG_SUMMARY_ANOMALIES="Anomalies"
MSG_SUMMARY_SPACE="Espace"

###########################################################
# COMPLEXITY (lib/complexity.sh)
###########################################################

MSG_COMPLEX_ANALYZING="Analyse de complexité du fichier"
MSG_COMPLEX_RESULTS="Résultats d'analyse"
MSG_COMPLEX_SPATIAL="Complexité spatiale (SI)"
MSG_COMPLEX_TEMPORAL="Complexité temporelle (TI)"
MSG_COMPLEX_VALUE="Complexité (C)"

###########################################################
# OFF-PEAK (lib/off_peak.sh) - compléments
###########################################################

MSG_OFF_PEAK_WAIT_PERIODS="Périodes d'attente"
MSG_OFF_PEAK_TOTAL="total"
MSG_OFF_PEAK_MODE_TITLE="MODE HEURES CREUSES ACTIVÉ"
MSG_OFF_PEAK_STATUS="Statut"
MSG_OFF_PEAK_IMMEDIATE="Heures creuses - démarrage immédiat"

###########################################################
# NOTIFY FORMAT (lib/notify_format.sh)
###########################################################

MSG_NOTIFY_FILE_START="Démarrage du fichier"
MSG_NOTIFY_CONV_DONE="Conversion terminée en"
MSG_NOTIFY_TRANSFERS_DONE="Transferts terminés"
MSG_NOTIFY_ANALYSIS_START="Début d'analyse"
MSG_NOTIFY_DISABLED="désactivé"

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

###########################################################
# QUEUE (lib/queue.sh) - compléments
###########################################################

MSG_QUEUE_NO_FILES="Aucun fichier à traiter trouvé (vérifiez les filtres ou la source)."
MSG_QUEUE_RANDOM_SELECTED="Fichiers sélectionnés aléatoirement"

###########################################################
# TRANSCODE VIDEO (lib/transcode_video.sh) - compléments
###########################################################

MSG_TRANSCODE_FFMPEG_LOG="Dernières lignes du log ffmpeg (%s)"
