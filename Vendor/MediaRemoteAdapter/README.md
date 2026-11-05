# MediaRemoteAdapter

Copie de [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (commit `0e82bf1c44ec`), sous licence BSD 3-Clause (voir `LICENSE`).

macOS réserve l'accès au « À l'écoute » (MediaRemote) à ses propres apps. Ce framework est chargé par `/usr/bin/perl`, un programme d'Apple qui y a droit, et transmet les informations du morceau en cours (YouTube dans le navigateur, Deezer, Podcasts…) en JSON.

Seuls `src/` (sans le client de test, dont seul l'en-tête est gardé), `include/` et `bin/mediaremote-adapter.pl` sont repris. Encoche le compile comme framework intégré à l'app (voir `project.yml`).
