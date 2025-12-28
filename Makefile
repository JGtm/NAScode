.DEFAULT_GOAL := help

SHELL := bash

.PHONY: help test doctor msys2-update msys2-install msys2-install-dev msys2-install-vmaf

help:
	@echo "Targets:" 
	@echo "  make help              Affiche cette aide"
	@echo "  make test [ARGS='...'] Lance les tests (wrapper de ./run_tests.sh)"
	@echo "  make doctor            Vérifie les dépendances (binaires + capacités FFmpeg)"
	@echo "  make msys2-update       (MSYS2) Met à jour les paquets via pacman"
	@echo "  make msys2-install      (MSYS2) Installe les dépendances via pacman"
	@echo "  make msys2-install-dev  (MSYS2) Installe les outils dev (shellcheck, shfmt)"
	@echo "  make msys2-install-vmaf (MSYS2) Installe la lib vmaf (NB: n'ajoute pas le filtre FFmpeg)"
	@echo ""
	@echo "Exemples:" 
	@echo "  make test"
	@echo "  make test ARGS='-v'"
	@echo "  make test ARGS='-f queue'"
	@echo "  make msys2-install"

# ARGS permet de passer des options à run_tests.sh (ex: -v, -f pattern)
# Exemple: make test ARGS='-v'
ARGS ?=

test:
	@set -euo pipefail; \
	bash ./run_tests.sh $(ARGS)

# Vérifie les dépendances réellement utilisées par le script et les tests.
# - Échoue si des requis "hard" manquent
# - Avertit si des features optionnelles (AV1/VMAF, checksums alternatifs) manquent

doctor:
	@set -euo pipefail; \
	echo "== NAScode doctor =="; \
	echo ""; \
	\
	required_cmds=(bash awk sed grep ffmpeg ffprobe mkfifo flock); \
	missing=0; \
	echo "[Requis]"; \
	for c in "$${required_cmds[@]}"; do \
		if command -v "$$c" >/dev/null 2>&1; then \
			printf "  OK   %s\n" "$$c"; \
		else \
			printf "  MISS %s\n" "$$c"; \
			missing=1; \
		fi; \
	done; \
	\
	echo ""; \
	echo "[Checksums]"; \
	if command -v sha256sum >/dev/null 2>&1; then \
		echo "  OK   sha256sum"; \
	elif command -v shasum >/dev/null 2>&1; then \
		echo "  OK   shasum (sha256 via 'shasum -a 256')"; \
	else \
		echo "  WARN aucun sha256sum/shasum (transfert checksum peut être impacté)"; \
	fi; \
	\
	if command -v md5sum >/dev/null 2>&1; then \
		echo "  OK   md5sum"; \
	elif command -v md5 >/dev/null 2>&1; then \
		echo "  OK   md5"; \
	elif command -v python3 >/dev/null 2>&1; then \
		echo "  OK   python3 (fallback md5)"; \
	else \
		echo "  WARN aucun md5sum/md5/python3 (fallback md5 indisponible)"; \
	fi; \
	\
	echo ""; \
	echo "[Tests]"; \
	if command -v bats >/dev/null 2>&1; then \
		echo "  OK   bats ($$(bats --version 2>/dev/null || true))"; \
	else \
		echo "  WARN bats non trouvé (make test échouera)"; \
	fi; \
	\
	echo ""; \
	echo "[FFmpeg capabilities]"; \
	if command -v ffmpeg >/dev/null 2>&1; then \
		echo "  $$(ffmpeg -hide_banner -version 2>/dev/null | head -n 1 || true)"; \
		enc=$$(ffmpeg -hide_banner -encoders 2>/dev/null || true); \
		filt=$$(ffmpeg -hide_banner -filters 2>/dev/null || true); \
		if echo "$$enc" | grep -q "libx265"; then echo "  OK   encoder libx265 (HEVC)"; else echo "  MISS encoder libx265 (HEVC)"; missing=1; fi; \
		if echo "$$enc" | grep -q "libsvtav1"; then echo "  OK   encoder libsvtav1 (AV1)"; else echo "  WARN encoder libsvtav1 (AV1) absent (AV1 indisponible)"; fi; \
		if echo "$$enc" | grep -q "libaom-av1"; then echo "  OK   encoder libaom-av1 (AV1 alt)"; else echo "  INFO encoder libaom-av1 absent"; fi; \
		if echo "$$filt" | grep -q "libvmaf"; then echo "  OK   filter libvmaf (VMAF)"; else echo "  WARN filter libvmaf absent (option -v/--vmaf indisponible)"; fi; \
	else \
		echo "  MISS ffmpeg (déjà signalé ci-dessus)"; \
	fi; \
	\
	echo ""; \
	if [ "$$missing" -ne 0 ]; then \
		echo "Doctor: ECHEC (dépendances requises manquantes)"; \
		exit 1; \
	fi; \
	echo "Doctor: OK";

# --- MSYS2 helpers (optionnels) ---
# Ces cibles sont utiles si tu es dans un shell MSYS2 (Git Bash avec pacman).
# Elles ne sont pas portables sur Linux/macOS.

msys2-update:
	@set -euo pipefail; \
	if ! command -v pacman >/dev/null 2>&1; then \
		echo "pacman introuvable. Ces cibles sont prévues pour MSYS2."; \
		exit 1; \
	fi; \
	echo "MSYS2: mise à jour (pacman -Syu)"; \
	echo "NB: MSYS2 peut demander de fermer/réouvrir le shell."; \
	pacman -Syu

msys2-install:
	@set -euo pipefail; \
	if ! command -v pacman >/dev/null 2>&1; then \
		echo "pacman introuvable. Ces cibles sont prévues pour MSYS2."; \
		exit 1; \
	fi; \
	echo "MSYS2: installation des dépendances NAScode"; \
	pacman -S --needed \
		bash coreutils findutils grep sed gawk diffutils util-linux procps-ng \
		make \
		perl python \
		ffmpeg \
		bats

msys2-install-dev:
	@set -euo pipefail; \
	if ! command -v pacman >/dev/null 2>&1; then \
		echo "pacman introuvable. Ces cibles sont prévues pour MSYS2."; \
		exit 1; \
	fi; \
	echo "MSYS2: installation outils dev (lint/format)"; \
	pacman -S --needed shellcheck shfmt

msys2-install-vmaf:
	@set -euo pipefail; \
	if ! command -v pacman >/dev/null 2>&1; then \
		echo "pacman introuvable. Ces cibles sont prévues pour MSYS2."; \
		exit 1; \
	fi; \
	echo "MSYS2: installation de la lib vmaf"; \
	echo "ATTENTION: installer vmaf ne suffit pas: il faut un FFmpeg compilé avec libvmaf pour avoir le filtre 'libvmaf'."; \
	pacman -S --needed vmaf || true
