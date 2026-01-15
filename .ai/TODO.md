# TODO

## Vidéo

### Détection de grain pour mode adaptatif

**Statut** : À implémenter (Phase 2)

**Contexte** : Le mode `adaptatif` utilise 3 métriques (stddev, SI, TI) pour calculer le coefficient de complexité. Cependant, les films avec grain de pellicule (35mm, 16mm, grain ajouté en post-production) peuvent nécessiter un traitement spécial car :
1. Le grain augmente artificiellement le SI mais de manière uniforme
2. Le grain est difficile à compresser sans artefacts
3. Un bitrate insuffisant produit un effet "lissé" ou des blocs visibles

**Objectif** : Détecter automatiquement la présence de grain et ajuster C en conséquence :
- Grain détecté → `C = C × 1.10` à `C × 1.15` (boost de 10-15%)

**Options d'implémentation** :

| Option | Principe | Avantages | Inconvénients |
|--------|----------|-----------|---------------|
| **A** (recommandé) | Variance haute fréquence via `edgedetect` | Simple, CPU modéré | Confusion grain/textures |
| **B** | Débruitage comparatif (`hqdn3d`) | Très précis | Plus lent |
| **C** | Machine Learning | Optimal | Complexité hors scope v1 |

**Constantes à ajouter** (`lib/constants.sh`) :
```bash
ADAPTIVE_GRAIN_DETECTION="${ADAPTIVE_GRAIN_DETECTION:-false}"
ADAPTIVE_GRAIN_THRESHOLD_LOW="${ADAPTIVE_GRAIN_THRESHOLD_LOW:-5}"
ADAPTIVE_GRAIN_THRESHOLD_HIGH="${ADAPTIVE_GRAIN_THRESHOLD_HIGH:-15}"
ADAPTIVE_GRAIN_BOOST_FACTOR="${ADAPTIVE_GRAIN_BOOST_FACTOR:-1.10}"
```

**Fichiers à modifier** :
- `lib/constants.sh` : constantes grain
- `lib/complexity.sh` : `_detect_grain_level()`, intégration dans `_map_metrics_to_complexity()`
- `lib/exports.sh` : export des nouvelles fonctions
- `tests/test_adaptatif.bats` : tests grain
- `docs/ADAPTATIF.md` : documentation

**Validation** :
- [ ] Prototype fonctionnel
- [ ] Tests unitaires
- [ ] Tests manuels (5+ films variés)
- [ ] Fallback si filtres indisponibles

---

### Clamp résolution pour mode adaptatif (en observation)

**Contexte** : En mode `adaptatif`, le bitrate est calculé par `BPP × largeur × hauteur × fps × C`. Pour une vidéo 720p très complexe, le modèle peut produire un `MAXRATE` élevé (ex: 2800 kbps) alors qu'en mode standard 720p, le budget serait plafonné à ~1764 kbps (70% du budget 1080p).

**Idée** : Ajouter un plafond pour que le mode adaptatif ne dépasse jamais le budget "standard" de la résolution de sortie :
```
ADAPTIVE_MAXRATE = min(calculé_BPP_C, plafond_résolution)
```

**Bénéfices potentiels** :
- Évite les fichiers 720p/480p "trop gros" sur contenus complexes
- Cohérence avec le mode standard pour les petites résolutions
- Gain potentiel de 10-30% sur certains fichiers basse résolution

**Risques identifiés** :
- ⚠️ **Double-compte** : la résolution est déjà dans la formule BPP — risque de sous-encoder
- ⚠️ **Edge cases** : un film 720p très complexe pourrait être bridé injustement (artefacts)
- Complexité ajoutée au calcul

**Décision (2026-01-14)** : Laisser en observation. Le modèle BPP × C est déjà auto-adaptatif à la résolution. Implémenter uniquement si des cas problématiques émergent en production (fichiers 720p anormalement gros).

---

## Refactorisation future (v3.0+)

- **Globals → Associative arrays** : reporté car les associative arrays ne peuvent pas être exportés vers des sous-shells (`convert_file` en parallèle). Conserver les variables séparées, documentées dans `lib/constants.sh`.

