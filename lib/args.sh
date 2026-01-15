#!/bin/bash
# shellcheck disable=SC2034
###########################################################
# PARSING DES ARGUMENTS
#
# NOTE: Ce module n'active pas `set -euo pipefail` car :
# 1. Le point d'entrée (nascode) l'active globalement
# 2. Le parsing peut utiliser des variables non définies
#    avec des valeurs par défaut (${2:-})
# 3. Les modules sont sourcés, pas exécutés directement
###########################################################

_args_require_value() {
    local opt="$1"
    local val="${2:-}"
    if [[ -z "$val" ]]; then
        print_error "$(msg MSG_ARG_REQUIRES_VALUE "$opt")"
        exit 1
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source) 
                _args_require_value "$1" "${2:-}"
                SOURCE="$2"
                shift 2 
                ;;
            -o|--output-dir) 
                _args_require_value "$1" "${2:-}"
                OUTPUT_DIR="$2"
                shift 2 
                ;;
            -e|--exclude) 
                _args_require_value "$1" "${2:-}"
                EXCLUDES+=("$2")
                shift 2 
                ;;
            -m|--mode) 
                _args_require_value "$1" "${2:-}"
                CONVERSION_MODE="$2"
                shift 2 
                ;;
            -d|--dry-run|--dryrun) 
                DRYRUN=true
                shift 
                ;;
            -x|--no-suffix) 
                SUFFIX_MODE="off"
                shift 
                ;;
            -r|--random)
                RANDOM_MODE=true
                shift
                ;;
            -l|--limit)
                if [[ "${2:-}" =~ ^[0-9]+$ ]] && [[ "$2" -gt 0 ]]; then
                    LIMIT_FILES="$2"
                    shift 2
                else
                    print_error "$(msg MSG_ARG_LIMIT_POSITIVE)"
                    exit 1
                fi
                ;;
            --min-size)
                if [[ -z "${2:-}" ]]; then
                    print_error "$(msg MSG_ARG_MIN_SIZE_REQUIRED)"
                    exit 1
                fi
                if ! MIN_SIZE_BYTES=$(parse_human_size_to_bytes "$2"); then
                    print_error "$(msg MSG_ARG_MIN_SIZE_INVALID "$2")"
                    exit 1
                fi
                shift 2
                ;;
            -q|--queue)
                _args_require_value "$1" "${2:-}"
                if [[ -f "$2" ]]; then
                    CUSTOM_QUEUE="$2"
                    shift 2
                else
                    print_error "$(msg MSG_ARG_QUEUE_NOT_FOUND "$2")"
                    exit 1
                fi
                ;;
            -n|--no-progress)
                NO_PROGRESS=true
                shift
                ;;
            -Q|--quiet)
                # Mode silencieux : limiter l'affichage aux warnings/erreurs
                UI_QUIET=true
                NO_PROGRESS=true
                shift
                ;;
            --lang)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        fr|en)
                            LANG_UI="$2"
                            _i18n_load "$2"
                            ;;
                        *)
                            print_error "$(msg MSG_ARG_LANG_INVALID "$2")"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    print_error "$(msg MSG_ARG_REQUIRES_VALUE "--lang")"
                    exit 1
                fi
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -k|--keep-index)
                KEEP_INDEX=true
                shift
                ;;
            -R|--regenerate-index)
                REGENERATE_INDEX=true
                shift
                ;;
            -S|--suffix)
                # Si un argument suit et ne commence pas par tiret, c'est le suffixe personnalisé
                if [[ -n "${2:-}" ]] && [[ "${2:0:1}" != "-" ]]; then
                    SUFFIX_MODE="custom:$2"
                    shift 2
                else
                    # Sinon, on active le suffixe dynamique (bypass la question interactive)
                    SUFFIX_MODE="on"
                    shift
                fi
                ;;
            -v|--vmaf)
                VMAF_ENABLED=true
                shift
                ;;
            -t|--sample|--test)
                SAMPLE_MODE=true
                shift
                ;;
            -f|--file)
                _args_require_value "$1" "${2:-}"
                if [[ -f "$2" ]]; then
                    SINGLE_FILE="$2"
                    shift 2
                else
                    print_error "$(msg MSG_ARG_FILE_NOT_FOUND "$2")"
                    exit 1
                fi
                ;;
            -a|--audio)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        copy|aac|ac3|eac3|opus)
                            AUDIO_CODEC="$2"
                            ;;
                        *)
                            print_error "$(msg MSG_ARG_AUDIO_INVALID "$2")"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    print_error "$(msg MSG_ARG_AUDIO_REQUIRES_VALUE)"
                    exit 1
                fi
                ;;
            -2|--two-pass)
                SINGLE_PASS_MODE=false
                shift
                ;;
            -c|--codec)
                if [[ -n "${2:-}" ]]; then
                    case "$2" in
                        hevc|av1)
                            VIDEO_CODEC="$2"
                            ;;
                        *)
                            print_error "$(msg MSG_ARG_CODEC_INVALID "$2")"
                            exit 1
                            ;;
                    esac
                    shift 2
                else
                    print_error "$(msg MSG_ARG_CODEC_REQUIRES_VALUE)"
                    exit 1
                fi
                ;;
            -j|--jobs)
                if [[ "${2:-}" =~ ^[0-9]+$ ]] && [[ "$2" -ge 1 ]]; then
                    PARALLEL_JOBS="$2"
                    shift 2
                else
                    print_error "$(msg MSG_ARG_LIMIT_MIN_ONE)"
                    exit 1
                fi
                ;;
            -p|--off-peak|--off-peak=*)
                OFF_PEAK_ENABLED=true
                # Vérifier si une plage horaire est fournie (format --off-peak=HH:MM-HH:MM)
                if [[ "$1" == *"="* ]]; then
                    local range="${1#*=}"
                    if ! parse_off_peak_range "$range"; then
                        print_error "$(msg MSG_ARG_OFF_PEAK_INVALID)"
                        exit 1
                    fi
                    shift
                elif [[ "${2:-}" =~ ^[0-9]{1,2}:[0-9]{2}-[0-9]{1,2}:[0-9]{2}$ ]]; then
                    # Format : --off-peak 22:00-06:00 (avec espace)
                    if ! parse_off_peak_range "$2"; then
                        print_error "$(msg MSG_ARG_OFF_PEAK_INVALID)"
                        exit 1
                    fi
                    shift 2
                else
                    # Pas de plage fournie, utiliser les valeurs par défaut
                    shift
                fi
                ;;
            --force-audio)
                FORCE_AUDIO_CODEC=true
                shift
                ;;
            --force-video)
                FORCE_VIDEO_CODEC=true
                shift
                ;;
            --force)
                # Raccourci pour forcer les deux
                FORCE_AUDIO_CODEC=true
                FORCE_VIDEO_CODEC=true
                shift
                ;;
            --no-lossless)
                # Force la conversion des codecs lossless/premium (DTS/DTS-HD/TrueHD/FLAC)
                NO_LOSSLESS=true
                shift
                ;;
            --equiv-quality)
                # Switch global : active le mode "qualité équivalente" (audio + cap vidéo).
                # NOTE : ignoré en mode adaptatif (reste activé).
                EQUIV_QUALITY_OVERRIDE=true
                shift
                ;;
            --no-equiv-quality)
                # Switch global : désactive le mode "qualité équivalente" (audio + cap vidéo).
                # NOTE : ignoré en mode adaptatif (reste activé).
                EQUIV_QUALITY_OVERRIDE=false
                shift
                ;;
            --limit-fps)
                # Force la limitation du FPS à 29.97 pour le contenu HFR (>30fps)
                LIMIT_FPS=true
                shift
                ;;
            --no-limit-fps)
                # Désactive la limitation FPS (garde le FPS original, majore le bitrate)
                LIMIT_FPS=false
                shift
                ;;
            -*) 
                # On vérifie si l'argument est une option courte groupée
                if [[ "$1" =~ ^-[a-zA-Z]{2,}$ ]]; then
                    local flag_to_process="-${1:1:1}" 
                    # remaining_flags = le reste
                    local remaining_flags="-${1:2}" 
                    # Remplacement des arguments :
                    # 1. Le premier argument devient le premier flag à traiter (-x).
                    # 2. Le reste de l'argument groupé est réinséré avant les arguments suivants.
                    set -- "$flag_to_process" "$remaining_flags" "${@:2}"
                    continue # On relance la boucle pour traiter le flag_to_process.
                fi
                # Si ce n'est pas une option groupée ou si ce n'est pas géré, c'est une erreur.
                print_error "$(msg MSG_ARG_UNKNOWN_OPTION "$1")"
                show_help
                exit 1
                ;;
            *)
                # Argument positionnel non reconnu (ni option ni flag)
                print_error "$(msg MSG_ARG_UNEXPECTED "$1")"
                echo -e "  ${DIM}$(msg MSG_ARG_UNEXPECTED_HINT)${NOCOLOR}" >&2
                exit 1
                ;;
        esac
    done

    #if [[ "$OUTPUT_DIR" != /* ]]; then
    #    OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR"
    #fi
    
    # En mode random, appliquer la limite par défaut si aucune limite n'a été spécifiée
    if [[ "$RANDOM_MODE" == true ]] && [[ "$LIMIT_FILES" -eq 0 ]]; then
        LIMIT_FILES=$RANDOM_MODE_DEFAULT_LIMIT
    fi
    
    # Avertissements d'incompatibilités
    if [[ "$DRYRUN" == true ]]; then
        if [[ "$VMAF_ENABLED" == true ]]; then
            print_warning "$(msg MSG_WARN_VMAF_DRYRUN)"
            VMAF_ENABLED=false
        fi
        if [[ "$SAMPLE_MODE" == true ]]; then
            print_warning "$(msg MSG_WARN_SAMPLE_DRYRUN)"
            SAMPLE_MODE=false
        fi
    fi
    
    # Recalculer la regex d'exclusions après avoir potentiellement ajouté des patterns via -e/--exclude.
    # (EXCLUDES_REGEX est initialisée au chargement de config.sh.)
    if declare -f _build_excludes_regex &>/dev/null; then
        EXCLUDES_REGEX="$(_build_excludes_regex)"
    fi
}

