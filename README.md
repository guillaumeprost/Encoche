<p align="center">
  <img src="docs/icon.png" width="128" alt="Icône d'Encoche">
</p>

<h1 align="center">Encoche</h1>

<p align="center">
  L'encoche du MacBook devient une petite Dynamic Island :<br>
  musique, agenda, notifications, Claude et activités en direct, à portée de souris.
</p>

---

Encoche vit dans l'encoche de l'écran. Noire en haut pour se fondre avec celle du Mac, elle s'ouvre au survol en verre fumé. Sur un écran sans encoche (écran externe), elle en simule une.

## Fonctionnalités

### Dans l'encoche ouverte
- **Accueil** : le morceau en cours avec ses commandes, l'agenda du jour, et un champ pour poser une question à Claude.
- **Calendrier** : le mois à gauche, l'agenda du jour choisi à droite, avec les boutons pour rejoindre les visios.
- **Rappels** : les rappels du jour et ceux en retard, à cocher directement dans l'encoche.
- **Musique** : le lecteur (Musique, Spotify, et aussi YouTube dans le navigateur, Deezer, Podcasts…), et au choix les **paroles synchronisées** (la ligne chantée est mise en avant, un clic y saute) ou la **file d'attente** de Musique.
- **Raccourcis** : une tuile par raccourci du dossier « Encoche » de l'app Raccourcis (allumer une lampe, lancer une scène…).
- **Étagère** : les dernières captures d'écran, à glisser où tu veux.
- **Presse-papier** : l'historique de ce que tu as copié (textes, images, fichiers), avec des éléments à épingler. Les mots de passe des gestionnaires sont ignorés.
- **Notifications** : l'historique des notifications, conservé d'un redémarrage à l'autre.
- **Claude** : ta consommation de tokens du jour et de la semaine, tes 5 dernières sessions Claude Code, avec leur progression, leurs agents et leur conversation, un champ pour **répondre à une session** ou poser une question rapide.

Quand une musique est chargée, une mini-pochette avec lecture/pause et suivant s'affiche en haut à droite, à côté du bouton **minuteur** (Pomodoro, pause, 1 à 60 minutes). **Glisse un fichier sur l'encoche** pour le poser sur l'Étagère.

### Autour de l'encoche fermée
- **Activités en direct** : musique, Claude Code qui travaille (le petit personnage de Claude Code trottine), minuteur et Pomodoro, réunion dans moins de 10 minutes, mode Concentration, téléchargements, caméra et micro. L'encoche s'agrandit un peu, et une deuxième activité s'affiche dans une **bulle** à côté, comme sur iPhone.
- **Notifications façon iPhone** : toutes les notifications du Mac s'affichent dans l'encoche à la place des bannières de macOS, sur l'écran principal. Au survol, elles se déplient et proposent de les fermer ; un clic ouvre l'app et ferme la notification.
- **Claude Code** : quand Claude demande une autorisation ou pose une question, tu **réponds depuis l'encoche**. Ses réponses proposées en fin de tâche deviennent des boutons. Pas de notification quand tu es déjà dans l'app de la session (app Claude, terminal).
- **Réunions** : un rappel une minute avant, avec un bouton **Rejoindre** pour Meet, Zoom, Teams, Webex, FaceTime ou Whereby. Pendant l'appel, l'encoche ouverte propose de **couper le micro**, de **couper la caméra** (Meet, Zoom, Teams) et de **quitter l'appel**.
- **Volume, luminosité, batterie** : affichés sous l'encoche, sans masquer l'activité en cours.
- **Appareils Bluetooth** : AirPods, casque ou clavier qui se connectent, avec leur batterie.
- **Écran de verrouillage** : un cadenas dans l'encoche qui s'ouvre au déverrouillage, les activités sous l'horloge, le lecteur de musique au-dessus de la photo de profil, et un son au choix.

