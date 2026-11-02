# Décisions et questions ouvertes

Chaque entrée : défaut retenu (simple et réversible), statut.

## D-001 — Orientation d'écran
Ni le GDD ni la SPEC ne fixent portrait ou paysage. **Défaut : paysage** (`sensor_landscape`, viewport 1280×720, étirement `canvas_items`, ratio `expand`). Changement : `project.godot` > `display/window/handheld/orientation`. *À valider.*

## D-002 — Taille des cases
Losange 2:1 de 128×64 px à zoom 1, dans `data/world_config.tres`. Provisoire, dépend des futurs assets. *À valider.*

## D-003 — Moteur de rendu
`gl_compatibility` pour la couverture maximale des téléphones. À rouvrir si des effets nécessitent le renderer « mobile ». *À valider.*

## D-004 — Rendu de la carte
Dessin direct (`_draw`) de losanges colorés, avec élimination des cases hors écran, plutôt que `TileMapLayer` : aucun asset ni tileset nécessaire en M0. À réévaluer sur mesure de performance sur appareil.

## D-005 — Carte de test
Générateur 100 % entier (hachage maison), seed 1865, `generator_version` 1. L'empreinte de la carte est figée dans `tests/test_world_map.gd` : toute modification du générateur doit s'accompagner d'une incrémentation de `generator_version` et d'une mise à jour consciente de l'empreinte.

## D-006 — Sans `class_name`
Les scripts se référencent par `preload` plutôt que par `class_name`, pour que les tests headless fonctionnent sans passer par l'import de l'éditeur. À reconsidérer si le nombre de scripts rend les `preload` pénibles.

## D-007 — Rattrapage de simulation
En temps réel, `SimClock` plafonne les pas par frame (25) et abandonne le retard au-delà. Le rattrapage hors ligne (24 h, GDD) devra passer par une voie dédiée de pas en lot (M5), non encore conçue.

## D-008 — Règles de pose des rails (M1)
Défauts d'essai, tous dans `RailNetwork` :
- Voisinage à 8 directions ; terrain constructible = tout sauf l'eau (le pont du niveau 2 est reporté, pas de passage préconstruit en M1).
- **Pas de croisement de deux diagonales** sans case commune (refusé). Les « croisements automatiques » du GDD restent à faire.
- **Rayon de courbure** : un train ne tourne que de 45° par case. À la pose, un nouveau segment doit pouvoir s'enchaîner avec un segment existant de la case (angle ouvert >= 135°), sinon « Virage trop serré ». Conséquence : pas de T à 90° ni de coin à 90°, il faut arrondir en deux virages de 45°. Le pathfinding applique la même règle (demi-tour interdit hors terminus, à traiter en M2).
- **Aiguillage** = case de degré >= 3, déduit du graphe (jamais stocké).
- Suppression d'un rail occupé : sans objet tant qu'il n'y a pas de train (M4).
- **Pas de coût** de pose en M1 : l'économie arrive avec M3.
*À valider (notamment le rayon de courbure, qui contraint le tracé).*

## D-009 — Gares (M1)
Une case, un axe parmi 4 (SE-NO, S-N, SO-NE, O-E en vue écran), type `freight`. Les rails ne se raccordent que le long de l'axe. Entrepôt et capacités : M3.

## D-010 — Saisie en construction
Réponse à la question ouverte sur glisser = pan ou pose : **modes explicites** via une barre d'outils (Naviguer / Rails / Gare / Gomme). En mode construction, un doigt trace ; un second doigt annule le tracé et active pincement/zoom. Le tracé suit le doigt, reculer l'annule, et seule la partie valide est posée au relâchement avec un message de refus. Un toucher qui démarre sous la barre est ignoré par la caméra. `emulate_mouse_from_touch` est réactivé pour que les boutons répondent au toucher. *À valider à l'usage sur téléphone.*

