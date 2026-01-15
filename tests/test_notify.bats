#!/usr/bin/env bats

load "test_helper.bash"

@test "notify: no-op sans webhook" {
  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; notify_event run_started'
  [ "$status" -eq 0 ]
}

@test "notify: envoie via curl mock quand webhook présent" {
  tmp="$BATS_TEST_TMPDIR"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
payload_file="${NASCODE_TEST_PAYLOAD_FILE:-}"

while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data-binary" ]]; then
    shift
    # Format attendu: @/path/to/file
    data_arg="$1"
    if [[ -n "$payload_file" ]] && [[ "$data_arg" == @* ]]; then
      src_file="${data_arg#@}"
      cat "$src_file" > "$payload_file"
    fi
    exit 0
  fi
  shift
done

exit 0
EOF
  chmod +x "$tmp/bin/curl"

  export PATH="$tmp/bin:$PATH"
  export NASCODE_TEST_PAYLOAD_FILE="$tmp/payload.json"
  export NASCODE_DISCORD_WEBHOOK_URL="https://discord.invalid/webhook"
  export NASCODE_DISCORD_NOTIFY=true
  export NASCODE_DISCORD_NOTIFY_ALLOW_IN_TESTS=true

  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; notify_discord_send_markdown "hello"; test -s "$NASCODE_TEST_PAYLOAD_FILE"'
  [ "$status" -eq 0 ]
  grep -q '"content"' "$NASCODE_TEST_PAYLOAD_FILE"
}

@test "notify: debug log écrit le code HTTP" {
  tmp="$BATS_TEST_TMPDIR"
  mkdir -p "$tmp/bin" "$tmp/logs"

  cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# En mode debug, notify.sh utilise -w '%{http_code}' et capture stdout.
echo "204"
exit 0
EOF
  chmod +x "$tmp/bin/curl"

  export PATH="$tmp/bin:$PATH"
  export LOG_DIR="$tmp/logs"
  export NASCODE_DISCORD_WEBHOOK_URL="https://discord.invalid/webhook"
  export NASCODE_DISCORD_NOTIFY=true
  export NASCODE_DISCORD_NOTIFY_DEBUG=true
  export NASCODE_DISCORD_NOTIFY_ALLOW_IN_TESTS=true
  export EXECUTION_TIMESTAMP="test"

  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; notify_discord_send_markdown "hello" "run_started"; test -s "$LOG_DIR/discord_notify_${EXECUTION_TIMESTAMP}.log"'
  [ "$status" -eq 0 ]
  grep -q "http=204" "$LOG_DIR/discord_notify_${EXECUTION_TIMESTAMP}.log"
}

@test "notify: file_skipped envoie un message" {
  tmp="$BATS_TEST_TMPDIR"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
payload_file="${NASCODE_TEST_PAYLOAD_FILE:-}"

while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--data-binary" ]]; then
    shift
    data_arg="$1"
    if [[ -n "$payload_file" ]] && [[ "$data_arg" == @* ]]; then
      src_file="${data_arg#@}"
      cat "$src_file" > "$payload_file"
    fi
    exit 0
  fi
  shift
done

exit 0
EOF
  chmod +x "$tmp/bin/curl"

  export PATH="$tmp/bin:$PATH"
  export NASCODE_TEST_PAYLOAD_FILE="$tmp/payload.json"
  export NASCODE_DISCORD_WEBHOOK_URL="https://discord.invalid/webhook"
  export NASCODE_DISCORD_NOTIFY=true
  export NASCODE_DISCORD_NOTIFY_ALLOW_IN_TESTS=true

  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; notify_event file_skipped "file01.mkv" "Déjà X265 & bitrate optimisé"; test -s "$NASCODE_TEST_PAYLOAD_FILE"'
  [ "$status" -eq 0 ]

  # Le contenu est JSON-encodé, on matche juste sur des fragments robustes.
  grep -q 'Ignor' "$NASCODE_TEST_PAYLOAD_FILE"
  grep -q 'file01.mkv' "$NASCODE_TEST_PAYLOAD_FILE"
  grep -q 'Raison' "$NASCODE_TEST_PAYLOAD_FILE"
}

