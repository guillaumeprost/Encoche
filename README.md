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
- **Musique** : le lecteur, et au choix les **paroles synchronisées** (la ligne chantée est mise en avant, un clic y saute) ou la **file d'attente** de Musique.
- **Maison** : une tuile par raccourci du dossier « Encoche » de l'app Raccourcis (allumer une lampe, lancer une scène…).
- **Étagère** : les dernières captures d'écran, à glisser où tu veux.
- **Presse-papier** : l'historique de ce que tu as copié. Les mots de passe des gestionnaires sont ignorés.
- **Notifications** : l'historique des notifications, conservé d'un redémarrage à l'autre.
- **Claude** : tes 5 dernières sessions Claude Code, avec leur progression, leurs agents et leur conversation, un champ pour **répondre à une session** ou poser une question rapide.

Quand une musique est chargée, une mini-pochette avec lecture/pause et suivant s'affiche en haut à droite.

### Autour de l'encoche fermée
- **Activités en direct** : musique, Claude Code qui travaille (avec l'avancement de son plan), téléchargements, caméra et micro. L'encoche s'agrandit un peu, et une deuxième activité s'affiche dans une **bulle** à côté, comme sur iPhone.
- **Notifications façon iPhone** : toutes les notifications du Mac s'affichent dans l'encoche à la place des bannières de macOS, sur l'écran principal. Au survol, elles se déplient et proposent de les fermer ; un clic les ouvre.
- **Claude Code** : quand Claude demande une autorisation, tu peux **autoriser ou refuser depuis l'encoche**.
- **Réunions** : un rappel une minute avant, avec un bouton **Rejoindre** pour Meet, Zoom, Teams, Webex, FaceTime ou Whereby.
- **Volume, luminosité, batterie** : affichés sous l'encoche, sans masquer l'activité en cours.
- **Appareils Bluetooth** : AirPods, casque ou clavier qui se connectent, avec leur batterie.
- **Écran de verrouillage** : un cadenas dans l'encoche qui s'ouvre au déverrouillage, le lecteur de musique, et un son au choix.

### Et aussi
- Une encoche sur **chaque écran**.
- Masquée quand une app est **en plein écran**, elle redescend avec la barre de menus quand la souris touche le haut de l'écran.
- **Réglages** (clic droit sur l'encoche → Réglages…) : style de l'encoche (noir, verre noir, Liquid Glass), activités, écran de verrouillage, et l'état de chaque autorisation.
- Très légère : environ 0,1 % de processeur au repos.

## Configuration requise

- macOS 26 ou plus récent
- Xcode 26 et [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Pour Claude : [Claude Code](https://claude.com/claude-code), connecté à ton abonnement. Encoche passe par la commande `claude`, sans clé d'API.

## Installation

1. Crée une seule fois le certificat de signature local. Il garde la même identité à l'app d'un build à l'autre, et macOS conserve ainsi les autorisations accordées :
   ```bash
   ./scripts/create-signing-cert.sh
   ```
2. Compile et installe dans `/Applications`. Le script lance aussi l'app :
   ```bash
   ./scripts/install.sh
   ```

Au premier lancement, Encoche s'ajoute aux éléments d'ouverture du Mac (désactivable dans les réglages).

### Autorisations

Encoche te guide pour chacune. Leur état est visible dans ses réglages.

| Autorisation | Pour quoi faire |
|---|---|
| **Accès complet au disque** | Lire les notifications des autres apps |
| **Accessibilité** | Touches volume et luminosité, masquer les bannières de macOS, lire la file d'attente de Musique, coller une réponse dans une session Claude |
| **Calendrier** | L'agenda et les rappels de réunion |
| **Automatisation** (Musique, Spotify, Terminal, iTerm) | Piloter la musique, envoyer une réponse à une session Claude dans son terminal |
| **Bluetooth** | Annoncer la connexion des appareils |

### Claude Code

Dans **Réglages → Claude → Installer les hooks**, Encoche ajoute ses hooks à `~/.claude/settings.json`. Une sauvegarde est faite dans `settings.json.notch-backup`. Les hooks envoient les événements des sessions à Encoche en local (`127.0.0.1:47823`). Rien ne sort du Mac.

Pour répondre à une session : dans Terminal ou iTerm, la réponse est tapée et envoyée dans le bon onglet. Dans l'app Claude ou un éditeur, elle est collée et attend que tu appuies sur Entrée, car la bonne conversation ne peut pas être visée à coup sûr.

### Services en ligne

Deux fonctions interrogent un service public, sans compte ni clé :

- **Paroles** : [LRCLIB](https://lrclib.net) reçoit le titre, l'artiste, l'album et la durée du morceau.
- **Suite de l'album** (quand la file de Musique n'est pas lisible) : la recherche iTunes d'Apple reçoit le titre, l'artiste et l'album.

### Limites connues

- La **file d'attente** de Musique est lue dans son panneau « File d'attente » : il doit être ouvert dans la fenêtre Musique (Encoche propose un bouton pour l'ouvrir). Spotify ne partage pas sa file.
- L'affichage sur l'**écran de verrouillage**, la file de Musique et les bannières de macOS reposent sur des mécanismes non documentés : une mise à jour de macOS peut les casser. Encoche échoue alors en silence.

## Développement

```bash
./scripts/run.sh          # compile en Debug et relance l'app
```

Le projet Xcode est généré par XcodeGen depuis `project.yml`. Ne modifie pas le `.xcodeproj` : il n'est pas versionné.

L'icône est dessinée par code. Pour la retoucher, modifie le script puis relance-le :

```bash
swift scripts/make-icon.swift
```

### Organisation

| Dossier | Contenu |
|---|---|
| `Notch/App` | Lancement, fenêtres de l'encoche, écrans, plein écran, réglages |
| `Notch/UI` | Vue de l'encoche, onglets, forme |
| `Notch/Music` | Musique et Spotify, paroles, file d'attente |
| `Notch/Calendar` | Calendrier et rappels de réunion |
| `Notch/Clipboard` | Historique du presse-papier |
| `Notch/Home` | Onglet Maison (raccourcis) |
| `Notch/Shelf` | Étagère et captures d'écran |
| `Notch/Notifications` | Notifications macOS, bannières, historique |
| `Notch/Claude` | Questions à Claude, sessions Claude Code, réponses, hooks |
| `Notch/HUD` | Activités en direct, téléchargements, Bluetooth, batterie, luminosité, caméra et micro |
| `Notch/Volume` | Volume et touches du clavier |
| `Notch/LockScreen` | Écran de verrouillage |
| `Notch/Settings` | Fenêtre de réglages |

Le code s'appelle encore `Notch` en interne (dossiers, cibles, identifiant `com.guillaumeprost.notch`). Garder l'identifiant permet à macOS de conserver les autorisations déjà accordées.
