#!/usr/bin/env bash
set -euo pipefail

# Génère des fichiers vidéo/audio "edge cases" (courts) pour tester NAScode.
# Objectif : samples reproductibles, sans sources externes, via lavfi.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

OUT_DIR="${REPO_ROOT}/samples/_generated"
DURATION_SECONDS="6"
FORCE="0"
ONLY_CASES=""

_usage() {
	cat <<'EOF'
Usage:
  bash tools/generate_ffmpeg_samples.sh [options]

Options:
  -o, --output DIR       Dossier de sortie (défaut: samples/_generated)
  -d, --duration SEC     Durée en secondes (défaut: 6)
  --only a,b,c           Ne génère que certains cas (noms ci-dessous)
  -f, --force            Écrase les fichiers existants
  -h, --help             Aide

Cas disponibles (noms pour --only) :
  h264_yuv444p
	av1_low_bitrate
	vp9_input
	mpeg4_input
  hevc_10bit_bt2020_pq
	hevc_high_bitrate
  h264_odd_dimensions
  h264_rotate90
  h264_interlaced_meta
  vfr_concat
	aac_high_bitrate_stereo
	eac3_high_bitrate_5_1
	flac_lossless_5_1
	pcm_7_1
	opus_5_1
	dts_5_1
	dts_7_1
	truehd_5_1
	truehd_7_1
  multiaudio_aac_ac3
  subtitles_srt
EOF
}

_die() {
	echo "[samples] ERREUR: $*" >&2
	exit 1
}

_need_cmd() {
	command -v "$1" >/dev/null 2>&1 || _die "Commande introuvable: $1"
}

_has_encoder() {
	local enc="$1"
	ffmpeg -hide_banner -encoders 2>/dev/null | awk '{print $2}' | grep -Fxq "$enc"
}

_mkdirp() {
	mkdir -p -- "$1"
}

_should_run_case() {
	local name="$1"
	[[ -z "$ONLY_CASES" ]] && return 0
	IFS=',' read -r -a _wanted <<<"$ONLY_CASES"
	local w
	for w in "${_wanted[@]}"; do
		[[ "$w" == "$name" ]] && return 0
	done
	return 1
}

_ffmpeg_overwrite_flag() {
	if [[ "$FORCE" == "1" ]]; then
		echo "-y"
	else
		echo "-n"
	fi
}

_write_banner() {
	echo "[samples] output=$OUT_DIR duration=${DURATION_SECONDS}s force=$FORCE"
}

_make_h264_yuv444p() {
	local out="$OUT_DIR/01_h264_yuv444p_high444.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "sine=frequency=1000:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv444p -profile:v high444 -crf 18 \
		-c:a aac -b:a 160k \
		"$out"
}

_make_hevc_10bit_bt2020_pq() {
	local out="$OUT_DIR/05_hevc_10bit_bt2020_pq.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx265; then
		echo "[samples]   skip: libx265 non disponible"
		return 0
	fi

	# HDR "soft" : on pose surtout les metadata colorimétriques + 10-bit.
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1920x1080:rate=24" \
		-f lavfi -i "sine=frequency=440:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
		-c:v libx265 -pix_fmt yuv420p10le -crf 20 \
		-c:a aac -b:a 160k \
		"$out"
}

_make_av1_low_bitrate() {
	local out="$OUT_DIR/02_av1_low_bitrate.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libsvtav1; then
		echo "[samples]   skip: libsvtav1 non disponible"
		return 0
	fi

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "sine=frequency=500:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libsvtav1 -pix_fmt yuv420p -crf 45 -preset 8 \
		-c:a aac -b:a 128k \
		"$out"
}

_make_vp9_input() {
	local out="$OUT_DIR/03_vp9_input.webm"
	echo "[samples] -> $out"

	if ! _has_encoder libvpx-vp9; then
		echo "[samples]   skip: libvpx-vp9 non disponible"
		return 0
	fi

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=30" \
		-f lavfi -i "sine=frequency=600:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libvpx-vp9 -pix_fmt yuv420p -b:v 1800k \
		-c:a libopus -b:a 96k \
		"$out"
}

_make_mpeg4_input() {
	local out="$OUT_DIR/04_mpeg4_avi_input.avi"
	echo "[samples] -> $out"

	if ! _has_encoder mpeg4; then
		echo "[samples]   skip: mpeg4 encoder non disponible"
		return 0
	fi

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=640x360:rate=25" \
		-f lavfi -i "sine=frequency=700:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v mpeg4 -q:v 4 \
		-c:a mp3 -b:a 128k \
		"$out"
}

