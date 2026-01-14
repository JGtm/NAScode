# TODO

## Vidéo

### Clamp résolution pour film-adaptive (en observation)

**Contexte** : En mode `film-adaptive`, le bitrate est calculé par `BPP × largeur × hauteur × fps × C`. Pour une vidéo 720p très complexe, le modèle peut produire un `MAXRATE` élevé (ex: 2800 kbps) alors qu'en mode standard 720p, le budget serait plafonné à ~1764 kbps (70% du budget 1080p).

**Idée** : Ajouter un plafond pour que film-adaptive ne dépasse jamais le budget "standard" de la résolution de sortie :
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

## Refactorisation future (v3.0+)

- **Globals → Associative arrays** : reporté car les associative arrays ne peuvent pas être exportés vers des sous-shells (`convert_file` en parallèle). Conserver les variables séparées, documentées dans `lib/constants.sh`.

