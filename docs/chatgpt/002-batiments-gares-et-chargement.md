# Message pour ChatGPT n°002 : lien bâtiment-gare et règle de chargement (jalon M3)

## 1. Contexte technique

Jalons M0 à M2 faits (carte, rails, gares, lignes, un train en aller-retour). J'attaque M3 : production, stocks, chargement/livraison, pièces. Contenu du niveau 1 : mine de charbon, scierie (bois), une ville qui consomme charbon et bois, gares fret, wagons charbon et bois.

Ce que le GDD fixe déjà et que j'applique : ressources naturelles inépuisables ; production si les intrants sont là et si la sortie n'est pas saturée ; stocks séparés et plafonnés par produit ; arrêt/reprise automatique ; tout échange entre bâtiments passe par le rail (chariots décoratifs) ; entrepôts de gare ; revenus = marchandises effectivement reçues par la ville, base unitaire par type + composante distance (trajet ferroviaire le plus court origine-destination) ; solde jamais négatif.

Pour M3, les bâtiments sont placés d'avance sur la carte de test (pas encore de construction de bâtiments) ; le joueur pose rails, gares et lignes.

## 2. Problème / décisions à prendre

Le GDD est muet sur deux règles qui changent le gameplay.

**D1. Comment un bâtiment est-il relié à une gare ?** La mine, la scierie et la ville ne sont pas sur les rails. Il faut une règle qui fait entrer leur production dans l'entrepôt d'une gare, et sortir de l'entrepôt les marchandises qu'ils consomment.

**D2. Que charge et décharge un train à chaque arrêt ?** La SPEC dit « selon le besoin réel des destinations », et « les marchandises non livrées restent à bord ». Il faut préciser la règle, car elle détermine quand le joueur est payé et où la marchandise s'accumule.

## 3. Solutions envisageables

**D1.**
- **A. Gare la plus proche dans un rayon de 2 cases** (distance de la case de la gare à l'emprise du bâtiment). Un bâtiment dépend d'une seule gare ; une gare peut en desservir plusieurs. Le lien est affiché (trait + rayon visible quand on pose une gare). Aucun geste supplémentaire pour le joueur.
- **B. Bâtiment contigu à la gare** (cases adjacentes). Très lisible, mais contraignant pour placer rails et gares sur une carte aux bâtiments fixes.
- **C. Raccord manuel** : le joueur relie explicitement un bâtiment à une gare par un geste. Plus de contrôle, un outil de plus à apprendre.

**D2.**
- **A. Selon le besoin réel :** à un arrêt, le train décharge seulement ce que les bâtiments de la gare peuvent recevoir (place libre dans leur stock d'intrant) et charge seulement ce que les autres gares de sa ligne demandent. Le reste reste à bord ou dans l'entrepôt.
- **B. Tout décharger, tout charger** : l'entrepôt sert de tampon, sans tenir compte de la demande. Plus simple, mais l'entrepôt se remplit de marchandises inutiles et le revenu n'arrive qu'après un transfert entrepôt-ville.
- **C. Hybride :** décharger tout dans l'entrepôt de la gare, mais ne charger que ce que les gares suivantes demandent.

Le revenu est crédité au moment où la marchandise entre dans le stock d'un consommateur (la ville), au prix base + distance (valeurs d'essai non validées).

## 4. Recommandation et conséquences

- **D1 : A** (gare la plus proche dans un rayon de 2 cases, lien visible). C'est le plus fluide sur mobile et cela reste conforme à « tout passe par le rail », puisque seul le trajet gare-bâtiment est décoratif. Conséquence : le joueur doit poser sa gare à proximité du bâtiment ; deux bâtiments proches d'une même gare partagent son entrepôt, ce que je gère par des stocks séparés par produit.
- **D2 : A** (selon le besoin réel). C'est ce que dit la SPEC, ça évite les entrepôts bloqués, et le revenu arrive à la livraison. Conséquence : une ligne dont aucune gare ne demande un produit ne le transporte pas ; le joueur voit pourquoi dans la fiche de la gare (« en attente d'un consommateur »).

Hypothèses de mise en œuvre que je prends sauf avis contraire :
1. **Composition fixe du train en M3 :** 1 wagon charbon + 1 wagon bois, capacité d'essai de 10 unités chacun. Le dépôt et l'écran de composition sont repoussés (le GDD place la composition au dépôt).
2. **Carburant des locomotives reporté :** pas de consommation de charbon par le train en M3, pour ne pas mélanger deux flux de charbon avant d'avoir validé le premier.
3. **Ville sans croissance :** elle consomme continuellement charbon et bois dans la limite de son stock, et on compte les livraisons ; pas de population ni de pénurie visible en M3.

## Ce que j'attends de ChatGPT

(a) Confirmer ou corriger D1 (A, B ou C) et D2 (A, B ou C). (b) Dire si les trois hypothèses ci-dessus sont acceptables pour le vertical slice. (c) Signaler toute règle du GDD qui contredit ces choix. Réponse courte et directe : Vincent tranche en dernier.

---

## Réponse de ChatGPT (2026-11-02, relevée dans la session)

- **D1 : option A** (rattachement automatique à la gare la plus proche dans un rayon de desserte ; le rayon de 2 cases est provisoire). Une gare peut desservir plusieurs bâtiments ; le bâtiment indique sa gare. Le transfert gare-bâtiment est automatique et sans wagon. Si deux gares peuvent desservir le même bâtiment : la plus proche, sans déplacer arbitrairement un stock existant.
- **D2 : option A** (chargement selon la demande réelle). Le train décharge les quantités effectivement acceptées ; ce qui n'est pas déchargé reste à bord ; revenu crédité uniquement à la réception par la ville. Les marchandises en transit pourront être déposées en entrepôt de correspondance (M4). **Ne pas limiter la demande aux seules gares suivantes d'une ligne** : le GDD prévoit des correspondances entre lignes.
- Hypothèses (composition fixe 1 wagon charbon + 1 wagon bois de 10 unités ; pas de carburant ; ville sans croissance) : acceptées pour M3, **temporairement** ; elles ne doivent pas devenir des règles définitives.
- Vigilance : (1) distinguer dès maintenant les marchandises en transit, celles destinées à un consommateur local, et les stocks des bâtiments ; (2) une ville n'est pas un puits infini : livraison limitée par sa capacité de stockage disponible.
- **Critère de validation de M3 :** observer la chaîne mine → gare → train → gare → ville, avec diminution du stock de charbon à la mine, augmentation du stock en ville, et crédit des pièces uniquement à la réception.

## Suite donnée (Claude Code)

Appliqué en M3 : D1-A et D2-A ; demande comptée sur **toutes les autres gares de la ligne** (pas seulement les suivantes) ; trois stocks séparés (bâtiments, entrepôts de gare, cargaison du train) avec lots portant leur gare d'origine ; ville limitée par sa capacité d'entrée. Décision finale : Vincent.
