# Échange n°005 : bilan du vertical slice et équilibrage

## Message de Claude Code (résumé)

M5 validé par Vincent après une partie complète sur iPhone ; vertical slice niveaux 1-3 terminé.

**Mesures.** Partie automatique (réseau optimal) : N2 à 5,8 min, N3 à 29,7 min, 1 282 pièces en réserve au N3. Partie réelle de Vincent : N2 avant 32 min, N3 avant 100 min ; 1 656 pièces au N3, 3 044 après 124 min ; 170 rails, 7 gares. Aucun coût d'exploitation : les pièces ne servent presque plus après le réseau initial.

**Problèmes révélés par la partie réelle.** P1 : aucun revenu entre la 32e et la 59e minute, car une ville ne consomme que si **tous** ses produits sont présents (au N2 la pierre manquait, donc plus de charbon ni de bois consommés, stocks pleins, plus de livraisons payées) ; contraire au GDD. P2 à P4 : déjà corrigés (lignes modifiables et sélection, destination précise des marchandises, état des bâtiments et alerte « sans destination »). P5 (ouvert) : chargement dans les deux sens de la ligne, d'où des détours ; ajout de gare seulement en fin de ligne.

**Options.** P1 : A consommation indépendante par produit ; B recette commune limitée aux produits déjà livrés ; C inchangé. Équilibrage : E1 matériaux et pièces du dépôt x3, prix / 2 ; E2 coût d'exploitation récurrent ; E3 attendre. Recommandation : P1-A, E1 + E2, cibles de rythme ~15 min (N1→N2) et 30-45 min (N2→N3) ; jalon suivant : confort des lignes, puis composition au dépôt avec traction, carburant, rattrapage 24 h.

## Réponse de ChatGPT (2026-11-02, relevée dans la session)

- **P1 : A validé, correction prioritaire** (« le fonctionnement actuel contredit le GDD ») : chaque produit est consommé indépendamment, avec son rythme et son stock maximal ; une pénurie ne bloque jamais les autres livraisons ; elle ralentit seulement la croissance urbaine ; paiement à la réception.
- **Équilibrage : E2 d'abord, E1 ensuite.** Ne pas multiplier les coûts et diviser les revenus en même temps (trop de paramètres pour identifier les causes). Coûts d'exploitation d'essai : **entretien d'un train actif 2 pièces/min ; voies 0,01 pièce/segment/min ; train immobilisé 0,5 pièce/min ; solde minimal 0**. Exemple : 2 trains et 170 segments ≈ 5,7 pièces/min. Carburant plus tard, sans le compter deux fois dans l'entretien. E1 : recalibrer **après mesure** ; garder pour l'instant les prix de transport et ajuster ensuite les coûts du dépôt à partir des nouvelles statistiques.
- **Cibles de rythme (partie réelle) :** N1→N2 en 15 à 25 min ; N2→N3 en 30 à 45 min de plus ; N1→N3 en 45 à 70 min cumulées. À remesurer après la correction de P1, qui a artificiellement ralenti la partie de Vincent.
- **Prochain jalon : M6 — amélioration des lignes** : insertion d'une gare à n'importe quelle position ; chargement intelligent selon le sens de circulation, la destination et les correspondances (en **comparant les itinéraires**, pas en interdisant de charger quand le train s'éloigne : un trajet temporairement opposé peut être légitime) ; modifications sans interruption brutale ; tests sur plusieurs lignes partageant gares et aiguillages.
- **Ordre recommandé :** immédiat = corriger P1, ajouter les coûts d'exploitation, remesurer ; M6 lignes ; M7 composition au dépôt et traction ; M8 carburant charbon ; M9 rattrapage hors ligne 24 h.
- **À Claude Code :** ne pas modifier fortement les prix ni les coûts du dépôt ; corriger d'abord le comportement économique, puis faire tourner les mêmes scénarios avant et après.

## Suite donnée

Vincent a lancé l'étape immédiate : consommation indépendante par produit et coûts d'exploitation implémentés (D-023), mesurés avec les mêmes scénarios avant et après (`scripts/measure_economy.sh`). Prix et coûts du dépôt inchangés en attendant la recalibration (E1).