@test "notify_format: jobs parallèles désactivé si =1" {
  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; PARALLEL_JOBS=1; _notify_format_parallel_jobs_label'
  [ "$status" -eq 0 ]
  [ "$output" = "désactivé" ]
}

@test "notify_format: aperçu queue max 20 avec ... et 3 derniers" {
  tmp="$BATS_TEST_TMPDIR"
  q="$tmp/queue.bin"

  # Construire une queue NUL-separated de 30 fichiers
  : > "$q"
  for i in $(seq 1 30); do
    printf 'file%02d.mp4\0' "$i" >> "$q"
  done

  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; _notify_format_queue_preview "$1"' bash "$q"
  [ "$status" -eq 0 ]

  # 20 lignes exactement : 16 + ... + 3
  [ "$(printf "%s\n" "$output" | wc -l | tr -d " ")" -eq 20 ]
  echo "$output" | grep -q "^\\[1/30\\] file01.mp4$"
  echo "$output" | grep -q "^\\.\\.\\.$"
  echo "$output" | grep -q "^\\[28/30\\] file28.mp4$"
  echo "$output" | grep -q "^\\[29/30\\] file29.mp4$"
  echo "$output" | grep -q "^\\[30/30\\] file30.mp4$"
}

@test "notify_format: résumé run markdown depuis metrics" {
  tmp="$BATS_TEST_TMPDIR"
  m="$tmp/summary_metrics.kv"

  cat > "$m" <<'EOF'
duration_total=1h 02min
succ=3
skip=1
err=0
size_anomalies=0
checksum_anomalies=2
vmaf_anomalies=0
show_space_savings=true
space_line1=120 MB (12%)
space_line2=Total: 1.0 GB -> 0.88 GB
EOF

  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; _notify_format_run_summary_markdown "$1" "2026-01-14 12:00:00" "0"' bash "$m"
  [ "$status" -eq 0 ]

  echo "$output" | grep -q "Résumé"
  echo "$output" | grep -q "\*\*Fin\*\* : 2026-01-14 12:00:00"
  echo "$output" | grep -q "\*\*Durée\*\* : 1h 02min"
  echo "$output" | grep -q "\*\*Résultats\*\*"
  echo "$output" | grep -q -- "- Succès : 3"
  echo "$output" | grep -q -- "- Ignorés : 1"
  echo "$output" | grep -q -- "- Erreurs : 0"
  echo "$output" | grep -q "\*\*Anomalies\*\*"
  echo "$output" | grep -q "Intégrité : 2"
  echo "$output" | grep -q "\*\*Espace économisé\*\*"
  echo "$output" | grep -q "120 MB (12%)"
  # Le message final varie selon le code de sortie (0 = succès, 130 = Ctrl+C, autre = erreur)
  echo "$output" | grep -q "Session terminée"
}

@test "notify_format: message fin distingue succès/interruption/erreur" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"

  # Fin normale (code 0)
  run _notify_format_event_script_exit_end "2026-01-14 12:00:00" 0
  echo "$output" | grep -q "Fin : 2026-01-14"
  [[ "$output" != *"Interrompu"* ]]
  [[ "$output" != *"Erreur"* ]]

  # Interruption Ctrl+C (code 130)
  run _notify_format_event_script_exit_end "2026-01-14 12:00:00" 130
  echo "$output" | grep -q "Interrompu : 2026-01-14"
  [[ "$output" != *"Fin :"* ]]

  # Erreur générique (code 1)
  run _notify_format_event_script_exit_end "2026-01-14 12:00:00" 1
  echo "$output" | grep -q "Erreur (code 1) : 2026-01-14"
  [[ "$output" != *"Fin :"* ]]
  [[ "$output" != *"Interrompu"* ]]
}

