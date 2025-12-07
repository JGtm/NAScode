#!/bin/bash

SOURCE="/mnt/u/The Tudors"
QUEUE="/mnt/e/conversion/convert_queue.txt"

LOG_SUCCESS="/mnt/e/conversion/convert_success.log"
LOG_SKIPPED="/mnt/e/conversion/convert_skipped.log"
LOG_PROGRESS="/mnt/e/conversion/convert_progress.log"

# Compteurs
total_files=0
success_count=0
skipped_bitrate_count=0
error_count=0
processed_count=0
skipped_no_ffprobe_count=0
skipped_x265_count=0

touch "$QUEUE" "$LOG_SUCCESS" "$LOG_SKIPPED" "$LOG_PROGRESS"

echo "" > "$QUEUE"
echo "" > "$LOG_SUCCESS"
echo "" > "$LOG_SKIPPED"
echo "" > "$LOG_PROGRESS"

# ----
# ETAPE 1 : Construire la file d’attente
# ----
> "$QUEUE"

find "$SOURCE" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" \) -size +900M \
| while read -r file; do
    echo "$file" >> "$QUEUE"
    total_files=$((total_files + 1))
done

# ----
# ETAPE 2 : Traitement séquentiel
# ----

while read -r file; do
    [ -z "$file" ] && continue

	echo "$(date "+%Y-%m-%d %H:%M:%S") | $file | START" >> "$LOG_PROGRESS"
	
	relative_path="${file#"$SOURCE"/}"
    dir_path="$(dirname "$relative_path")"
	
	filename="$(basename "$file")"
    base="${filename%.*}"
	
	echo "Fichier : $file"
	echo "RelativePage : $relative_path"
	echo "Dir path : $dir_path"
	echo "Filename : $filename"
	echo "Basename : $basename"
	
	newFile="/mnt/e/conversion/$filename"
	newOutputFile="/mnt/e/conversion/converted_$filename"
	
	echo "New file : $newFile"
	echo "New output file : $newOutputFile"
	
	rsync -ah --progress "$file" "$newFile"
	
	info_video=$(ffprobe -v error -select_streams v:0 \
			-show_entries stream=codec_name,height,bit_rate \
			-of default=noprint_wrappers=1:nokey=1 "$newFile" 2>/dev/null)
	ffprobe_status=$?

	if [ "$ffprobe_status" -ne 0 ] || [ -z "$info_video" ]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (pas de flux vidéo/corrompu) | $newFile" >> "$LOG_SKIPPED"
		skipped_no_ffprobe_count=$((skipped_no_ffprobe_count + 1))
		processed_count=$((processed_count + 1))
		return 0
	fi
	
	local codec=$(echo "$info_video" | sed -n '1p')
	local bitrate=$(echo "$info_video" | sed -n '3p')
	local sizeBeforeMB=$(du -m "$newFile" | awk '{print $1}')
	
	if [[ "$codec" == "hevc" || "$codec" == "h265" ]]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED (déjà x265) | $newFile" >> "$LOG_SKIPPED"
		skipped_x265_count=$((skipped_x265_count + 1))
		processed_count=$((processed_count + 1))
		return 0
	fi


	echo "$(date "+%Y-%m-%d %H:%M:%S") | $newFile | CHECK BITRATE" >> "$LOG_PROGRESS"
	if [[ "$bitrate" =~ ^[0-9]+$ ]] && [[ "$bitrate" -le 2300000 ]]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') | SKIPPED bitrate ${bitrate}bps | $newFile" >> "$LOG_SKIPPED"
		skipped_bitrate_count=$((skipped_bitrate_count + 1))
		processed_count=$((processed_count + 1))
		return 0
	fi

    echo "$(date "+%Y-%m-%d %H:%M:%S") | $newFile | CONVERTING..." >> "$LOG_PROGRESS"
	
	#-hwaccel cuda -hwaccel_output_format cuda \
	#-cq "$CRF"
	
	if ffmpeg -y -loglevel quiet -stats \
        -i "$newFile" \
        -c:v hevc_nvenc -preset p5 -rc vbr \
		-multipass qres \
		-b:v 2300k \
		-maxrate 3000k \
		-bufsize 4500k \
        -c:a copy \
        "$newOutputFile"; then
		
		local sizeAfterMB=$(du -m "$newOutputFile" | awk '{print $1}')

        # Déplacement vers la destination finale
        echo "$(date '+%Y-%m-%d %H:%M:%S') | $file | SUCCESS | ${sizeBeforeMB}MB -> ${sizeAfterMB}MB" >> "$LOG_SUCCESS"
		echo "$(date "+%Y-%m-%d %H:%M:%S") | $file | FINISHED" >> "$LOG_PROGRESS"
        success_count=$((success_count + 1))
        processed_count=$((processed_count + 1))
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ERROR ffmpeg | $file" >> "$LOG_ERROR"
		error_count=$((error_count + 1))
        processed_count=$((processed_count + 1))
        #rm -f "$tmp_input" "$tmp_output"
    fi
	
	break
	
done < "$QUEUE"

SUMMARY_FILE="$SOURCE/summary.txt"

{
    echo "Résumé du $(date "+%Y-%m-%d %H:%M:%S")"
    echo "--------------------------------------"
    echo "Fichiers trouvés               : $total_files"
    echo "Conversions réussies           : $success_count"
    echo "Skip bitrate (<=2.3 Mbps)      : $skipped_bitrate_count"
    echo "Skip no ffprobe                : $skipped_no_ffprobe_count"
    echo "Skip codec (x265)              : $skipped_x265_count"
    echo "Erreurs conversion             : $error_count"
    echo "Total fichiers traités         : $processed_count"
} > "$SUMMARY_FILE"