## D-011 — Trains et lignes (M2)
Défauts d'essai, tous dans `data/world_config.tres` sauf mention :
- **Vitesse** 2 cases/s, **arrêt en gare** 3 s, **nouvel essai** d'itinéraire toutes les 1 s ; longueur logique d'un segment : 1000 milli-cases en droit, 1414 en diagonale (`direction.gd`).
- **Un seul train** (`max_trains = 1`) : pas de répartiteur avant M4, donc pas de risque de collision. M4 porte la limite à 2 au niveau 3.
- **Rebroussement uniquement en gare** : en ligne, le rayon de courbure (D-008) interdit le demi-tour. Conséquence : une ligne dont un tronçon exige de faire demi-tour hors gare est refusée à la création (« Pas de voie praticable entre deux gares »). Ex. : A-C-B avec C au bout d'une branche d'aiguillage divergente. Il faudra une boucle ou un terminus pour rebrousser.
- **Aller-retour** : à chaque terminus le sens s'inverse ; les gares traversées sans être sur la ligne ne provoquent pas d'arrêt.
- **Ligne non modifiable** après création (le GDD prévoit un changement appliqué après le prochain arrêt : reporté). On la retire (« Retirer ») et on la recrée.
- **Protections** : un segment sous un train ne peut pas être effacé, une gare d'une ligne non plus. Une voie retirée devant le train est détectée à la case suivante : il replanifie ou attend (rouge), puis repart après reconnexion. Ces protections préfigurent la règle M4 « suppression d'un rail occupé : attend la libération ».
- Simulation en **entiers** (milli-cases) ; positions flottantes réservées au rendu, interpolé entre deux pas.
*Valeurs d'équilibrage à valider.* **Rebroussement en gare uniquement : avis fonctionnel de ChatGPT du 2026-11-02 (échange 001, `docs/chatgpt/001-rebroussement-et-lignes.md`) = option A**, compatible avec le GDD ; aucun niveau 1 à 3 n'exige de rebroussement hors gare ; pas de système de retournement (option C) avant nouvelle décision de gameplay ; messages d'erreur explicites exigés et un exemple A-B-C-B-A en test (déjà couvert). *Décision finale de Vincent : à confirmer.*

## D-012 — Test sur simulateur iOS et zones sûres
- Chaîne reproductible : `scripts/build_ios_sim.sh` (export du projet Xcode via un préréglage `export_presets.cfg`, puis `xcodebuild` sans signature). L'identifiant d'équipe `AAAAAAAAAA` du préréglage est factice, suffisant pour le simulateur ; un vrai identifiant sera nécessaire pour un téléphone. Bundle id provisoire : `com.trainwork.prototype`. Icône provisoire : `icon.svg`.
- **Constats iOS (iPhone 17, simulateur) :** le jeu démarre en paysage, la simulation suit le temps réel malgré 15-20 FPS (simulateur), les boutons répondent au toucher, le tracé de rails au doigt est validé au relâchement, le pincement atteint le zoom maximal sans tracer de rail en mode Rails.
- **Défaut corrigé :** la barre d'outils et le HUD ignoraient les zones sûres (indicateur d'accueil, îlot dynamique). `Main._apply_safe_area` décale maintenant l'interface avec `DisplayServer.get_display_safe_area()` ; sans effet sur ordinateur.
- Le HUD de debug affiche le dernier toucher reçu et la taille du viewport (diagnostic mobile).
- **Limite du banc de test :** pour une app en paysage, l'outil de simulateur injecte les touches avec des axes non pivotés : seule la zone x ≤ 720, y ≤ 720 du jeu (conversion : point écran de jeu × 0,558) est atteignable, donc les boutons Gare, Ligne, Gomme et la moitié droite de la carte ne se testent pas ainsi. Ce n'est pas un défaut du jeu ; ces parties restent couvertes par les tests automatiques et à vérifier sur un vrai téléphone.
*Non testé sur simulateur : mode Gare/Ligne, train en marche, performances réelles (FPS du simulateur non représentatif).*

