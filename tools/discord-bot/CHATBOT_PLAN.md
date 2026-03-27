# Plan d'implémentation — Bot Discord NAScode (Langage Naturel)

> Objectif : piloter `nascode` en langage naturel via Discord, depuis le NAS Synology, sans exposer de surface d'attaque.

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture technique](#2-architecture-technique)
3. [Composants à créer](#3-composants-à-créer)
4. [Étapes d'implémentation](#4-étapes-dimplémentation)
5. [Sécurité](#5-sécurité)
6. [Déploiement Synology](#6-déploiement-synology)
7. [Fonctionnalités du bot](#7-fonctionnalités-du-bot)
8. [Extensions futures](#8-extensions-futures)
9. [Prérequis](#9-prérequis)

---

## 1. Vue d'ensemble

```
Tu (Discord mobile/desktop)
  │
  │  "convertis mes films en HEVC, 2 jobs"
  ▼
Bot Discord (container Python sur le NAS)
  │
  │  1. Appel LLM → JSON structuré + validé
  │  2. Confirmation utilisateur (réaction ✅/❌)
  │  3. Exécution nascode
  ▼
nascode + ffmpeg (container ou processus hôte)
  │
  └──► Notification Discord de fin (notify_discord.sh existant)
```

Avantages de cette approche :
- Zéro port exposé sur Internet (Discord est le canal)
- Confirmation avant exécution → pas d'accident
- Le LLM ne peut produire que des arguments whitelistés
- Réutilise les notifications Discord déjà intégrées dans `lib/notify_discord.sh`

---

## 2. Architecture technique

### Flux de données

```
Message Discord
  └─► on_message()
        ├─► parse_natural_language(text)   ← appel LLM
        │     └─► SYSTEM_PROMPT + schéma JSON strict
        │           └─► { source, codec, jobs, ... }
        ├─► validation JSON Schema (additionalProperties: false)
        ├─► affichage commande générée + demande confirmation
        ├─► attente réaction ✅/❌ (timeout 30s)
        └─► subprocess.run(nascode, args, timeout=7200)
              └─► Discord : extrait final stdout/stderr
```

### Choix LLM

| Option | Avantages | Inconvénients | Recommandé si |
|--------|-----------|---------------|---------------|
| **OpenAI GPT-4o mini** | Excellent, rapide, ~$0.001/appel | Données envoyées à OpenAI | Simplicité de setup |
| **Ollama local (Llama 3.2 3B)** | 100% local, gratuit | ~2 GB RAM, container lourd | NAS avec 4+ GB RAM libre |
| **Claude API (Anthropic)** | Très bonne compréhension | Plus cher | Si déjà abonné |

**Recommandation par défaut : OpenAI GPT-4o mini** (rapport qualité/coût/complexité optimal).

---

## 3. Composants à créer

```
tools/discord-bot/
├── PLAN.md                  ← ce fichier
├── bot.py                   ← bot Discord principal
├── Dockerfile               ← image Python légère
├── docker-compose.yml       ← déploiement NAS Synology
├── requirements.txt         ← dépendances Python
├── config.example.env       ← variables d'environnement (template)
└── README.md                ← guide de déploiement rapide
```

---

## 4. Étapes d'implémentation

### Étape 1 — Créer l'application Discord (5 min)

1. Aller sur [discord.com/developers/applications](https://discord.com/developers/applications)
2. **New Application** → donner un nom (ex: `NAScode Bot`)
3. Onglet **Bot** → copier le **Token** (à mettre dans `.env`)
4. Activer l'intent **"Message Content"** (Privileged Gateway Intents)
5. Onglet **OAuth2 → URL Generator** :
   - Scopes : `bot`
   - Permissions : `Send Messages`, `Read Messages/View Channels`, `Add Reactions`
6. Ouvrir l'URL générée → inviter le bot sur ton serveur

### Étape 2 — Obtenir son User ID Discord

1. Dans Discord : Paramètres → Avancés → activer **Mode développeur**
2. Clic-droit sur ton avatar → **Copier l'identifiant**
3. Mettre cette valeur dans `ALLOWED_USER_IDS` dans `bot.py`

### Étape 3 — Créer la clé OpenAI (si option cloud)

1. [platform.openai.com/api-keys](https://platform.openai.com/api-keys) → Create new secret key
2. Ajouter au `.env` : `OPENAI_API_KEY=sk-...`
3. (Optionnel) Définir une limite de dépense mensuelle dans les paramètres billing

### Étape 4 — Implémenter `bot.py`

Composants du bot :

```
bot.py
├── Configuration
│   ├── ALLOWED_USER_IDS       : set d'IDs Discord autorisés
│   ├── NASCODE_PATH           : chemin absolu du script nascode
│   ├── SYSTEM_PROMPT          : prompt LLM avec chemins du NAS
│   └── NASCODE_SCHEMA         : JSON Schema strict (whitelist des args)
│
├── parse_natural_language()
│   ├── Appel API LLM avec response_format JSON Schema
│   └── Retourne dict validé ou None
│
├── args_from_params()
│   ├── Convertit dict JSON → liste d'args CLI
│   └── Sécurité : valeurs strippées, aucun subprocess shell=True
│
└── on_message()                : handler principal
    ├── Vérification auteur (whitelist)
    ├── Préfixe "!nas "
    ├── LLM → JSON
    ├── Affichage + confirmation réaction
    └── subprocess.run(nascode)
```

Points critiques de `NASCODE_SCHEMA` :
- `"additionalProperties": false` → bloque toute clé inventée par le LLM
- Valeurs `enum` pour codec, mode, audio → pas d'injection
- `"pattern"` regex pour `min_size` (ex: `"^[0-9]+[KMG]$"`)
- `"minimum"/"maximum"` pour `jobs` (1–8)

### Étape 5 — Dockerfile et docker-compose

**Dockerfile** :
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bot.py .
CMD ["python", "-u", "bot.py"]
```

**docker-compose.yml** :
```yaml
services:
  nascode-bot:
    build: .
    restart: unless-stopped
    env_file: .env
    volumes:
      - /volume1/scripts/NAScode:/scripts:ro      # nascode en lecture seule
      - /volume1/Video:/volume1/Video:ro           # médias en lecture seule
      - /Converted:/Converted                      # sortie en lecture/écriture
    # Pas de ports exposés — le bot se connecte à Discord en sortant
```

**requirements.txt** :
```
discord.py>=2.3
openai>=1.30
jsonschema>=4.22
```

### Étape 6 — Déployer sur Synology

1. Copier le dossier `tools/discord-bot/` sur le NAS (SSH ou File Station)
2. Créer `.env` depuis `config.example.env`, remplir les valeurs
3. Via **Container Manager → Projets → Créer** → pointer vers le `docker-compose.yml`
4. Démarrer le projet → vérifier les logs du container

### Étape 7 — Tester

Séquence de test recommandée :
```
!nas simulation: convertis 2 films en HEVC
  → vérifier la commande affichée
  → confirmer ✅
  → vérifier que nascode --dry-run s'exécute sans erreur

!nas convertis les séries en AV1 avec 3 jobs
  → vérifier le JSON produit par le LLM
  → vérifier la commande CLI correspondante
```

---

## 5. Sécurité

### Vecteurs d'attaque et mitigations

| Vecteur | Mitigation |
|---------|------------|
| **Injection de commande via LLM** | `additionalProperties: false` + enum stricts → le LLM ne peut produire que des valeurs connues |
| **Accès non autorisé au bot** | `ALLOWED_USER_IDS` hardcodé + vérification sur chaque message |
| **Prompt injection dans le message** | Le message utilisateur va dans le `content` user, pas dans le system prompt ; le schéma JSON force la structure |
| **Dépassement de ressources** | `timeout=7200` sur subprocess ; `--jobs` limité à 8 |
| **Accès aux fichiers système** | Volumes Docker : `/scripts` en `:ro`, médias en `:ro` ; sortie seule en `:rw` |
| **Token Discord exposé** | Variable d'environnement uniquement, jamais dans le code ; `.env` dans `.gitignore` |
| **Escalade de privilèges** | Container sans `--privileged`, sans `cap_add` |

### Ce que le bot NE peut PAS faire

- Exécuter de commandes arbitraires (pas de `shell=True`)
- Utiliser des flags non whitelistés
- Accéder à des chemins hors des volumes montés
- Être déclenché par quelqu'un d'autre que toi

---

## 6. Déploiement Synology

### Prérequis NAS

- DSM 7.x
- **Container Manager** installé (anciennement Docker)
- RAM disponible : ≥ 512 MB (bot seul) ou ≥ 4 GB (avec Ollama local)
- `nascode` déjà fonctionnel sur le NAS (bash + ffmpeg installés)

### Variante Ollama 100% local

Si tu ne veux pas dépendre d'OpenAI :

```yaml
# dans docker-compose.yml
  ollama:
    image: ollama/ollama
    volumes:
      - ollama_data:/root/.ollama
    # Pas de GPU sur Synology → CPU only, ~5s par requête avec Llama 3.2 3B
```

Dans `bot.py`, remplacer l'appel OpenAI :
```python
import requests, json

def parse_natural_language(text: str) -> dict:
    resp = requests.post("http://ollama:11434/api/generate", json={
        "model": "llama3.2",
        "prompt": SYSTEM_PROMPT + "\n\nDemande : " + text + "\n\nJSON uniquement :",
        "format": "json",
        "stream": False
    }, timeout=60)
    return json.loads(resp.json()["response"])
```

---

## 7. Fonctionnalités du bot

### Commandes prévues

| Commande | Description |
|----------|-------------|
| `!nas <demande>` | Commande principale en langage naturel |
| `!nas status` | Affiche les jobs nascode en cours (`pgrep + ps`) |
| `!nas stop` | Envoie SIGTERM aux processus nascode en cours |
| `!nas help` | Exemples de formulations reconnues |

### Exemples de langage naturel reconnus

```
!nas convertis mes films en HEVC
!nas encode les séries en AV1 avec 3 jobs en parallèle
!nas fais une simulation sur les films, ignore les fichiers < 500M
!nas 2 passes sur mes films, audio en opus
!nas convertis uniquement 5 films pour tester
!nas régénère l'index
!nas lance en heures creuses uniquement
```

---

## 8. Extensions futures

- **`!nas status`** : affichage des jobs en cours via `pgrep nascode | xargs ps`
- **Logs en streaming** : utiliser `asyncio.subprocess` pour envoyer les logs au fur et à mesure
- **Boutons Discord** (discord.py `View`) : remplacer les réactions par des boutons "Lancer" / "Annuler"
- **Historique des lancements** : fichier JSON local de log des commandes exécutées
- **Planification** : `!nas demain à 2h, convertis les films` → cron job dynamique
- **Support Telegram** : même logique, remplacer `discord.py` par `python-telegram-bot`

---

## 9. Prérequis

### Côté NAS

- [ ] Container Manager (DSM 7.x)
- [ ] `nascode` opérationnel (bash + ffmpeg)
- [ ] Chemins des médias identifiés (`/volume1/Video/...`)

### Côté Discord

- [ ] Serveur Discord personnel ou privé
- [ ] Application créée sur discord.com/developers
- [ ] Token bot copié
- [ ] User ID récupéré (mode développeur)
- [ ] Intent "Message Content" activé

### Côté LLM (option cloud)

- [ ] Compte OpenAI
- [ ] Clé API créée
- [ ] Limite de dépense configurée (recommandé : $5/mois)

---

*Plan créé le 24 mars 2026 — à implémenter dans `tools/discord-bot/`.*
