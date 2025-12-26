# Instructions Copilot (repo)

Lis et applique en priorité les règles dans [agent.md](../agent.md).
## ⛔ PREMIÈRE ACTION OBLIGATOIRE

**Avant TOUTE modification de fichier, exécute :**

```bash
git branch --show-current
```

**Si la réponse est `main`, STOP !** Crée une branche AVANT de toucher au code :

```bash
git checkout -b fix/description-courte   # ou feature/, refactor/, docs/
```

Cette règle est **non négociable**. Ne jamais modifier directement `main`.
## Règles clés (résumé)

- Respecter la modularité : modifications localisées dans le bon module `lib/*.sh`.
- Maintenabilité > performance (sauf si mesuré et validé).
- Si changement non-trivial : proposer un plan + analyse + options **avant** d’exécuter.
- Si une fonction/comportement change : mettre à jour les tests Bats (`tests/*.bats`).
- Si CLI/logs/suffixes/comportement utilisateur change : mettre à jour le README.
- Après merge/rebase depuis `main` : relire/mettre à jour le README + relancer `bash run_tests.sh`.
- Commits : explicites, un sujet par commit, corps « un point par ligne ».