## D-013 — Déploiement sur iPhone réel
- Appareil : « iPhone de Vince » (iPhone 16 Pro), UDID `00008140-001269280142801C`. Équipe de signature : **Personal Team** `F723XNC425` (certificat `vincent@debaty.be`), choisie pour ne pas utiliser le compte de l'entreprise (HertBelgium). Identifiant d'app `com.trainwork.prototype` enregistré automatiquement dans ce compte.
- Procédure : `scripts/deploy_ios_device.sh <UDID> <équipe>`. Un profil d'équipe personnelle expire après 7 jours : il faut réinstaller.
- Au premier lancement, approuver le profil sur l'iPhone (Réglages > Général > VPN et gestion de l'appareil), et activer le mode développeur (Réglages > Confidentialité et sécurité).

## D-014 — Pose de rails au toucher (retour UX de Vincent)
Demande : « je tape sur la case, le rail se place automatiquement selon la jonction du rail adjacent » + arrondi automatique des coins à 90°. Implémenté dans `src/rail/rail_planner.gd` (pur), appliqué par `BuildController`. Le glissement reste disponible.
- **Tête** : dernière case choisie en mode Rails (anneau jaune), point de départ du prochain tracé.
- **Règles, dans l'ordre :** (0) case déjà équipée : devient la tête, ou est reliée à la tête ; (1) case voisine d'un bout de voie ou d'une gare : raccord automatique (alignement droit privilégié), et comblement d'un trou entre deux bouts ; (2) coin à 90° sur un bout de voie : le dernier segment est remplacé par une diagonale à 45° ; (3) sinon, tracé calculé depuis la tête dans un rayon de 12 cases, virages de 45° max, qui contourne l'eau et les rails ; (4) sinon la case devient la tête.
- Un raccord en milieu de voie crée un aiguillage (fourche) seulement si aucun bout de voie, gare ou coin arrondi n'est possible.
- **Annuler** (modes Rails et Gomme) : défait la dernière action sur les segments (jusqu'à 30) ; un segment sous un train ne peut pas être retiré.
- `RailNetwork.replace_edge` remplace un segment de façon atomique ; `check_replace` le simule.
*À valider à l'usage.*

## D-015 — Production, stocks, chargement et revenus (M3)
Décisions de conception arbitrées avec ChatGPT (échange 002, `docs/chatgpt/002-batiments-gares-et-chargement.md`), valeurs d'essai dans `data/content.json` (jamais validées) :
- **Rattachement bâtiment-gare (D1-A) :** chaque bâtiment dépend de la gare **la plus proche dans un rayon de 2 cases** de son emprise (égalité : plus petit id) ; une gare peut en desservir plusieurs ; aucun stock n'est déplacé quand le rattachement change ; le lien est tracé à l'écran et le rayon s'affiche en mode Gare.
- **Chargement selon le besoin réel (D2-A) :** à l'arrêt, le train décharge ce que les consommateurs de la gare peuvent recevoir (place libre en entrée), le reste reste à bord ; il charge ce que les consommateurs des **autres gares de la ligne** demandent (pas seulement les suivantes : prévu pour les correspondances de M4+), dans la limite de la capacité des wagons.
- **Trois stocks séparés :** bâtiments (`Building.inputs/outputs`), entrepôts de gare (`GoodsStock` par gare, lots avec gare d'origine), cargaison du train (`Train.cargo`). Les lots portent leur gare d'origine : ils servent au prix (distance) et distingueront sortant / en transit.
- **Production :** un cycle démarre seulement si tous les intrants sont présents **et** s'il y a place pour chaque sortie ; intrants consommés au démarrage, sorties créées à la fin. Une ville est un bâtiment sans sortie qui consomme : sa livraison est limitée par sa capacité d'entrée (ce n'est pas un puits infini). Registre matière : produit - consommé = somme des stocks, vérifié à chaque pas par les tests.
- **Revenus :** crédités à l'entrée de la marchandise dans le stock du consommateur, une fois ; prix par unité = base + distance (segments du plus court trajet ferroviaire entre la gare d'origine du lot et la gare de livraison) x tarif par segment. Pièces en milli-pièces entiers ; solde jamais négatif (`Economy.spend` refuse).
- **Durée d'arrêt :** au moins l'arrêt minimal, plus si le volume manipulé l'exige (unités / débit de manutention). Le transfert est instantané à l'arrivée ; la durée est proportionnelle au volume.
- **Hypothèses de M3, acceptées « temporairement » par ChatGPT, qui ne doivent pas devenir des règles :** composition fixe du train (wagon charbon + wagon bois de 10 unités, en attendant le dépôt) ; pas de carburant ; ville sans croissance ; bâtiments placés d'avance par `data/scenario_level1.json` ; rails et gares coûtent 0 pièce (l'économie de construction viendra avec les niveaux).
- **Rails et gares interdits sur un bâtiment** (« Emplacement occupé par un bâtiment »).
- Fichiers JSON exportés sur mobile via `include_filter="data/*.json"` du préréglage d'export.
- **Défaut corrigé au passage :** `DisplayServer.get_display_safe_area()` est en coordonnées d'écran ; sur Mac mon décalage de zone sûre (D-012) sortait l'interface de la vue. Marges mesurées désormais par rapport à la fenêtre + test de non-régression.
*À valider : chaîne visible mine, gare, train, gare, ville avec baisse du stock de la mine, hausse du stock de la ville et pièces à la réception (critère de ChatGPT).*

## D-016 — Sécurité des voies et deux trains (M4)
Arbitré avec ChatGPT (échange 003, `docs/chatgpt/003-securite-voies-et-deux-trains.md`), option A. Valeurs d'essai dans `data/content.json` :
- **Réservation tout ou rien :** avant de quitter une gare, un train réserve **tout** son trajet jusqu'à la gare suivante, **quai de destination compris**. Sinon il attend en gare (état « attend que la voie soit libre »), sans rien retenir d'autre que sa case. Les cases se libèrent derrière lui quand sa queue les a quittées (longueur du train : 1000 milli-cases) ; à l'arrivée il ne tient plus que sa gare. Les passages à voie unique sont donc exclusifs par construction.
- **Capacité d'une case :** 1 sur voie et aiguillage ; **nombre de quais** dans une gare (`station_platforms`, 2 en essai). Une gare n'est un point de croisement que si elle a réellement 2 quais : avec 1 quai, deux trains face à face ne peuvent pas se croiser.
- **Interblocage non exclu :** détection d'attente circulaire (plus grand ensemble de trains qui s'attendent tous les uns les autres) ; le jeu ne déplace jamais un train dangereusement, il affiche un **diagnostic** (« Train 1 attend Gare 2, occupé par Train 2… ») et un conseil (ajouter un quai ou une voie de croisement, ou retirer un train). Une voie coupée n'est pas un interblocage (état « attend une voie »).
- **Nombre de trains :** `max_trains` dans `content.json` (2, limite des niveaux 3-4) l'emporte sur la configuration, en attendant les niveaux (M5). Un 2e train sur une ligne identique la rejoint ; il est refusé (« Gare pleine ») si le premier quai n'est pas libre.
- **Limites connues de A :** pas de convoi à la queue leu leu (le second train attend que le premier ait fini son trajet) ; débit plus faible sur voie très partagée ; une voie coupée en cours de trajet laisse un train arrêté en voie, case retenue. Le cantonnement par blocs (option B) sera réévalué à 3 trains ou plus.
- **Tests (13 nouveaux)** : les trois scénarios demandés (même sens sur voie partagée ; sens opposés avec croisement en gare ; face à face sans croisement possible : aucun départ, diagnostic), voie en Y avec tronc partagé, invariants à chaque pas (capacité des cases, pas de superposition hors gare), déterminisme à 2 trains, indépendance au FPS. Un contrôle par mutation (réservation désactivée) fait échouer 8 tests.
*À valider : voir deux trains circuler sur la même voie sans jamais se toucher, et l'interblocage expliqué quand il se produit.*

