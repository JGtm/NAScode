#!/bin/bash

###########################################################
# SCRIPT DE CONVERSION VIDÉO LIBX265
# Version modulaire - Point d'entrée principal
###########################################################
# 
# Ce script convertit des fichiers vidéo en HEVC/x265 avec
# encodage two-pass pour une taille prévisible (~1,1 Go/h).
#
# Architecture modulaire :
#   lib/colors.sh     - Codes couleurs ANSI
#   lib/config.sh     - Configuration globale et paramètres
#   lib/utils.sh      - Fonctions utilitaires (MD5, timestamps, etc.)
#   lib/logging.sh    - Gestion des logs et répertoires
#   lib/lock.sh       - Gestion des verrous et cleanup
#   lib/system.sh     - Vérifications système et dépendances
#   lib/args.sh       - Parsing des arguments CLI
#   lib/queue.sh      - Construction et gestion de la file d'attente
#   lib/progress.sh   - Système de slots pour progression parallèle
#   lib/media_probe.sh - Propriétés média (ffprobe)
#   lib/transcode_video.sh - Transcodage vidéo (x265, 10-bit/downscale)
#   lib/conversion.sh - Logique de conversion FFmpeg
#   lib/processing.sh - Traitement parallèle et FIFO
#   lib/vmaf.sh       - Analyse VMAF (qualité vidéo)
#   lib/finalize.sh   - Finalisation et résumé
#   lib/exports.sh    - Export des fonctions/variables pour sous-shells
#
###########################################################

set -euo pipefail

###########################################################
# DÉTERMINATION DU RÉPERTOIRE DU SCRIPT
###########################################################

# Le SCRIPT_DIR est le répertoire contenant ce script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

###########################################################
# CHARGEMENT DES MODULES
###########################################################

# Vérifier que le répertoire lib existe
if [[ ! -d "$LIB_DIR" ]]; then
    echo "ERREUR : Répertoire lib introuvable : $LIB_DIR"
    echo "Assurez-vous que tous les modules sont présents dans le dossier lib/"
    exit 1
fi

# Charger les modules dans l'ordre des dépendances
source "$LIB_DIR/colors.sh"      # Codes couleurs (pas de dépendances)
source "$LIB_DIR/config.sh"      # Configuration (dépend de colors pour erreurs)
source "$LIB_DIR/utils.sh"       # Utilitaires (dépend de config pour HAS_*)
source "$LIB_DIR/logging.sh"     # Logs (dépend de config pour EXECUTION_TIMESTAMP)
source "$LIB_DIR/progress.sh"    # Slots progression (dépend de config pour EXECUTION_TIMESTAMP)
source "$LIB_DIR/lock.sh"        # Verrous (dépend de colors, config)
source "$LIB_DIR/system.sh"      # Système (dépend de colors, config, utils)
source "$LIB_DIR/args.sh"        # Arguments (dépend de colors, config)
source "$LIB_DIR/queue.sh"       # Queue (dépend de colors, config, utils, logging)
source "$LIB_DIR/vmaf.sh"        # VMAF (dépend de colors, config, utils, logging)
source "$LIB_DIR/media_probe.sh" # Propriétés média (dépend de utils)
source "$LIB_DIR/transcode_video.sh" # Transcodage vidéo (dépend de media_probe, config)
source "$LIB_DIR/conversion.sh"  # Conversion (dépend de tout sauf finalize)
source "$LIB_DIR/processing.sh"  # Traitement (dépend de conversion, queue)
source "$LIB_DIR/finalize.sh"    # Finalisation (dépend de colors, config, utils, vmaf)
source "$LIB_DIR/transfer.sh"    # Transferts asynchrones (dépend de finalize, config)
source "$LIB_DIR/exports.sh"     # Exports (dépend de tout)

###########################################################
# FONCTION PRINCIPALE
###########################################################

main() {
    # Configurer les traps pour le nettoyage
    setup_traps

    # Chrono global (temps total d'exécution du script)
    # Défini une seule fois, et utilisé dans le résumé final.
    if [[ -z "${START_TS_TOTAL:-}" ]]; then
        START_TS_TOTAL="$(date +%s)"
    fi
    
    # Parser les arguments de la ligne de commande
    parse_arguments "$@"
    
    # Configurer les paramètres selon le mode de conversion
    set_conversion_mode_parameters
    
    # Convertir SOURCE en chemin absolu pour éviter les problèmes de répertoire courant
    SOURCE=$(cd "$SOURCE" && pwd)
    
    # Vérifications initiales
    check_lock
    check_dependencies
    initialize_directories
    
    # Initialiser le système de transferts asynchrones
    init_async_transfers
    
    # Vérifications interactives
    check_plexignore
    check_output_suffix
    
    # Détecter le hwaccel avant d'indexer / construire la queue
    detect_hwaccel

    # Vérifier si VMAF est activé et disponible
    check_vmaf

    # Construire la file d'attente
    build_queue
    
    # Exporter les variables et fonctions pour les sous-shells
    export_variables

    # Préparer la queue dynamique, lancer le traitement et attendre la fin
    prepare_dynamic_queue

    # Attendre la fin de tous les transferts en cours
    cleanup_transfers

    # Afficher le résumé final
    if [[ "$DRYRUN" == true ]]; then
        echo -e "${GREEN}Dry run terminé${NOCOLOR}"
        dry_run_compare_names
    else
        show_summary
    fi
}

###########################################################
# POINT D'ENTRÉE
###########################################################

main "$@"