_make_hevc_high_bitrate() {
	local out="$OUT_DIR/06_hevc_high_bitrate.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx265; then
		echo "[samples]   skip: libx265 non disponible"
		return 0
	fi

	# But: un HEVC volontairement "trop lourd" pour forcer un ré-encodage selon les seuils.
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1920x1080:rate=24" \
		-f lavfi -i "sine=frequency=440:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx265 -pix_fmt yuv420p -crf 6 \
		-c:a aac -b:a 160k \
		"$out"
}

_make_h264_odd_dimensions() {
	local out="$OUT_DIR/07_h264_odd_dimensions_853x479.mp4"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=853x479:rate=30" \
		-f lavfi -i "sine=frequency=880:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 19 \
		-c:a aac -b:a 128k \
		-movflags +faststart \
		"$out"
}

_make_h264_rotate90() {
	local out="$OUT_DIR/08_h264_rotate90_metadata.mp4"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=30" \
		-f lavfi -i "sine=frequency=660:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a aac -b:a 128k \
		-metadata:s:v:0 rotate=90 \
		-movflags +faststart \
		"$out"
}

_make_h264_interlaced_meta() {
	local out="$OUT_DIR/09_h264_interlaced_meta_tff.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1440x1080:rate=25" \
		-f lavfi -i "sine=frequency=330:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-vf "setfield=tff" \
		-c:v libx264 -pix_fmt yuv420p -crf 18 -flags +ilme+ildct -x264-params "tff=1" \
		-c:a aac -b:a 160k \
		"$out"
}

_make_vfr_concat() {
	local tmp="$OUT_DIR/_tmp_vfr"
	local out="$OUT_DIR/10_vfr_concat.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	_mkdirp "$tmp"

	# Important (Git Bash / Windows): le concat demuxer gère mal les chemins MSYS
	# de type /c/... (peut finir en C:/c/...). On travaille donc avec des chemins relatifs.
	pushd "$tmp" >/dev/null

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-t 3 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		"seg1.mkv"

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=30" \
		-t 3 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		"seg2.mkv"

	{
		echo "file 'seg1.mkv'"
		echo "file 'seg2.mkv'"
	} >"concat.txt"

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f concat -safe 0 -i "concat.txt" \
		-f lavfi -i "sine=frequency=500:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v copy \
		-c:a aac -b:a 160k \
		"$out"

	popd >/dev/null
	rm -rf -- "$tmp"
}

_make_aac_high_bitrate_stereo() {
	local out="$OUT_DIR/11_aac_high_bitrate_stereo.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	# But: AAC stéréo à bitrate élevé (cas downscale vers la cible AAC).
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "sine=frequency=880:sample_rate=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a aac -b:a 320k -ac 2 \
		"$out"
}