### Et aussi
- Une encoche sur **chaque écran**.
- Masquée quand une app est **en plein écran**, elle redescend avec la barre de menus quand la souris touche le haut de l'écran.
- **Réglages** (clic droit sur l'encoche → Réglages…) : style de l'encoche (noir, verre noir, Liquid Glass), activités, écran de verrouillage, et l'état de chaque autorisation.
- Très légère : environ 0,1 % de processeur au repos.

## Installation

Il faut **macOS 26** ou plus récent, sur un Mac Apple Silicon ou Intel.

### Depuis une version publiée

1. Télécharge **`Encoche-x.y.z.zip`** depuis la [dernière version](https://github.com/guillaumeprost/Encoche/releases/latest), ouvre-le et glisse **Encoche** dans le dossier **Applications**.
2. Ouvre Encoche. macOS refuse la première fois, car l'app n'est pas notarisée par Apple : clique sur **OK**.
3. Va dans **Réglages Système → Confidentialité et sécurité**, descends jusqu'à « Encoche a été bloquée » et clique sur **Ouvrir quand même**, puis confirme. C'est à faire une seule fois.
4. Encoche apparaît dans l'encoche. Elle te propose les autorisations au fur et à mesure (voir plus bas) et s'ajoute aux éléments d'ouverture du Mac (désactivable dans ses réglages).

Pour mettre à jour, remplace l'app dans Applications par la nouvelle version : les autorisations sont conservées.

### Depuis le code source

Il faut **Xcode 26** ou plus récent (lancé une fois, pour accepter sa licence) et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/guillaumeprost/Encoche.git
cd Encoche
./scripts/create-signing-cert.sh   # une seule fois par Mac
./scripts/install.sh
```

- `create-signing-cert.sh` crée dans ton Trousseau le certificat « Notch Local Signing ». L'app garde ainsi la même identité d'un build à l'autre, et macOS conserve les autorisations accordées.
- `install.sh` vérifie ces prérequis, compile en Release pour ton Mac, ferme l'Encoche en cours, installe la nouvelle dans `/Applications` et la lance.

Pour mettre à jour : `git pull`, puis `./scripts/install.sh`.

### Claude Code (facultatif)

Pour les fonctions Claude, il faut [Claude Code](https://claude.com/claude-code), connecté à ton abonnement : Encoche passe par la commande `claude`, sans clé d'API. Tout le reste fonctionne sans.

### Autorisations

Encoche te guide pour chacune. Leur état est visible dans ses réglages.

| Autorisation | Pour quoi faire |
|---|---|
| **Accès complet au disque** | Lire les notifications des autres apps |
| **Accessibilité** | Touches volume et luminosité, lire et masquer les bannières de macOS, lire la file d'attente de Musique, couper la caméra ou quitter un appel Meet, coller une réponse dans une session Claude |
| **Calendrier** | L'agenda et les rappels de réunion |
| **Rappels** | Les rappels du jour, à cocher |
| **Automatisation** (Musique, Spotify, Terminal, iTerm) | Piloter la musique, envoyer une réponse à une session Claude dans son terminal |
| **Bluetooth** | Annoncer la connexion des appareils |

### Hooks Claude Code

Dans **Réglages → Claude → Installer les hooks**, Encoche ajoute ses hooks à `~/.claude/settings.json`. Une sauvegarde est faite dans `settings.json.notch-backup`. Les hooks envoient les événements des sessions à Encoche en local (`127.0.0.1:47823`). Rien ne sort du Mac.

Pour répondre à une session : dans Terminal ou iTerm, la réponse est tapée et envoyée dans le bon onglet. Dans l'app Claude ou un éditeur, elle est collée et attend que tu appuies sur Entrée, car la bonne conversation ne peut pas être visée à coup sûr.

### Services en ligne

Deux fonctions interrogent un service public, sans compte ni clé :

- **Paroles** : [LRCLIB](https://lrclib.net) reçoit le titre, l'artiste, l'album et la durée du morceau.
- **Suite de l'album** (quand la file de Musique n'est pas lisible) : la recherche iTunes d'Apple reçoit le titre, l'artiste et l'album.

### En cas de souci

- **Les notifications restent en bannières de macOS** : vérifie l'**Accès complet au disque** et l'**Accessibilité** dans les réglages d'Encoche. Il arrive que macOS perde sa base des notifications (dossier `~/Library/Group Containers/group.com.apple.usernoted/db2` vide) : Encoche lit alors les bannières elles-mêmes, et un redémarrage du Mac recrée la base.
- **Encoche ne se lance pas à l'ouverture de session** : vérifie qu'elle est cochée dans **Réglages Système → Général → Ouverture**, ou ouvre-la depuis Applications.
- **Une autorisation semble perdue après une mise à jour** : retire Encoche de la liste concernée dans **Confidentialité et sécurité**, puis rajoute-la.

### Désinstallation

1. Dans les réglages d'Encoche, section **Claude**, clique sur **Désinstaller les hooks** (sinon Claude Code continue d'appeler un serveur absent, sans conséquence).
2. Quitte Encoche (clic droit sur l'encoche → Quitter Encoche) et mets `/Applications/Encoche.app` à la corbeille.
3. Si tu veux effacer ses données (historiques, captures de l'Étagère) : le dossier `~/Library/Application Support/Notch`.
4. Depuis le code source, le certificat « Notch Local Signing » peut être supprimé dans Trousseaux d'accès.

### Limites connues

- La **file d'attente** de Musique est lue dans son panneau « File d'attente » : il doit être ouvert dans la fenêtre Musique (Encoche propose un bouton pour l'ouvrir). Spotify ne partage pas sa file.
- L'affichage sur l'**écran de verrouillage**, la file de Musique, le mode Concentration, les lecteurs autres que Musique et Spotify et les bannières de macOS reposent sur des mécanismes non documentés : une mise à jour de macOS peut les casser. Encoche échoue alors en silence.
- Les lecteurs autres que Musique et Spotify passent par [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (licence BSD, copié dans `Vendor/`), qui donne accès au « À l'écoute » de macOS.

## Développement

L'app est écrite en **Swift 6** (vérification stricte de la concurrence, avertissements traités comme des erreurs) avec SwiftUI. Mêmes prérequis que l'installation depuis le code source.

```bash
./scripts/run.sh          # compile en Debug et relance l'app
./scripts/test.sh         # tests unitaires de la logique (NotchTests)
./scripts/format.sh       # met le code en forme (--check : vérifie seulement, comme la CI)
./scripts/install.sh      # compile en Release et installe dans /Applications
./scripts/release.sh      # version universelle zippée dans dist/, pour une Release GitHub
```

Les tests n'ouvrent ni serveur ni fenêtre, et ne touchent à aucun fichier réel : ils travaillent dans des dossiers temporaires et sur des presse-papier de test. La CI GitHub (`.github/workflows/ci.yml`) vérifie la mise en forme, compile et lance les tests à chaque push et pull request.

Le projet Xcode est généré par XcodeGen depuis `project.yml`. Ne modifie pas le `.xcodeproj` : il n'est pas versionné. La version de l'app (`CFBundleShortVersionString`) est aussi dans `project.yml`.

L'icône est dessinée par code. Pour la retoucher, modifie le script puis relance-le :

```bash
swift scripts/make-icon.swift
```

### Organisation

| Dossier | Contenu |
|---|---|
| `Notch/App` | Lancement, fenêtres de l'encoche, écrans et placement (`ScreenLayout`), plein écran, audio (`AudioHardware`), réglages |
| `Notch/UI` | Vue de l'encoche, onglets, forme |
| `Notch/Music` | Musique et Spotify, paroles, file d'attente |
| `Notch/Calendar` | Calendrier et rappels de réunion |
| `Notch/Clipboard` | Historique du presse-papier |
| `Notch/Home` | Onglet Raccourcis |
| `Notch/Shelf` | Étagère et captures d'écran |
| `Notch/Notifications` | Notifications macOS, bannières, historique |
| `Notch/Claude` | Questions à Claude, sessions Claude Code, réponses, hooks |
| `Notch/HUD` | Activités en direct, téléchargements, Bluetooth, batterie, luminosité, caméra et micro |
| `Notch/Volume` | Volume et touches du clavier |
| `Notch/LockScreen` | Écran de verrouillage |
| `Notch/Timer` | Minuteur et Pomodoro |
| `Notch/Settings` | Fenêtre de réglages |
| `Notch/Reminders` | Rappels du jour |
| `NotchTests` | Tests unitaires (Swift Testing) |
| `Vendor/MediaRemoteAdapter` | Accès au « À l'écoute » de macOS (projet open source) |

Le code s'appelle encore `Notch` en interne (dossiers, cibles, identifiant `com.guillaumeprost.notch`). Garder l'identifiant permet à macOS de conserver les autorisations déjà accordées.
