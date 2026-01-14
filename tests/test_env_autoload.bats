#!/usr/bin/env bats

load "test_helper.bash"

@test "env: charge un fichier .env (NASCODE_* uniquement)" {
  tmp="$BATS_TEST_TMPDIR"
  envf="$tmp/env.local"

  cat > "$envf" <<'EOF'
# Comment
export NASCODE_DISCORD_NOTIFY=true
NASCODE_DISCORD_WEBHOOK_URL="https://discord.invalid/webhook"
NOT_NASCODE_SHOULD_NOT_LOAD=1
NASCODE_QUOTED='abc def'
EOF

  run bash -c 'source "$LIB_DIR/env.sh"; _nascode_load_env_file "$1"; echo "notify=${NASCODE_DISCORD_NOTIFY:-}"; echo "webhook=${NASCODE_DISCORD_WEBHOOK_URL:+set}"; echo "other=${NOT_NASCODE_SHOULD_NOT_LOAD:-}"; echo "quoted=${NASCODE_QUOTED:-}"' bash "$envf"
  [ "$status" -eq 0 ]

  echo "$output" | grep -q "notify=true"
  echo "$output" | grep -q "webhook=set"
  echo "$output" | grep -q "other="
  echo "$output" | grep -q "quoted=abc def"
}

@test "env: autoload peut être désactivé" {
  tmp="$BATS_TEST_TMPDIR"
  envf="$tmp/env.local"

  printf '%s\n' 'NASCODE_TEST_AUTOLOAD=1' > "$envf"

  run bash -c 'source "$LIB_DIR/env.sh"; unset NASCODE_TEST_AUTOLOAD; NASCODE_ENV_AUTOLOAD=false; NASCODE_ENV_FILE="$1"; _nascode_autoload_env "."; echo "val=${NASCODE_TEST_AUTOLOAD:-}"' bash "$envf"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "val="
}

@test "env: autoload utilise NASCODE_ENV_FILE" {
  tmp="$BATS_TEST_TMPDIR"
  envf="$tmp/custom.env"

  printf '%s\n' 'NASCODE_DISCORD_NOTIFY=true' > "$envf"

  run bash -c 'source "$LIB_DIR/env.sh"; NASCODE_ENV_FILE="$1"; _nascode_autoload_env "."; echo "notify=${NASCODE_DISCORD_NOTIFY:-}"' bash "$envf"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "notify=true"
}