## D-017 — Progression des niveaux 1 à 3, dépôt et coûts (M5)
Arbitré avec ChatGPT (échange 004, `docs/chatgpt/004-progression-couts-sauvegarde.md`). Valeurs d'essai dans `data/content.json` :
- **Dépôt physique** (bâtiment du scénario, rôle `depot`) relié à une gare : il demande exactement les matériaux du prochain niveau (sa capacité d'entrée = la quantité requise). Bouton **« Améliorer → N2 »** (mode Naviguer) actif seulement si **toutes** les conditions sont réunies : pièces disponibles, matériaux présents au dépôt, objectifs permanents. L'amélioration débite les pièces et **consomme** les matériaux.
- **Conditions :** N1→N2 = 20 bois + 20 charbon au dépôt, 40 unités livrées à la ville dont 10 de chaque produit, 75 pièces ; N2→N3 = 25 bois + 20 pierre + 15 charbon au dépôt, 30 pierre livrée à la ville, une ligne opérationnelle (au moins un trajet effectué), 150 pièces. Livraisons à la ville comptées depuis le début du niveau.
- **Déblocages :** N2 = carrière, pierre, wagon pierre, la ville demande de la pierre ; N3 = mine de fer, aciérie (2 minerai + 1 charbon → 1 acier, essai), wagons minerai et acier, la ville demande de l'acier, **2 trains**. Les 2e mines/scieries ne sont **pas** des déblocages (avis ChatGPT). Bâtiments des niveaux à venir présents sur la carte mais inertes, en transparence, emplacement réservé. **Écarts au GDD tracés, hors périmètre du prototype mais pas supprimés :** pont simple et locomotive/gare/bâtiments améliorés (N2), 2e carrière et wagon de fer distinct (N3).
- **Priorité de livraison (GDD) :** dépôt (matériaux de construction), puis industries, puis villes. **Les livraisons au dépôt ne rapportent rien** (choix de ma part, pour éviter de gagner des pièces avec ses propres matériaux) ; chaque unité a une seule destination.
- **Wagons :** un wagon de 10 unités par produit débloqué, ajouté automatiquement à tous les trains (pas d'écran de composition ; traction ignorée pour l'instant).
- **Coûts :** 100 pièces au départ ; rail 1 pièce par segment ; gare 10 ; retrait remboursé à 50 % ; annulation d'une pose remboursée en entier ; pose trop chère **refusée en entier** avec le montant manquant ; solde jamais négatif. Réseau minimal du niveau 1 (2 gares + 10 rails) : 30 pièces, test de marge.
- **Pertes :** retirer les trains ou supprimer une gare détruit leurs marchandises, comptées dans un registre `lost` ; le bilan matière devient produit − consommé − perdu = présent.
- **Rattachement :** à égalité de distance de Chebyshev, la gare la plus proche en ligne droite l'emporte (l'ordre de pose ne décide plus).
- **Rythme mesuré (partie automatique, couloir y=38) :** niveau 2 atteint en **1 min 20 s** de jeu, niveau 3 en **3 min 30 s**. Probablement trop rapide pour le GDD (40 à 60 h pour 30 niveaux) : valeurs à recalibrer après les essais sur iPhone.
- **Piège de placement (résolu par D-019) :** dans l'ancienne disposition, l'aciérie se rattachait à la gare de la ville ; elle est désormais éloignée de la ville.
*À valider en jeu sur iPhone.*

