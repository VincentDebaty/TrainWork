# Architecture et plan d'implémentation

Moteur : Godot 4.7.2 (GDScript typé, rendu GL Compatibility). Voir `CLAUDE.md` et `SPEC_Prototype_Godot_v0_1.docx`.

## Principes

1. **Simulation indépendante du rendu.** `src/core` et `src/sim` n'utilisent aucun nœud ni la caméra. Seule `src/presentation` connaît les nœuds, et `main.gd` assemble le tout.
2. **Pas fixe** (0,2 s, `data/world_config.tres`), accumulé en microsecondes entières. Le rendu ne fait que lire l'état.
3. **Grille logique 2D** ; la projection isométrique n'existe que dans `iso_projection.gd`, utilisée par le rendu et la saisie.
4. **Données éditables** : constantes d'essai dans `data/*.tres`, jamais en dur.
5. **Testable en headless** : logique pure en `RefCounted`, sans `class_name` (références par `preload`, donc pas de dépendance au cache de classes de l'éditeur).

## Arborescence

```
project.godot
scenes/main.tscn            scène d'assemblage (Main > WorldView, Camera, Hud)
data/world_config.tres      constantes d'essai (carte, projection, sim, caméra, debug)
src/
  data/world_config.gd      schéma de la configuration (Resource)
  core/                     logique pure, sans nœuds
    terrain.gd  world_map.gd  map_generator.gd  iso_projection.gd  camera_math.gd
  rail/                     réseau ferré (logique pure)
    direction.gd  rail_graph.gd  rail_network.gd  station.gd  rail_drag_path.gd
  data/content.gd           lecture de data/content.json (produits, bâtiments, wagons)
  sim/                      simulation à pas fixe
    sim_clock.gd  sim_params.gd  game_simulation.gd  train_simulator.gd  line.gd  train.gd
    industry.gd  building.gd  goods_stock.gd  logistics.gd  economy.gd  dispatcher.gd
    progression.gd  construction.gd  game_world.gd  offline_catchup.gd
  persistence/              sauvegarde : save_game.gd (format versionné), save_store.gd (fichier, écriture sûre)
  presentation/             nœuds, rendu, saisie
    main.gd  world_view.gd  camera_rig.gd  rail_view.gd  train_view.gd  build_controller.gd  build_toolbar.gd
  dev/demo_m1.gd            démo de développement (réseau d'exemple)
tests/                      tests headless (run_tests.gd + test_*.gd)
scripts/run_tests.sh
docs/                       GDD, SPEC, DECISIONS.md, ce fichier
```

Tous les modules du plan M0-M5 existent ; `tests/game_fixture.gd` fournit des parties de test.

## Plan par jalons

| Jalon | Contenu | Vérification |
|---|---|---|
| **M0** (fait, validé) | Carte de test, projection iso, caméra tactile, horloge de sim | 22 tests ; pan/zoom sur appareil |
| **M1** (fait, validé) | `RailGraph` (8 directions), pose/suppression par glissement, gares, aiguillages auto, connexité | voie continue, aiguillage, rupture/reconnexion |
| **M2** (fait) | Train sur segments, arrêts en gare, aller-retour A-B-C-B-A | pas de saut/oscillation au terminus |
| **M3** (fait, validé) | Production, stocks, chargement/livraison, pièces | bilan matière, revenu une fois par livraison |
| **M4** (fait, validé) | `Dispatcher` : réservation de sections, 2 trains niveau 3, interblocages | aucune collision, attente sûre |
| **M5** (fait, validé le 2026-11-02 après une partie complète sur iPhone) | Save/Load versionné, niveaux 1–3, test mobile | état identique après rechargement |

Chaque jalon s'arrête pour validation humaine avant le suivant.

## M0 : comportement et vérification

- Carte 64×64 déterministe (rivière, forêts, collines), cases en losanges de 128×64.
- Caméra : 1 doigt = pan, 2 doigts = pincement (zoom centré sur les doigts), tap = sélection de case (surlignage jaune + HUD). Bureau : glisser = pan, molette = zoom, pavé tactile Mac = pan / pincement. Zoom borné (0,5 à 2,5) et caméra bornée à la carte.
- HUD de debug : pas de simulation, zoom, FPS, case sélectionnée.

### Vérifier sur le poste

```
./scripts/run_tests.sh          # tests headless
godot --path .                  # lance le jeu (ou ouvrir project.godot et F5)
```

### Vérifier sur simulateur iOS

```
./scripts/build_ios_sim.sh
```
puis installer `build/derived/Build/Products/Debug-iphonesimulator/TrainWork.app` (bundle `com.trainwork.prototype`). Voir D-012 pour les constats et les limites.

### Vérifier sur téléphone

- **Android** : Éditeur > Gérer les modèles d'export (installer les modèles 4.7.2), régler le SDK Android dans Paramètres de l'éditeur, Projet > Exporter > ajouter « Android », activer le débogage USB sur le téléphone, puis bouton de déploiement en un clic en haut à droite.
- **iOS** : Projet > Exporter > « iOS », ouvrir le projet Xcode généré, signer avec votre équipe, lancer sur l'appareil.
- Le test M0 attendu : pan et zoom fluides ; le compteur « Pas sim. » avance au même rythme (5 pas/s) pendant et sans manipulation.

## M1 : comportement et vérification

- `RailGraph` : segments non orientés à id stable, aiguillage déduit du degré, connexité, `find_path` respectant le rayon de courbure.
- `RailNetwork` : point d'entrée unique des modifications ; règles de pose (D-008), gares sur axe (D-009), aperçu sans effet de bord (`simulate_edges`), signal `changed`.
- Outils (D-010) : Naviguer / Rails / Gare (bouton « Axe » pour tourner) / Gomme. Aperçu vert (valide), bleu (déjà posé), rouge (refusé), orange (gomme).
- Test : `./scripts/run_tests.sh` (54 tests : voie continue, aiguillage, rupture et reconnexion, refus de pose, gestes de bout en bout).
- Démo : `godot --path . res://scenes/dev_demo_m1.tscn` (réseau d'exemple) ; `godot --path .` pour construire soi-même.

## M2 : comportement et vérification

- `TrainSimulator` : lignes (gares ordonnées), un train, états `à l'arrêt / en marche / attend une voie`, aller-retour A-B-C-B-A, rebroussement en gare. Arrivées signalées (`train_arrived`) pour les futurs chargements (M3).
- Interface : mode **Ligne** ; taper les gares dans l'ordre (retaper la dernière l'annule), « Lancer » crée la ligne et son train, « Vider » efface la sélection, « Retirer » supprime lignes et trains. Train bleu en marche, gris à l'arrêt, rouge en attente.
- Tests : `./scripts/run_tests.sh` (aller-retour 2 et 3 gares, durée de trajet exacte, stabilité aux terminus, pas de saut ni de recul, courbes diagonales, aiguillage, rupture/reprise, protections, déterminisme et indépendance au FPS).
- Démo : `godot --path . res://scenes/dev_demo_m1.tscn` (réseau d'exemple avec un train en marche).

## M3 : comportement et vérification

- Données dans `data/content.json` (produits, bâtiments, wagons, constantes de logistique) et `data/scenario_level1.json` (mine, scierie, ville placées d'avance). Valeurs d'essai.
- Production avec intrants, capacités et arrêt/reprise ; rattachement automatique bâtiment-gare (rayon 2) ; entrepôts de gare ; train chargé selon la demande ; revenu à la réception ; pièces affichées dans le HUD.
- Démonstration : `godot --path . res://scenes/dev_demo_m1.tscn` (gare 1 dessert mine et scierie, gare 2 dessert la ville). En jeu normal : poser deux gares à moins de 2 cases des bâtiments, relier par rails, mode Ligne, toucher les deux gares puis « Lancer ». Toucher un bâtiment ou une gare en mode Naviguer affiche sa fiche (stocks, gare, état).
- Tests : bilan matière à chaque pas, capacités, production sans intrants, revenu une fois par livraison et seulement à la réception, solde jamais négatif, rattachement, durée d'arrêt, déterminisme et indépendance au FPS.

## M4 : comportement et vérification

- `Dispatcher` : réservation atomique de cases (capacité 1 en voie, nombre de quais en gare), libération derrière le train ; `TrainSimulator` réserve le trajet complet avant de partir et détecte les attentes circulaires.
- Démo : `godot --path . res://scenes/dev_demo_m1.tscn` (deux trains en sens opposés entre les deux gares). En jeu : créer une ligne, « Lancer » ; relancer la même sélection de gares ajoute un second train (2 maximum).
- Tests : `./scripts/run_tests.sh` ; voir D-016.

## M5 : comportement et vérification

- Partie neuve : niveau 1, 100 pièces. Rails (1 pièce) et gares (10) se paient. Le HUD affiche le niveau et chaque condition du prochain (`[ok]` / `[..]`) ; « Améliorer → N2 » s'active quand tout est réuni. Nouveaux bâtiments en transparence jusqu'à leur niveau.
- Sauvegarde automatique (30 s, arrière-plan, montée de niveau) ; reprise au lancement avec rattrapage plafonné et message ; « Recommencer » efface la partie.
- Tests : partie complète automatique du niveau 1 au niveau 3 puis acier livré, sans toucher aux données ; round-trip de sauvegarde (même état, même suite) ; écriture sûre et repli ; rattrapage plafonné ; coûts et soldes ; reprise par la scène principale.

## Limites connues de M5

- Rythme de progression trop rapide (valeurs d'essai) ; pas de pont ni d'amélioration de locomotive/gare (écarts tracés) ; rattrapage plafonné à 10 min ; piège de placement de l'aciérie (D-017).

## Limites connues de M4

- Pas de convoi à la queue leu leu ; 2 trains maximum (niveau 3-4) ; pas de résolution automatique d'un interblocage (diagnostic seulement) ; niveaux et déblocage du 2e train non gérés (M5).

## Limites connues de M3

- Pas de construction de bâtiments, de dépôt, d'achat de train ni de carburant ; composition du train fixe ; ville sans croissance ; correspondances entre lignes non implémentées (structure prévue).
- Coûts de construction à 0 ; prix et débits non calibrés.

## Limites connues de M2

- Pas de cargaison, ni de répartiteur, ni de second train (M3, M4). Train représenté par un trait épais (placeholder), sans wagons ni animation de vapeur.
- Une ligne ne peut pas être modifiée ; pas d'écran de dépôt ni d'achat.

## Limites connues de M1

- Pas de coût ni de pièces, pas de croisement automatique de voies, pas de pont, pas d'annulation globale (Gomme uniquement).
- Les rails sont dessinés sans courbes adoucies ni traverses (placeholder).
- Gestes de construction testés par événements simulés, pas encore sur appareil.

## Limites connues de M0

- Rendu : un `draw_colored_polygon` par case visible (~900 à zoom 0,5). Suffisant pour M0 ; à remplacer (chunks pré-rendus ou `TileMapLayer`) si les mesures sur téléphone le demandent.
- Pas d'inertie du panoramique, pas de sauvegarde du dernier cadrage (prévu en M5), pas de carte générale distincte, pas de brouillard de régions.
- Seul le rendu sur macOS est vérifié ; le comportement tactile réel est couvert par des tests d'événements simulés, pas encore par un appareil.
