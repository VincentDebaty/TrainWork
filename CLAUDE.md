# Compagnie ferroviaire — instructions Claude Code

## Source de vérité
- Référence produit : `GDD_Compagnie_Ferroviaire_v1.docx` (GDD v1.0 validé par le porteur du projet).
- Référence d'implémentation : `SPEC_Prototype_Godot_v0_1.docx` (spécification technique proposée, à valider sur prototype).
- En cas d'ambiguïté, ne pas inventer de règle définitive : noter la question dans `docs/DECISIONS.md`, proposer un défaut simple et réversible.
- Ne **pas** implémenter les 30 niveaux d'un coup. Construire d'abord un vertical slice des niveaux 1 à 3.

## Vision non négociable
- Jeu mobile en français, gestion ferroviaire XIXe siècle, locomotives à vapeur, vue isométrique fixe, caméra tactile pan + zoom.
- Le joueur construit les rails, les gares et les lignes ; les trains transportent automatiquement les marchandises.
- Les transferts de marchandises entre bâtiments se font **exclusivement par rail** ; routes et charrettes ne sont que décoratives.
- Lignes définies par une **liste ordonnée de gares** et parcourues en **aller-retour** (A-B-C-B-A).
- Stocks réels finis, production automatique conditionnée par les intrants et la capacité disponible.
- Economie accessible : pas de faillite punitive ; solde de pièces jamais négatif.
- Tous les trains doivent respecter la sécurité des sections de voie : pas de collision, pas de chevauchement.
- Simulation séparée du rendu : fonctionnement hors écran, sauvegarde et reprise possibles.
- Pas de bouton pause ni d'accélération du temps pour le produit final.
- Ne pas créer de nouveau système de contrats, cloud, voyageurs, tunnels, météo ou niveau >3 durant le premier vertical slice.

## Cadre technique proposé (adapter à la version Godot installée)
- Godot **4.x stable**, GDScript typé, projet 2D isométrique (TileMapLayer / Node2D selon besoins). Ne pas choisir de plugin payant ou dépendance externe sans accord.
- Construire une simulation déterministe à pas fixe (hypothèse de départ : 0,2 seconde) distincte du framerate ; l'affichage interpole les positions.
- Les coordonnées de simulation des rails restent sur une grille logique 2D 8 directions ; projection isométrique uniquement dans la couche de rendu.
- Utiliser des identifiants stables pour trains, gares, rails, bâtiments, produits et lignes. Stocker les données gameplay en Resources/JSON plutôt que dispersées dans les scènes.
- Séparer données, système de simulation, interface et rendu. Ne pas faire dépendre la logique métier des nœuds visuels.
- Garder la simulation testable de façon headless avec des scènes/tests unitaires ou scripts dédiés.

## Modules à créer dans l'ordre
1. World/grid et caméra isométrique tactile ; carte fixe reproductible pour les tests.
2. RailGraph : cellules, segments, aiguillages ; pose/suppression ; vérification de connexité.
3. TrainSimulator + Dispatcher : circulation sur segments, réservation sécurisée, gare, aller-retour.
4. Cargo/Production : charbon, bois, pierre, minerai de fer, acier ; stocks, recettes et capacités.
5. Lines/Cargo routing : gares ordonnées, chargement/déchargement et destinations automatiques.
6. Economy/Progression : pièces, revenus, coûts simples, dépôt niveaux 1–3, objectifs tests.
7. Save/Load local : sérialisation versionnée + reprise et tests de restauration.
8. Interfaces minimales et polish fonctionnel (animations placeholders acceptées).

## Règles d'implémentation
- Pour chaque étape : annoncer les fichiers modifiés, le comportement visé, les tests, les limites connues et le mode de vérification dans Godot.
- Préférer une petite tranche verticale exécutable à une grosse structure abstraite non jouable.
- Écrire des tests sur les invariants : bilan matière, capacité des stocks, sécurité de la voie, transitions des lignes, pas de solde négatif, round-trip sauvegarde.
- Ajouter des logs structurés désactivables ; éviter le spam console par frame.
- Ne pas introduire de valeurs d'équilibrage comme « validées » : centraliser les constantes d'essai dans des ressources facilement éditables.
- Les graphismes provisoires sont autorisés, mais ils doivent signaler clairement les rails, les gares, les marchandises et les capacités.
- Ne pas modifier des éléments déjà fonctionnels hors du périmètre demandé sans expliquer pourquoi.
- Après un bloc de travail, **s'arrêter pour validation humaine** avant de commencer le suivant.

## Définition de terminé du prototype
- Le joueur peut poser des voies, créer une gare, acheter un train et configurer une ligne.
- Un transport de charbon/bois depuis un producteur vers une ville fonctionne en autonomie et rémunère la compagnie.
- La production respecte les stocks et peut s'interrompre/reprendre.
- Deux trains peuvent circuler au niveau 3 sans collision sur une voie partagée simple.
- Un save/load local restaure rails, trains, positions logiques, stocks, pièces et niveau.
- On peut démontrer l'ensemble avec des assets temporaires sur un téléphone cible.

## Première demande conseillée à Claude Code
« Lis le GDD et la spécification du prototype, inspecte la version de Godot et le contenu du dépôt. Propose une architecture minimale, un arborescence de projet et un plan d'implémentation par étapes validables. Ne code que la première étape après avoir présenté le plan ; ne produis pas d'assets définitifs. »