## D-018 — Sauvegarde, reprise et rattrapage (M5)
- **Sauvegarde locale versionnée** (`save_version` 1) en JSON dans `user://savegame.json` : réseau (rails avec ids, gares), bâtiments et stocks, entrepôts (lots ordonnés), registres, pièces, niveau et objectifs, lignes, trains (position logique exacte, réservations, cargaison), répartiteur, horloge (pas et accumulateur), cadrage de la caméra. La carte n'est **pas** dupliquée : graine et version du générateur, vérifiées au chargement ; sauvegarde incompatible ignorée avec message.
- **Écriture sûre :** fichier temporaire relu et vérifié, copie de secours de l'ancienne sauvegarde, puis renommage. Fichier principal corrompu : on reprend la copie de secours.
- **Quand :** toutes les 30 s (`autosave_interval_sec`), à la mise en arrière-plan ou à la fermeture, et à chaque montée de niveau. « Recommencer » (double appui) efface la partie.
- **Reprise exacte :** après chargement, la simulation continue à l'identique (test : 1000 pas identiques). Correctif nécessaire : `JSON.stringify` de Godot trie les clés par défaut ; l'ordre est désormais conservé.
- **Rattrapage hors ligne :** composant isolé `src/sim/offline_catchup.gd` (demande de ChatGPT), qui rejoue pas à pas avec un plafond de 10 minutes de jeu (`offline_cap_sec`). **Le rattrapage de 24 h reste une exigence du jeu final.** Mesure : environ 15 ms pour 1000 pas sur Mac (petit réseau), donc 24 h demanderaient de l'ordre de quelques secondes sur Mac ; à mesurer sur iPhone avant de choisir entre rejouer et modèle simplifié.

