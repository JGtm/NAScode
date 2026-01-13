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
  if [[ "$1" == "-d" ]]; then
    shift
    [[ -n "$payload_file" ]] && printf "%s" "$1" > "$payload_file"
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

  run bash -c 'source "$LIB_DIR/notify.sh"; notify_discord_send_markdown "hello"; test -s "$NASCODE_TEST_PAYLOAD_FILE"'
  [ "$status" -eq 0 ]
  grep -q '"content"' "$NASCODE_TEST_PAYLOAD_FILE"
}