# Dépannage

## Logs (où regarder)

Les logs sont dans `logs/`.

Fichiers typiques :
- `Session_*.log` : journal unifié de la session
- `Summary_*.log` : résumé de fin de conversion
- `Progress_*.log` : progression détaillée
- `Success_*.log` / `Error_*.log` / `Skipped_*.log`
- `SVT_*.log` : extrait de config SVT-AV1 (option debug, voir ci-dessous)
- `Index` : index des fichiers à traiter (null-separated)
- `Index_readable_*.txt` : index lisible (liste)
- `Queue` / `Queue.full` : file d’attente (généralement temporaire)
- `DryRun_Comparison_*.log` : comparaison des noms (dry-run)

## Aucun fichier à traiter / queue invalide / source exclue

### 1) Message “Aucun fichier à traiter”

Ça arrive typiquement quand **aucun fichier ne passe les filtres** (ex: `--min-size`) ou quand la **source** (`-s`) ne pointe pas sur le bon dossier.

Actions rapides :

```bash
# Régénérer index + queue depuis la source
bash nascode -R -s "/chemin/source"

# Si tu avais un filtre taille, essaye sans
bash nascode -R -s "/chemin/source"  # sans --min-size
```

### 2) Message “Format du fichier queue invalide (séparateur NUL attendu)”

NAScode utilise des fichiers `logs/Index`/`logs/Queue` au format **null-separated**.
Si tu fournis un fichier queue personnalisé (option `-q`), il doit respecter ce format.

Actions rapides :

```bash
# Supprimer la queue et régénérer
rm -f logs/Queue logs/Queue.full 2>/dev/null || true
bash nascode -R -s "/chemin/source"
```

### 3) Erreur “Le répertoire source est exclu par la configuration (EXCLUDES)”

La config contient une liste d’exclusions (`EXCLUDES`). Si ta `SOURCE` (après normalisation) matche une exclusion, NAScode s’arrête explicitement.

Actions rapides :

- Vérifie que tu passes bien le bon `-s`.
- Ajuste `EXCLUDES` (dans la config) si tu veux autoriser ce chemin.

## Lockfile / Stop flag

En cas de crash, le script peut laisser :
- Lockfile : `/tmp/conversion_video.lock`
- Stop flag : `/tmp/conversion_stop_flag`

Si aucun `nascode` ne tourne, supprimer :

```bash
rm -f /tmp/conversion_video.lock /tmp/conversion_stop_flag
```

## Vérifier FFmpeg (encoders/filters)

```bash
ffmpeg -hide_banner -encoders | grep libx265
ffmpeg -hide_banner -encoders | grep libsvtav1  # optionnel (AV1)
ffmpeg -hide_banner -filters | grep libvmaf     # optionnel (VMAF)
```

## FFmpeg sans libx265

```bash
# Ubuntu/Debian
sudo apt install ffmpeg

# macOS
brew install ffmpeg
```

## Windows (Git Bash) : FFmpeg avec SVT-AV1

La version "essentials" de FFmpeg (gyan.dev) ne contient pas `libsvtav1` pour l'encodage AV1.
Si tu utilises Git Bash avec MSYS2, tu peux installer une version complète de FFmpeg :

```bash
# 1. Installer FFmpeg et SVT-AV1 via pacman (MSYS2)
pacman -S mingw-w64-ucrt-x86_64-ffmpeg mingw-w64-ucrt-x86_64-svt-av1

# 2. Ajouter MSYS2 au PATH (dans ~/.bashrc)
echo 'export PATH="/c/msys64/ucrt64/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 3. Vérifier que libsvtav1 est disponible
ffmpeg -encoders 2>/dev/null | grep libsvtav1
```

Note : sans MSYS2, il est possible d'utiliser un FFmpeg "full" depuis https://www.gyan.dev/ffmpeg/builds/.

## Debug SVT-AV1 : vérifier "capped CRF" / `mbr`

Si tu veux confirmer que SVT-AV1 a bien activé le mode "capped CRF" et pris en compte `mbr=<kbps>`, tu peux activer un mode debug qui écrit un petit log dédié **sans spammer le terminal** :

```bash
NASCODE_LOG_SVT_CONFIG=1 bash nascode [options]
```

Résultat :
- Un fichier `logs/SVT_<timestamp>_*.log` est créé par conversion AV1 (SVT-AV1) et contient les lignes `Svt[info]: SVT [config] ...` incluant notamment `BRC mode ... capped CRF ... max bitrate`.
- Le terminal reste inchangé (la sortie FFmpeg est déjà redirigée, on n’affiche pas ces lignes en direct).

## VMAF

- Si ton FFmpeg principal n’a pas `libvmaf`, le script peut chercher un FFmpeg alternatif selon l’environnement.
- En cas de doute : tester sur un fichier via `-l 1` et activer les logs.

Repères de lecture (indicatifs) :

| Score | Qualité |
|-------|---------|
| ≥ 90 | EXCELLENT |
| 80-89 | TRÈS BON |
| 70-79 | BON |
| < 70 | DÉGRADÉ |

## Fichiers sautés (skip)

- Consulter `logs/Skipped_*.log`.

## Erreurs d'encodage

1. Consulter `logs/Error_*.log`
2. Vérifier l'espace disque dans `/tmp`
3. Tester avec un seul fichier : `bash nascode -l 1`

## Noms de fichiers

Le script gère les espaces et caractères spéciaux, mais éviter les caractères de contrôle.
