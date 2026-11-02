# Message pour ChatGPT n°001 : rebroussement des trains et lignes A-B-C-B-A

## 1. Contexte technique

Prototype Godot, jalons M0 à M2 faits (carte iso, rails sur grille logique à 8 directions, gares, aiguillages automatiques, une ligne avec un train en aller-retour).

Règles de circulation actuellement implémentées (défauts d'essai, non validés) :

- Un train ne tourne que de **45° maximum par case**. À la pose, un virage à 90° ou un « T » franc est refusé (« virage trop serré »). Le joueur arrondit en deux virages de 45°. Cela correspond à « courbes adoucies graphiquement » du GDD.
- Un train **ne peut pas faire demi-tour en pleine voie**. Il ne rebrousse que **dans une gare** (terminus ou gare intermédiaire).
- À la création d'une ligne, chaque tronçon entre deux gares consécutives doit avoir un itinéraire praticable dans les deux sens. Sinon la ligne est refusée avec « Pas de voie praticable entre deux gares ».

## 2. Problème / décision à prendre

Le GDD dit : « Une ligne est une liste ordonnée de gares, parcourue en aller-retour (A-B-C-B-A), **sans boucle obligatoire** ». La règle ci-dessus crée un cas où une ligne que le joueur trouvera naturelle est refusée.

Exemple : une voie principale avec un aiguillage et une branche en Y. Les gares A (à l'ouest) et B (tronc, à l'est) sont sur la voie principale, la gare C est au bout de la branche qui diverge vers l'est.

- A → C : possible (le train prend la branche).
- C → B : **impossible**. Revenu de C, le train arrive à l'aiguillage en direction du sud-ouest et devrait repartir vers l'est, soit un virage de 135°. Les deux bras « est » du Y partent du même côté ; passer de l'un à l'autre exige un rebroussement au niveau de l'aiguillage, comme dans la réalité.
- Une ligne A-C-B est donc refusée, alors que A-C et A-B passent. La contrainte est physique, mais elle n'est pas écrite dans le GDD, et un joueur de niveau 1 peut la rencontrer dès qu'il pose un embranchement.

Question : doit-on conserver cette rigueur physique, ou assouplir pour que « pas de boucle obligatoire » soit toujours vrai pour n'importe quel enchaînement de gares reliées par rail ?

## 3. Solutions envisageables

- **A. Garder la règle physique** (état actuel). Rebroussement uniquement en gare. Améliorer le retour visuel : indiquer quel tronçon bloque et pourquoi (« C → B exige un demi-tour : ajoutez un terminus ou une boucle »). Aucun nouveau contenu de gameplay.
- **B. Autoriser le rebroussement à tout aiguillage.** Le train s'arrête, change de sens et repart (arrêt court, quelques secondes). Toute ligne reliée par rail est valide. Simple à implémenter, mais le rôle de l'aiguillage change (ce n'est plus un simple embranchement) et la sécurité devient plus délicate au jalon M4 (deux trains pouvant rebrousser au même point).
- **C. Ajouter une pièce dédiée** (« voie de dégagement », triangle de retournement, ou plaque tournante) que le joueur construit pour rebrousser en ligne. Fidèle à l'esprit ferroviaire du XIXᵉ siècle et crée un objectif de construction, mais c'est un nouveau système (contenu, coût, déblocage par niveau) absent du GDD.
- **D. Assouplir la courbure** (autoriser des virages à 90° aux aiguillages) pour que le Y puisse être traversé dans les deux sens. Ne règle pas le problème de fond : le virage nécessaire est de 135°.

## 4. Recommandation et conséquences

Recommandation : **A pour le prototype**, avec un meilleur retour visuel (c'est ce que je ferai sans autre échange), et noter **C** comme piste pour après le vertical slice.

- **Pourquoi :** la contrainte est réaliste, rend les aiguillages et les terminus intéressants, et ne touche aucun invariant de sécurité préparé pour M4. B contredit le principe « tous les trains respectent la sécurité des sections » plus qu'il ne l'aide, et C est un nouveau système interdit par CLAUDE.md pour le premier vertical slice.
- **Conséquences si A :** certaines lignes sont refusées tant que le joueur n'a pas de terminus ou de boucle. Il faut s'assurer que la carte de départ et les niveaux 1 à 3 n'imposent pas ce cas (les gares du niveau 1 sont sur une voie simple). C'est un point à vérifier dans le GDD : confirmer qu'aucun niveau ne suppose un embranchement avec rebroussement hors gare.
- **Si B ou C :** il faut reprendre une partie de M2 (rebroussement, itinéraires) et ajouter des tests de sécurité en M4.

Ce que j'attends de ChatGPT : (1) dire si la règle « rebroussement en gare uniquement » est compatible avec l'intention du GDD ; (2) confirmer qu'aucun niveau 1 à 3 ne suppose un rebroussement hors gare ; (3) trancher entre A, B et C, ou proposer une autre piste.

---

## Réponse de ChatGPT (2026-11-02, relevée dans la session)

- (a) Compatible avec le GDD : « sans boucle obligatoire » signifie qu'un train inverse son sens aux terminus, pas qu'il peut manœuvrer librement à un aiguillage.
- (b) Aucun objectif validé des niveaux 1 à 3 n'exige de rebroussement hors gare ; le joueur doit pouvoir comprendre pourquoi deux gares reliées physiquement ne garantissent pas un trajet.
- (c) **Option A** : rebroussement en gare uniquement, virages de 45° par case, validation des itinéraires dans les deux sens, message explicite si une ligne est impossible. Point d'attention : une gare ne permet pas de rebrousser « magiquement » à travers des voies déconnectées ; l'itinéraire respecte toujours la géométrie des rails. Option C : piste d'évolution, pas avant une nouvelle décision de gameplay. Au moins un exemple A-B-C-B-A fonctionnel dans les tests.

## Suite donnée (Claude Code)

Règles inchangées. Ajout : le refus d'une ligne indique le tronçon bloquant et la cause (demi-tour hors gare ou gares non reliées) ; test du message ; l'exemple A-B-C-B-A existait déjà (`test_three_stations_visit_order_a_b_c_b_a`). Décision finale : Vincent.
