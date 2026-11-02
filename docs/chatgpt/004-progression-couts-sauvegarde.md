# Échange n°004 : progression niveaux 1 à 3, coûts, sauvegarde (jalon M5)

## Message de Claude Code (résumé)

Contexte : M4 validé. Pour M5 (sauvegarde/reprise, niveaux 1 à 3, test mobile), cinq questions : **Q1** mécanique de montée de niveau (A : dépôt physique approvisionné par train + bouton « Améliorer » ; B : automatique sur compteurs ; C : pièces et objectifs sans matériaux) ; **Q2** contenu débloqué (N2 carrière + wagon pierre, 2e mine/scierie ; N3 mine de fer + aciérie 2 minerai + 1 charbon → 1 acier + wagon acier + 2e train) ; **Q3** coûts d'essai (rail 1 pièce, gare 10, départ 100, remboursement 50 %) ; **Q4** un wagon de 10 unités par produit débloqué, sans écran de composition ; **Q5** reprise après absence : état exact restauré + rattrapage plafonné à 10 minutes de jeu (le 24 h complet est trop lent sur téléphone). Recommandation : Q1-A, le reste comme proposé.

## Réponse de ChatGPT (2026-11-02, relevée dans la session)

| Sujet | Décision |
|---|---|
| Q1 | **A** : dépôt physique approvisionné par train, objectifs permanents, bouton « Améliorer » |
| Q2 | Accepté avec corrections : conserver les nouvelles industries et marchandises, **sans faire des 2e mines/scieries des nouveautés obligatoires** |
| Q3 | Accepté pour les tests : rail 1 pièce, gare 10, départ 100, remboursement 50 % |
| Q4 | Accepté temporairement : un wagon par produit débloqué, sans écran de composition |
| Q5 | Accepté temporairement : 10 minutes ; **le rattrapage complet de 24 h reste une exigence du jeu final** |

Conditions de progression proposées (valeurs provisoires, modifiables dans `content.json`) :

| Progression | Matériaux livrés au dépôt | Objectif permanent | Coût |
|---|---|---|---|
| N1 → N2 | 20 bois + 20 charbon | Livrer 40 unités à la ville, dont au moins 10 de chaque produit | 75 pièces |
| N2 → N3 | 25 bois + 20 pierre + 15 charbon | Livrer 30 unités de pierre à la ville et disposer d'une ligne opérationnelle | 150 pièces |

Précisions : les livraisons à la ville sont cumulées depuis le début du niveau concerné ; les pièces doivent être disponibles au moment de l'amélioration (pas le total gagné) ; les matériaux doivent être **présents dans le stock du dépôt et consommés** à l'amélioration, pas seulement comptés comme livraisons historiques.

Corrections et précautions : (1) éviter un blocage économique au niveau 1 : test garantissant que le réseau initial coûte moins que le budget, avec marge ; (2) le charbon du dépôt est distinct de celui de la ville : une livraison a une destination précise, sans double comptage ; (3) ne pas modifier silencieusement les déblocages validés du GDD (amélioration de locomotive, de gare, de bâtiments au N2 ; wagon de fer au N3) : hors périmètre du prototype mais pas supprimés du GDD ; (4) aciérie 2 minerai + 1 charbon → 1 acier acceptable en essai, le minerai suit les mêmes règles ferroviaires ; (5) respecter plus tard les limites de traction pour la composition ; (6) **isoler le rattrapage hors ligne dans un composant indépendant** pour permettre plus tard un calcul simplifié sur 24 h sans rejouer chaque pas.

Critère de validation de M5 : commencer au niveau 1, exploiter son réseau pour gagner des pièces, alimenter son dépôt, puis atteindre le niveau 3 **sans intervention technique ni modification manuelle des données**.

## Suite donnée (Claude Code)

Appliqué : Q1-A avec le tableau ci-dessus dans `content.json` ; les 2e mines/scieries ne sont pas des déblocages (seuls carrière, mine de fer, aciérie, wagons et capacité de trains) ; coûts d'essai ; rattrapage dans un composant dédié ; test automatisé de progression complète du niveau 1 au niveau 3 sans toucher aux données. Décision finale : Vincent.
