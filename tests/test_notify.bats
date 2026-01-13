#!/usr/bin/env bats

load "test_helper.bash"

@test "notify: no-op sans webhook" {
  run bash -c 'source "$LIB_DIR/notify.sh"; notify_event run_started'
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
  export NASCODE_DISCORD_NOTIFY_ALLOW_IN_TESTS=true

  run bash -c 'source "$LIB_DIR/notify.sh"; notify_discord_send_markdown "hello"; test -s "$NASCODE_TEST_PAYLOAD_FILE"'
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

  run bash -c 'source "$LIB_DIR/notify.sh"; notify_discord_send_markdown "hello" "run_started"; test -s "$LOG_DIR/discord_notify_${EXECUTION_TIMESTAMP}.log"'
  [ "$status" -eq 0 ]
  grep -q "http=204" "$LOG_DIR/discord_notify_${EXECUTION_TIMESTAMP}.log"
}

@test "notify_format: jobs parallèles désactivé si =1" {
  run bash -c 'source "$LIB_DIR/notify.sh"; PARALLEL_JOBS=1; _notify_format_parallel_jobs_label'
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

  run bash -c 'source "$LIB_DIR/notify.sh"; _notify_format_queue_preview "$1"' bash "$q"
  [ "$status" -eq 0 ]

  # 20 lignes exactement : 16 + ... + 3
  [ "$(printf "%s\n" "$output" | wc -l | tr -d " ")" -eq 20 ]
  echo "$output" | grep -q "^\\[1/30\\] file01.mp4$"
  echo "$output" | grep -q "^\\.\\.\\.$"
  echo "$output" | grep -q "^\\[28/30\\] file28.mp4$"
  echo "$output" | grep -q "^\\[29/30\\] file29.mp4$"
  echo "$output" | grep -q "^\\[30/30\\] file30.mp4$"
}