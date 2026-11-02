# Échange n°003 : sécurité des voies et deux trains (jalon M4)

## Message de Claude Code (résumé)

Contexte : M3 validé. Pour M4, il faut un répartiteur garantissant qu'une section n'est jamais occupée par deux trains incompatibles. Le GDD dit « sécurité automatique sur sections uniques, aiguillages et croisements » et « passage alterné sûr » pour ponts et tunnels, mais pas où les trains attendent ni comment ils se croisent sur voie simple.

Options : **A** réservation tout ou rien du trajet jusqu'à la gare suivante (le train n'attend qu'en gare, les gares servent de points de croisement à 2 trains) ; **B** cantonnement par blocs (attente en pleine voie, détection d'interblocage à écrire) ; **C** gares à 1 train, croisement par boucles construites par le joueur. Recommandation : A pour M4, 2 trains maximum, interface du répartiteur assez générale pour passer à B plus tard.

## Réponse de ChatGPT (2026-11-02, relevée dans la session)

- **(a) A, validé** pour le prototype à deux trains : le train réserve son trajet jusqu'à la prochaine gare avant de partir ; s'il n'est pas disponible il attend en gare ; cases libérées progressivement derrière lui. **La réservation doit inclure la disponibilité d'un quai à destination**, sinon deux trains peuvent se bloquer en attendant une place.
- **(b) Gare = point de croisement : acceptable provisoirement, à condition que la gare ait réellement deux voies ou quais indépendants.** Le GDD prévoit un quai au départ et des améliorations de capacité. Pour M4, deux quais par paramètre de test ; ne pas considérer qu'une gare à voie unique permet magiquement un croisement.
- **(c) Ponts et tunnels :** A suffit pour M4 ; pas de cantonnement par blocs maintenant. Les ponts et tunnels à voie unique doivent être protégés par des réservations exclusives. Le cantonnement par blocs n'est pas nécessairement obligatoire au niveau 5 ; à réévaluer avec 3 trains ou plus.
- **(d) Deuxième train par réglage dans `content.json` avant M5 : validé.**
- **Point critique : ne pas considérer que deux trains rendent tout interblocage impossible par construction.** Trois tests indispensables : (1) deux trains dans le même sens sur une voie partagée ; (2) deux trains en sens opposés avec une gare permettant réellement le croisement ; (3) deux trains face à face sur une voie unique sans possibilité de croisement : aucune collision, aucun départ dangereux, diagnostic compréhensible.

## Suite donnée (Claude Code)

Appliqué en M4 : réservation tout ou rien d'un trajet complet, quai de destination compris ; capacité des gares = nombre de quais (`station_platforms`, 2 en essai, 1 pour le scénario sans croisement) ; détection d'attente circulaire avec diagnostic affiché ; `max_trains` dans `content.json` ; les trois scénarios exigés sont des tests. Décision finale : Vincent.