## D-019 — Bâtiments dispersés (demande de Vincent)
- **Demande :** les bâtiments étaient trop proches les uns des autres ; ils doivent être plus dispersés.
- **Nouvelle disposition** (`data/scenario_level1.json`), sur toute la rive ouest (la rivière vers x = 30-36 n'est pas franchissable tant que les ponts ne sont pas construits) : mine de charbon au nord-ouest (4,4), scierie en forêt à l'ouest (5,29), ville (21,40) avec le dépôt à côté (16,44) au sud, carrière dans les collines au sud-ouest (8,56), mine de fer dans les collines au nord (21,8), aciérie à l'est (24,25). Des voies de 10 à 25 cases séparent les sites.
- **Budget de départ : 150 pièces** (au lieu de 100, valeur d'essai) : le réseau minimal du niveau 1 (mine, scierie, ville + dépôt) coûte 65 à 67 pièces ; avec 100, un joueur réel qui fait des détours manquait de marge. Test : le réseau minimal coûte au plus la moitié du budget.
- **Rythme mesuré** (partie automatique) : niveau 2 en 4 min de jeu, niveau 3 en 10 min (contre 1 min 20 s et 3 min 30 s avant). Les trajets plus longs ralentissent la progression et paient davantage (composante distance du prix).
- `src/dev/sample_network.gd` : réseau d'exemple valide (gares, axes, raccords trouvés par recherche automatique), partagé par la démo et les tests. La recherche de tracé accepte une portée plus grande (le toucher en jeu reste limité à 12 cases).
- Une sauvegarde existante garde l'ancienne disposition (les bâtiments font partie de la sauvegarde) : « Recommencer » pour la nouvelle.

## D-020 — Carte 80 x 80, sites dispersés autour du dépôt (demande de Vincent, plan validé)
- **Objectif :** sensation de territoire et d'expansion (esprit Age of Empires II) : dépôt au centre, ville éloignée, ressources dans différentes directions, exploration par la caméra.
- **Carte 80 x 80, générateur v2** piloté par le scénario (`data/scenario_level1.json`) : plaine clairsemée ; environnement autour de chaque site (forêt pour la scierie, **roche** — nouveau terrain constructible — pour la carrière, collines pour les mines) ; clairière autour de chaque bâtiment (2 cases, 6 autour du dépôt) ; rivière en polyligne épaissie (aucun franchissement en diagonale) ; site de pont. Structure `layout` (sites, rivière, pont) produite aujourd'hui depuis le fichier, demain par une génération procédurale ; chaque site indique sa direction et sa plage de distance.
- **Implantation** (coin haut, à l'écran x vers le sud-est, y vers le sud-ouest) : dépôt (39,39) au centre ; mine de charbon (22,39) nord-ouest ≈ 17 ; scierie (39,56) sud-ouest ≈ 17 ; ville (66,39) sud-est ≈ 27 ; carrière (39,10) nord-est ≈ 29 ; mine de fer (62,62) sud ≈ 33 ; aciérie (61,18) est ≈ 30. Vérifié par test (direction à l'écran et distance).
- **Rivière et pont (option A) :** la rivière traverse le nord et n'isole que la carrière. Un **site de pont** (cases d'eau autour de (40,16)) accepte des rails à partir du niveau 2, à 5 pièces le segment ; avant, message « le pont sera disponible au niveau 2 ». **Écart au GDD tracé** : pas de chantier progressif ni de matériaux pour le pont (passage préconstruit, comme le prévoit la SPEC).
- **Sites futurs invisibles :** carrière, mine de fer et aciérie ne sont ni dessinées ni nommées avant leur niveau ; seul leur environnement trahit l'emplacement ; construire dessus : « Site réservé pour une extension future ».
- **Le dépôt et la ville ont chacun leur gare** : la ville est une vraie destination (environ 27 cases).
- **Économie :** 200 pièces au départ (réseau minimal du niveau 1 = 4 gares + ~50 rails ≈ 90 pièces, test : au plus la moitié du budget). Pose au toucher portée à 20 cases. Coûts unitaires inchangés.
- **Caméra :** une partie neuve s'ouvre centrée sur le dépôt ; au zoom minimal, on voit environ 40 % de la largeur de la carte ; la ville et les sites lointains se découvrent en se déplaçant.
- **Rythme mesuré** (partie automatique, `src/dev/sample_network.gd`) : niveau 2 à 5,8 min de jeu, niveau 3 à 29,7 min ; 1 282 pièces en réserve au niveau 3 (économie large en fin de prototype : à recalibrer). Calcul : environ 0,09 ms par pas sur Mac ; un rattrapage de 24 h rejoué pas à pas prendrait environ 40 s sur Mac.
- **Sauvegardes :** l'ancienne carte (64 x 64, v1) est incompatible : une sauvegarde existante est ignorée avec un message et une partie neuve commence.
- Hors périmètre, non développés : générateur procédural complet, brouillard de guerre définitif.
*Disposition validée par Vincent le 2026-11-02 après essai sur iPhone.*

## D-021 — Modifier une ligne et destination précise des marchandises (retour de test iPhone)
**Constat de Vincent :** après avoir relié la carrière et « refait la ligne », le train ne passait pas par la carrière. **Analyse de sa sauvegarde :** la nouvelle ligne n'avait pas été créée (niveau 2 : 1 train maximum, « Lancer » échouait sur « Nombre maximal de trains atteint ») et aucune ligne ne pouvait être modifiée. **En rejouant sa partie** avec la ligne corrigée, un second défaut est apparu : en revenant de la carrière, le train passait par la ville avant le dépôt ; la ville absorbait toute la pierre et le dépôt n'en recevait jamais, ce qui bloquait le passage au niveau 3.
- **Modifier une ligne (GDD : « un changement de liste est appliqué après le prochain arrêt en gare ») :** `TrainSimulator.update_line`. Chaque train garde son parcours (`Train.route`) jusqu'à son prochain arrêt, puis adopte la nouvelle liste depuis la gare où il se trouve ; si cette gare n'y figure plus, il rejoint la première gare. Les gares de l'ancien parcours restent protégées tant qu'un train les vise.
- **« Lancer » en mode Ligne :** même liste qu'une ligne existante = un train de plus ; sinon, si le nombre maximal de trains est atteint et qu'il n'y a qu'une ligne, **la ligne est modifiée** (« Ligne modifiée : le train suivra le nouveau parcours après son prochain arrêt ») ; avec plusieurs lignes, message explicite pour en retirer une. Le HUD affiche le parcours de chaque ligne.
- **Destination précise (exigence ChatGPT 002, priorité du GDD) :** à chaque arrêt, la cargaison à bord est réservée pour des gares du parcours, par priorité (dépôt, puis industries, puis villes) puis dans l'ordre du parcours, dans la limite de leur demande non réservée par les autres trains. Un train ne décharge à une gare que ce qui lui est réservé ; les réservations sont recalculées à chaque arrêt et sauvegardées.
- **Vérifié sur la sauvegarde de Vincent :** avec la ligne modifiée, le dépôt reçoit ses 20 pierres, la ville 30, et le niveau 3 devient accessible. Test de régression (ville placée avant le dépôt sur le chemin) ; une mutation qui supprime la réservation le fait échouer.
- Les anciennes sauvegardes restent compatibles (parcours repris de la ligne, réservations recalculées au prochain arrêt).

## Questions ouvertes
- Prise en charge des rails sur ponts/eau (niveau 2) : écart à tracer quand le pont sera traité.