_make_eac3_high_bitrate_5_1() {
	local out="$OUT_DIR/12_eac3_high_bitrate_5_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder eac3; then
		echo "[samples]   skip: eac3 encoder non disponible"
		return 0
	fi

	# But: EAC3 5.1 trop haut (ex: 640k) -> downscale attendu vers 384k en mode film.
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.08*sin(2*PI*220*t)|0.08*sin(2*PI*330*t)|0.08*sin(2*PI*440*t)|0.08*sin(2*PI*550*t)|0.08*sin(2*PI*660*t)|0.08*sin(2*PI*770*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a eac3 -b:a 640k -ac 6 -metadata:s:a:0 language=eng \
		"$out"
}

_make_flac_lossless_5_1() {
	local out="$OUT_DIR/13_flac_lossless_5_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder flac; then
		echo "[samples]   skip: flac encoder non disponible"
		return 0
	fi

	# But: piste lossless (FLAC) qui devrait être conservée en smart audio (sauf --no-lossless).
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.08*sin(2*PI*220*t)|0.08*sin(2*PI*330*t)|0.08*sin(2*PI*440*t)|0.08*sin(2*PI*550*t)|0.08*sin(2*PI*660*t)|0.08*sin(2*PI*770*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a flac -ac 6 -metadata:s:a:0 language=eng \
		"$out"
}

_make_pcm_7_1() {
	local out="$OUT_DIR/14_pcm_7_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder pcm_s16le; then
		echo "[samples]   skip: pcm_s16le encoder non disponible"
		return 0
	fi

	# But: 7.1 (8 canaux) pour valider la logique de réduction (serie: -> stéréo, film: -> 5.1) lors d'une conversion.
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.06*sin(2*PI*220*t)|0.06*sin(2*PI*330*t)|0.06*sin(2*PI*440*t)|0.06*sin(2*PI*550*t)|0.06*sin(2*PI*660*t)|0.06*sin(2*PI*770*t)|0.06*sin(2*PI*880*t)|0.06*sin(2*PI*990*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a pcm_s16le -ac 8 -metadata:s:a:0 language=eng \
		"$out"
}

_make_opus_5_1() {
	local out="$OUT_DIR/15_opus_5_1_224k.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder libopus; then
		echo "[samples]   skip: libopus non disponible"
		return 0
	fi

	# But: Opus 5.1 à 224k (codec efficace multicanal, souvent à copier en smart audio).
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.08*sin(2*PI*220*t)|0.08*sin(2*PI*330*t)|0.08*sin(2*PI*440*t)|0.08*sin(2*PI*550*t)|0.08*sin(2*PI*660*t)|0.08*sin(2*PI*770*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a libopus -b:a 224k -ac 6 -metadata:s:a:0 language=eng \
		"$out"
}

_make_dts_5_1() {
	local out="$OUT_DIR/18_dts_5_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder dca; then
		echo "[samples]   skip: dca (DTS) encoder non disponible"
		return 0
	fi

	# But: DTS 5.1 (premium) -> devrait être passthrough en smart audio (sauf --no-lossless / règles premium).
	# Note: -strict est une option de sortie: elle doit être placée avant le fichier de sortie.
	if ! ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.08*sin(2*PI*220*t)|0.08*sin(2*PI*330*t)|0.08*sin(2*PI*440*t)|0.08*sin(2*PI*550*t)|0.08*sin(2*PI*660*t)|0.08*sin(2*PI*770*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a dca -b:a 1536k -ac 6 -metadata:s:a:0 language=eng \
		-strict -2 \
		"$out"; then
		echo "[samples]   skip: échec encodage DTS (dca)"
		return 0
	fi
}

_make_dts_7_1() {
	local out="$OUT_DIR/19_dts_7_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder dca; then
		echo "[samples]   skip: dca (DTS) encoder non disponible"
		return 0
	fi

	# But: DTS 7.1 (8 canaux) -> en mode film devrait être réduit vers 5.1 lors d'une conversion.
	# Note: selon la build ffmpeg, l'encodeur DTS peut refuser 7.1; on ne bloque pas le script.
	if ! ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.06*sin(2*PI*220*t)|0.06*sin(2*PI*330*t)|0.06*sin(2*PI*440*t)|0.06*sin(2*PI*550*t)|0.06*sin(2*PI*660*t)|0.06*sin(2*PI*770*t)|0.06*sin(2*PI*880*t)|0.06*sin(2*PI*990*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a dca -b:a 1536k -ac 8 -metadata:s:a:0 language=eng \
		-strict -2 \
		"$out"; then
		echo "[samples]   skip: encodage DTS 7.1 non supporté (ou a échoué)"
		return 0
	fi
}

_make_truehd_5_1() {
	local out="$OUT_DIR/20_truehd_5_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder truehd; then
		echo "[samples]   skip: truehd encoder non disponible"
		return 0
	fi

	# But: TrueHD 5.1 (premium/lossless) -> devrait être conservé par défaut.
	if ! ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.08*sin(2*PI*220*t)|0.08*sin(2*PI*330*t)|0.08*sin(2*PI*440*t)|0.08*sin(2*PI*550*t)|0.08*sin(2*PI*660*t)|0.08*sin(2*PI*770*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a truehd -ac 6 -metadata:s:a:0 language=eng \
		-strict -2 \
		"$out"; then
		echo "[samples]   skip: échec encodage TrueHD"
		return 0
	fi
}

_make_truehd_7_1() {
	local out="$OUT_DIR/21_truehd_7_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi
	if ! _has_encoder truehd; then
		echo "[samples]   skip: truehd encoder non disponible"
		return 0
	fi

	# But: TrueHD 7.1 (premium) -> cas réduction 7.1 -> 5.1 en mode film lors d'une conversion.
	if ! ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.06*sin(2*PI*220*t)|0.06*sin(2*PI*330*t)|0.06*sin(2*PI*440*t)|0.06*sin(2*PI*550*t)|0.06*sin(2*PI*660*t)|0.06*sin(2*PI*770*t)|0.06*sin(2*PI*880*t)|0.06*sin(2*PI*990*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a truehd -ac 8 -metadata:s:a:0 language=eng \
		-strict -2 \
		"$out"; then
		echo "[samples]   skip: encodage TrueHD 7.1 non supporté (ou a échoué)"
		return 0
	fi
}

_make_multiaudio_aac_ac3() {
	local out="$OUT_DIR/16_multiaudio_aac_stereo_ac3_5_1.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	# Piste 1: stéréo AAC (fra)
	# Piste 2: 5.1 AC3 (eng)
	# Aevalsrc: 6 canaux séparés par '|'
	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "aevalsrc=0.08*sin(2*PI*440*t)|0.08*sin(2*PI*550*t):s=48000" \
		-f lavfi -i "aevalsrc=0.08*sin(2*PI*220*t)|0.08*sin(2*PI*330*t)|0.08*sin(2*PI*440*t)|0.08*sin(2*PI*550*t)|0.08*sin(2*PI*660*t)|0.08*sin(2*PI*770*t):s=48000" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 -map 2:a:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a:0 aac -b:a:0 160k -ac:a:0 2 -metadata:s:a:0 language=fra \
		-c:a:1 ac3 -b:a:1 384k -ac:a:1 6 -metadata:s:a:1 language=eng \
		"$out"
}

_make_subtitles_srt() {
	local tmp="$OUT_DIR/_tmp_subs"
	local srt="$tmp/subs.srt"
	local out="$OUT_DIR/17_subtitles_srt.mkv"
	echo "[samples] -> $out"

	if ! _has_encoder libx264; then
		echo "[samples]   skip: libx264 non disponible"
		return 0
	fi

	_mkdirp "$tmp"

	cat >"$srt" <<'EOF'
1
00:00:00,000 --> 00:00:02,000
Hello NAScode

2
00:00:02,000 --> 00:00:05,000
Sous-titres SRT intégrés
EOF

	ffmpeg -hide_banner -loglevel error $(_ffmpeg_overwrite_flag) \
		-f lavfi -i "testsrc2=size=1280x720:rate=24" \
		-f lavfi -i "sine=frequency=440:sample_rate=48000" \
		-i "$srt" \
		-t "$DURATION_SECONDS" \
		-map 0:v:0 -map 1:a:0 -map 2:s:0 \
		-c:v libx264 -pix_fmt yuv420p -crf 20 \
		-c:a aac -b:a 160k \
		-c:s srt -metadata:s:s:0 language=eng \
		"$out"

	rm -rf -- "$tmp"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-o|--output)
			OUT_DIR="$2"; shift 2 ;;
		-d|--duration)
			DURATION_SECONDS="$2"; shift 2 ;;
		--only)
			ONLY_CASES="$2"; shift 2 ;;
		-f|--force)
			FORCE="1"; shift ;;
		-h|--help)
			_usage; exit 0 ;;
		*)
			_die "Option inconnue: $1" ;;
	esac
	done

_need_cmd ffmpeg
_mkdirp "$OUT_DIR"
_write_banner

if _should_run_case h264_yuv444p; then _make_h264_yuv444p; fi
if _should_run_case av1_low_bitrate; then _make_av1_low_bitrate; fi
if _should_run_case vp9_input; then _make_vp9_input; fi
if _should_run_case mpeg4_input; then _make_mpeg4_input; fi
if _should_run_case hevc_10bit_bt2020_pq; then _make_hevc_10bit_bt2020_pq; fi
if _should_run_case hevc_high_bitrate; then _make_hevc_high_bitrate; fi
if _should_run_case h264_odd_dimensions; then _make_h264_odd_dimensions; fi
if _should_run_case h264_rotate90; then _make_h264_rotate90; fi
if _should_run_case h264_interlaced_meta; then _make_h264_interlaced_meta; fi
if _should_run_case vfr_concat; then _make_vfr_concat; fi
if _should_run_case aac_high_bitrate_stereo; then _make_aac_high_bitrate_stereo; fi
if _should_run_case eac3_high_bitrate_5_1; then _make_eac3_high_bitrate_5_1; fi
if _should_run_case flac_lossless_5_1; then _make_flac_lossless_5_1; fi
if _should_run_case pcm_7_1; then _make_pcm_7_1; fi
if _should_run_case opus_5_1; then _make_opus_5_1; fi
if _should_run_case dts_5_1; then _make_dts_5_1; fi
if _should_run_case dts_7_1; then _make_dts_7_1; fi
if _should_run_case truehd_5_1; then _make_truehd_5_1; fi
if _should_run_case truehd_7_1; then _make_truehd_7_1; fi
if _should_run_case multiaudio_aac_ac3; then _make_multiaudio_aac_ac3; fi
if _should_run_case subtitles_srt; then _make_subtitles_srt; fi

echo "[samples] Terminé. Fichiers dans: $OUT_DIR"