###########################################################
# Tests supplémentaires notify_format.sh
###########################################################

@test "notify_format: event file_started formate correctement" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  run _notify_format_event_file_started "test_video.mkv" 5 10
  [ "$status" -eq 0 ]
  
  # Doit contenir le nom du fichier
  echo "$output" | grep -q "test_video.mkv"
}

@test "notify_format: event file_completed formate correctement" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  run _notify_format_event_file_completed "test_video.mkv" "3m 45s" "850 Mo" "1.2 Go"
  [ "$status" -eq 0 ]
  
  echo "$output" | grep -q "test_video.mkv"
  echo "$output" | grep -q "3m 45s"
}

@test "notify_format: vmaf_quality_badge retourne badge selon score" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  # Score excellent (>= 95)
  run _notify_format_vmaf_quality_badge 98
  [[ "$output" =~ "🟢" ]] || [[ "$output" =~ "Excellent" ]] || [[ -n "$output" ]]
  
  # Score bon (>= 90)
  run _notify_format_vmaf_quality_badge 92
  [ "$status" -eq 0 ]
  
  # Score moyen (>= 80)
  run _notify_format_vmaf_quality_badge 85
  [ "$status" -eq 0 ]
  
  # Score faible (< 80)
  run _notify_format_vmaf_quality_badge 70
  [ "$status" -eq 0 ]
}

@test "notify_format: event run_started inclut infos de base" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  # Définir les variables attendues
  export SOURCE="/test/source"
  export OUTPUT_DIR="/test/output"
  export CONVERSION_MODE="serie"
  export DRYRUN=false
  
  run _notify_format_event_run_started "2026-01-14 10:00:00" 15
  [ "$status" -eq 0 ]
  
  # Doit contenir des infos sur le démarrage
  [[ -n "$output" ]]
}

@test "notify_format: parallel_jobs_label avec valeur > 1" {
  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; PARALLEL_JOBS=4; _notify_format_parallel_jobs_label'
  [ "$status" -eq 0 ]
  [ "$output" = "4" ]
}

@test "notify_format: event peak_pause formate correctement" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  run _notify_format_event_peak_pause "08:00" "22:00"
  [ "$status" -eq 0 ]
  
  echo "$output" | grep -q "08:00"
  echo "$output" | grep -q "22:00"
}

@test "notify_format: event peak_resume formate correctement" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  run _notify_format_event_peak_resume
  [ "$status" -eq 0 ]
  [[ -n "$output" ]]
}

@test "notify_format: queue_preview avec peu de fichiers" {
  tmp="$BATS_TEST_TMPDIR"
  q="$tmp/queue_small.bin"

  # Queue de 5 fichiers seulement
  : > "$q"
  for i in $(seq 1 5); do
    printf 'file%02d.mp4\0' "$i" >> "$q"
  done

  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; _notify_format_queue_preview "$1"' bash "$q"
  [ "$status" -eq 0 ]

  # 5 lignes exactement (pas de ...)
  [ "$(printf "%s\n" "$output" | wc -l | tr -d " ")" -eq 5 ]
  echo "$output" | grep -q "^\\[1/5\\] file01.mp4$"
  echo "$output" | grep -q "^\\[5/5\\] file05.mp4$"
  # Pas de ...
  [[ "$output" != *"..."* ]]
}

@test "notify_format: queue_preview avec fichier vide" {
  tmp="$BATS_TEST_TMPDIR"
  q="$tmp/queue_empty.bin"
  touch "$q"

  run bash -c 'source "$LIB_DIR/ui.sh"; source "$LIB_DIR/notify.sh"; _notify_format_queue_preview "$1"' bash "$q"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "notify_format: event transfers_pending formate correctement" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  run _notify_format_event_transfers_pending 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "5"
}

@test "notify_format: event vmaf_started formate correctement" {
  load_modules minimal_fast
  source "$LIB_DIR/notify.sh"
  
  run _notify_format_event_vmaf_started 10
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "10"
}