###########################################################
# AFFICHAGE DE L'AIDE
###########################################################

show_help() {
    cat << EOF
${CYAN}$(msg MSG_HELP_USAGE)${NOCOLOR} ./nascode [OPTIONS]

${CYAN}$(msg MSG_HELP_OPTIONS)${NOCOLOR}
    ${GREEN}-s, --source${NOCOLOR} DIR             $(msg MSG_HELP_SOURCE)
    ${GREEN}-o, --output-dir${NOCOLOR} DIR         $(msg MSG_HELP_OUTPUT)
    ${GREEN}-e, --exclude${NOCOLOR} PATTERN        $(msg MSG_HELP_EXCLUDE)
    ${GREEN}-m, --mode${NOCOLOR} MODE              $(msg MSG_HELP_MODE)
    ${GREEN}--min-size${NOCOLOR} SIZE              $(msg MSG_HELP_MIN_SIZE)
    ${GREEN}-d, --dry-run${NOCOLOR}                $(msg MSG_HELP_DRYRUN)
    ${GREEN}-S, --suffix${NOCOLOR} [STRING]        $(msg MSG_HELP_SUFFIX)
    ${GREEN}-x, --no-suffix${NOCOLOR}              $(msg MSG_HELP_NO_SUFFIX)
    ${GREEN}-r, --random${NOCOLOR}                 $(msg MSG_HELP_RANDOM)
    ${GREEN}-l, --limit${NOCOLOR} N                $(msg MSG_HELP_LIMIT)
    ${GREEN}-j, --jobs${NOCOLOR} N                 $(msg MSG_HELP_JOBS)
    ${GREEN}-q, --queue${NOCOLOR} FILE             $(msg MSG_HELP_QUEUE)
    ${GREEN}-n, --no-progress${NOCOLOR}            $(msg MSG_HELP_NO_PROGRESS)
    ${GREEN}-Q, --quiet${NOCOLOR}                  $(msg MSG_HELP_QUIET)
    ${GREEN}-h, --help${NOCOLOR}                   $(msg MSG_HELP_HELP)
    ${GREEN}-k, --keep-index${NOCOLOR}             $(msg MSG_HELP_KEEP_INDEX)
    ${GREEN}-R, --regenerate-index${NOCOLOR}       $(msg MSG_HELP_REGEN_INDEX)
    ${GREEN}-v, --vmaf${NOCOLOR}                   $(msg MSG_HELP_VMAF)
    ${GREEN}-t, --sample${NOCOLOR}                 $(msg MSG_HELP_SAMPLE)
    ${GREEN}-f, --file${NOCOLOR} FILE              $(msg MSG_HELP_FILE)
    ${GREEN}-a, --audio${NOCOLOR} CODEC            $(msg MSG_HELP_AUDIO)
                                 ${DIM}$(msg MSG_HELP_AUDIO_HINT)${NOCOLOR}
    ${GREEN}-2, --two-pass${NOCOLOR}               $(msg MSG_HELP_TWO_PASS)
    ${GREEN}-c, --codec${NOCOLOR} CODEC            $(msg MSG_HELP_CODEC)
    ${GREEN}-p, --off-peak${NOCOLOR} [RANGE]       $(msg MSG_HELP_OFF_PEAK)
                                 $(msg MSG_HELP_OFF_PEAK_HINT)
    ${GREEN}--force-audio${NOCOLOR}                $(msg MSG_HELP_FORCE_AUDIO)
    ${GREEN}--force-video${NOCOLOR}                $(msg MSG_HELP_FORCE_VIDEO)
    ${GREEN}--force${NOCOLOR}                      $(msg MSG_HELP_FORCE)
    ${GREEN}--no-lossless${NOCOLOR}                $(msg MSG_HELP_NO_LOSSLESS)
                                 ${DIM}$(msg MSG_HELP_NO_LOSSLESS_HINT)${NOCOLOR}
    ${GREEN}--equiv-quality${NOCOLOR}              $(msg MSG_HELP_EQUIV_QUALITY)
    ${GREEN}--no-equiv-quality${NOCOLOR}           $(msg MSG_HELP_NO_EQUIV_QUALITY)
                                 ${DIM}$(msg MSG_HELP_EQUIV_QUALITY_HINT)${NOCOLOR}
    ${GREEN}--lang${NOCOLOR} LANG                  $(msg MSG_HELP_LANG)

${CYAN}$(msg MSG_HELP_SHORT_OPTIONS_TITLE)${NOCOLOR}
    ${DIM}- $(msg MSG_HELP_SHORT_OPTIONS_DESC)
    - $(msg MSG_HELP_SHORT_OPTIONS_ARG)
        $(msg MSG_HELP_SHORT_OPTIONS_EXAMPLE)${NOCOLOR}

${CYAN}$(msg MSG_HELP_SMART_CODEC_TITLE)${NOCOLOR}
  ${DIM}$(msg MSG_HELP_SMART_CODEC_DESC)${NOCOLOR}

${CYAN}$(msg MSG_HELP_MODES_TITLE)${NOCOLOR}
  ${YELLOW}film${NOCOLOR}          : $(msg MSG_HELP_MODE_FILM)
  ${YELLOW}adaptatif${NOCOLOR}     : $(msg MSG_HELP_MODE_ADAPTATIF)
  ${YELLOW}serie${NOCOLOR}         : $(msg MSG_HELP_MODE_SERIE)

${CYAN}$(msg MSG_HELP_OFF_PEAK_TITLE)${NOCOLOR}
  ${DIM}$(msg MSG_HELP_OFF_PEAK_DESC)${NOCOLOR}

${CYAN}$(msg MSG_HELP_EXAMPLES_TITLE)${NOCOLOR}
  ${DIM}./nascode
  ./nascode -s /media/videos -o /media/converted
  ./nascode --mode film --dry-run
  ./nascode --mode serie --no-progress
  ./nascode --mode film --quiet
  ./nascode -xdrk -l 5
  ./nascode -dnr
  ./nascode --vmaf
  ./nascode --off-peak
  ./nascode -p 23:00-07:00
  ./nascode -f /path/video.mkv
  ./nascode --lang en${NOCOLOR}
EOF
}
