# TODO : Détection de Grain pour Film-Adaptive

## Contexte

Le mode `film-adaptive` utilise actuellement 3 métriques (stddev, SI, TI) pour calculer le coefficient de complexité. Cependant, les films avec grain de pellicule (35mm, 16mm, grain ajouté en post-production) peuvent nécessiter un traitement spécial car :

1. Le grain augmente artificiellement le SI (complexité spatiale) mais de manière uniforme
2. Le grain est difficile à compresser efficacement sans artefacts
3. Un bitrate insuffisant produit un effet "lissé" indésirable ou des blocs visibles

## Objectif

Détecter automatiquement la présence de grain et ajuster le coefficient C en conséquence :
- Grain détecté → `C = C × 1.10` à `C × 1.15` (boost de 10-15%)

---

## Implémentation Proposée

### Option A : Analyse de la variance haute fréquence (recommandé)

**Principe** : Le grain produit du bruit haute fréquence uniformément réparti. Filtrer les hautes fréquences et mesurer la variance résiduelle.

**Implémentation** :

```bash
# Extraire les hautes fréquences via un filtre passe-haut
# et mesurer la variance des valeurs résultantes

_detect_grain_level() {
    local file="$1"
    local start_sec="$2"
    local duration_sec="$3"
    
    # Appliquer un filtre edge detection + mesurer la variance
    # Le grain produit beaucoup de petits edges uniformément répartis
    ffmpeg -hide_banner -ss "$start_sec" -t "$duration_sec" -i "$file" \
        -vf "edgedetect=mode=colormix:high=0.1,signalstats" \
        -f null - 2>&1 | \
        awk '/YAVG/ { sum += $2; count++ } END { if(count>0) print sum/count; else print 0 }'
}

# Seuils de détection
# < 5  : pas de grain (numérique propre)
# 5-15 : grain léger (post-production subtil)
# > 15 : grain fort (pellicule 35mm)
```

**Avantages** :
- Simple à implémenter
- Coût CPU modéré
- Bonne discrimination

**Inconvénients** :
- Peut confondre grain et textures naturelles (feuillage, tissu)

---

### Option B : Analyse par débruitage comparatif

**Principe** : Comparer la vidéo originale avec une version débruitée. La différence = estimation du bruit/grain.

**Implémentation** :

```bash
_detect_grain_by_denoise() {
    local file="$1"
    local start_sec="$2"
    local duration_sec="$3"
    
    # Calculer la différence entre original et débruité
    ffmpeg -hide_banner -ss "$start_sec" -t "$duration_sec" -i "$file" \
        -filter_complex "[0:v]split[a][b];
                         [a]hqdn3d=4:3:6:4.5[denoised];
                         [b][denoised]blend=difference[diff];
                         [diff]signalstats" \
        -f null - 2>&1 | \
        awk '/YAVG/ { sum += $2; count++ } END { if(count>0) print sum/count; else print 0 }'
}

# Seuils
# < 3  : pas de grain
# 3-8  : grain modéré
# > 8  : grain fort
```

**Avantages** :
- Très précis pour isoler le grain
- Distingue grain et textures réelles

**Inconvénients** :
- Plus lent (débruitage en temps réel)
- Dépend du filtre hqdn3d

---

### Option C : Machine Learning (futur)

Utiliser un modèle pré-entraîné pour classifier les contenus. Hors scope actuel mais à considérer pour une v2.

---

## Plan d'Implémentation

### Phase 1 : Prototype (Option A)

1. **Ajouter les constantes** dans `lib/constants.sh` :
   ```bash
   ADAPTIVE_GRAIN_DETECTION="${ADAPTIVE_GRAIN_DETECTION:-false}"  # Désactivé par défaut
   ADAPTIVE_GRAIN_THRESHOLD_LOW="${ADAPTIVE_GRAIN_THRESHOLD_LOW:-5}"
   ADAPTIVE_GRAIN_THRESHOLD_HIGH="${ADAPTIVE_GRAIN_THRESHOLD_HIGH:-15}"
   ADAPTIVE_GRAIN_BOOST_FACTOR="${ADAPTIVE_GRAIN_BOOST_FACTOR:-1.10}"
   ```

2. **Implémenter `_detect_grain_level()`** dans `lib/complexity.sh`

3. **Intégrer dans `_map_metrics_to_complexity()`** :
   ```bash
   if [[ "${ADAPTIVE_GRAIN_DETECTION:-false}" == true ]]; then
       local grain_level
       grain_level=$(_detect_grain_level "$file" ...)
       if [[ "$grain_level" -gt "$ADAPTIVE_GRAIN_THRESHOLD_LOW" ]]; then
           complexity_c=$(awk -v c="$complexity_c" -v boost="$ADAPTIVE_GRAIN_BOOST_FACTOR" \
               'BEGIN { printf "%.2f", c * boost }')
       fi
   fi
   ```

4. **Ajouter affichage UX** dans `display_complexity_analysis()` :
   ```
   📊 Résultats d'analyse :
      └─ Grain détecté : modéré (boost +10%)
   ```

### Phase 2 : Tests

1. **Créer des tests unitaires** dans `tests/test_film_adaptive.bats` :
   - `_detect_grain_level` retourne 0 pour vidéo numérique propre
   - Boost appliqué correctement quand grain > seuil

2. **Tests manuels** sur échantillons :
   - Film numérique (Marvel, Pixar) → pas de boost
   - Film 35mm (Nolan, Tarantino) → boost détecté
   - Anime → pas de boost

### Phase 3 : Calibration

1. Tester sur un panel de films variés
2. Ajuster les seuils si nécessaire
3. Documenter les cas limites

---

## Structure des Fichiers à Modifier

```
lib/
├── constants.sh      # Ajouter ADAPTIVE_GRAIN_*
├── complexity.sh     # Ajouter _detect_grain_level(), modifier _map_metrics_to_complexity()
└── exports.sh        # Exporter les nouvelles constantes

tests/
└── test_film_adaptive.bats  # Ajouter tests grain

docs/
└── FILM_ADAPTIVE.md  # Documenter la fonctionnalité
```

---

## Risques et Mitigations

| Risque | Impact | Mitigation |
|--------|--------|------------|
| Faux positifs (textures confondues avec grain) | Bitrate trop élevé | Seuils conservateurs, option désactivée par défaut |
| Surcoût CPU | +10-20% temps d'analyse | Échantillonnage limité (3-5 positions) |
| FFmpeg sans filtre requis | Échec analyse | Fallback silencieux (pas de boost) |

---

## Validation de la Feature

- [ ] Prototype fonctionnel
- [ ] Tests unitaires passent
- [ ] Tests manuels sur 5+ films variés
- [ ] Documentation mise à jour
- [ ] Option activable/désactivable
- [ ] Fallback gracieux si filtres indisponibles
- [ ] Review du code

---

## Références

- ITU-T P.910 : Subjective video quality assessment methods
- Netflix Tech Blog : "Toward A Practical Perceptual Video Quality Metric"
- x265 documentation : `--noise-reduction` et `--film-grain`
- SVT-AV1 : `--film-grain` et `--film-grain-denoise`
