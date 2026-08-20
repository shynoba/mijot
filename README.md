<p align="center">
  <img src="./GitHubBanner.png" alt="Mijot" width="100%">
</p>

# Mijot — assistant de repas iOS à partir de tickets PDF

Lors du lancement de l'application, un profil nutritionnel est réalisé très rapidement puis ensuite a partir d'un ticket PDF, une analyse est faite par Gemini, laissant l’utilisateur corriger les aliments retenus ainsi que les coûts, le tout alimente un inventaire JSON privé stocké sur l’appareil.

La détection et les recettes reposent sur Gemini avec la clé personnelle de l’utilisateur. Aucun catalogue de recettes local n’est affiché : le nombre de recettes choisi par l’utilisateur est généré pour le stock réellement présent.

## Fonctionnalités

- import d’un ticket PDF avec PDFKit ;
- analyse visuelle directe du PDF avec Gemini 3.5 Flash ;
- OCR local de secours avec Vision pour les documents trop volumineux ;
- exclusion par Gemini des adresses, téléphones, prix, TVA et lignes de paiement ;
- validation des noms, quantités, unités, catégories, rangements et émojis avant import ;
- récupération du prix réellement payé pour chaque ligne alimentaire du ticket, avec correction manuelle possible ;
- calcul du prix par gramme, litre ou pièce et conservation de ce coût dans le stock ;
- identification visuelle de chaque article avec un émoji précis proposé par Gemini et modifiable ;
- séparation du stock entre **Au frigo** et **À l’air libre** ;
- classement en **Viandes & poissons**, **Fruits & légumes**, **Laitages** et **Snacks & épicerie** ;
- noix, épicerie sèche, conserves et aliments similaires conservés hors du frigo lorsque Gemini le recommande ;
- inventaire local et historique des mouvements ;
- génération Gemini automatique avec réponse JSON structurée lorsque le stock change ;
- page d’accueil avec profil alimentaire personnel ;
- personnalisation par régime, objectifs, allergies, aliments refusés ou appréciés, cuisines favorites et consigne libre ;
- plage calorique, caractère obligatoire ou facultatif du féculent, liste des féculents autorisés, niveau d’épices et temps maximal entièrement réglables ;
- régénération automatique des recettes dès que le profil change ;
- recettes composées par Gemini pour une personne, composées de quatre à sept ingrédients et d’étapes complètes ;
- repas dans la plage calorique choisie, avec au choix riz, pâtes, pommes de terre, semoule, quinoa, pain ou légumineuses ;
- estimation du coût d’une portion à partir des quantités de la recette et des prix du ticket ;
- affichage du coût de chaque repas, du budget total des recettes et du prix moyen par repas ;
- choix de 1 à 14 recettes immédiatement après la validation d’un ticket ;
- réglages persistants pour le four, la poêle et l’Airfryer ;
- deux idées de repas rapprochées lorsque viande ou poisson correspondent à deux portions ;
- clé Gemini conservée dans le Trousseau iOS, jamais dans le code source ;
- ajout d’une recette à un ou plusieurs jours, au déjeuner ou au dîner, puis planning hebdomadaire avec déplacement par glisser-déposer ;
- intégration EventKit avec les calendriers Apple, iCloud déjà configurés sur l’appareil ;
- choix du calendrier de destination et horaires persistants : déjeuner à 12 h 30 et dîner à 19 h 30 par défaut ;
- création d’un événement contenant le nom du plat, les portions, les calories et les ingrédients ;
- déplacement et suppression répercutés dans le calendrier pour les repas synchronisés ;
- déduction des ingrédients uniquement après « Plat préparé » ;
- échéance automatique à 48 h pour viande et poisson frais détectés par Gemini ;
- identité **Mijot**, icône minimaliste noire et blanche, et interface SwiftUI compacte inspirée des conventions Apple.

## Ouvrir le projet

1. Ouvrir `Mijot.xcodeproj` avec Xcode 26.6 ou plus.
2. Choisir un simulateur iPhone avec iOS 18 ou plus.
3. Lancer la cible `Mijot`.

Le projet utilise une signature automatique. Pour l’installer sur un iPhone, sélectionner son équipe de développement dans **Signing & Capabilities**.
Il faut savoir qu'au bout de une semaine, l'application ne s'ouvrira plus du a l'équipe de développement gratuite, il suffira de recompiler l'application sur l'appareil iOS, dans le cas inverse il faut payer une licence de développement.

## Activer Gemini gratuitement pour un usage personnel

1. Créer une clé dans [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Dans l’onglet **Pour vous**, toucher l’icône en haut à droite.
3. Coller la clé, puis choisir **Enregistrer et générer**.

Les appareils de cuisine se règlent dans **Recettes → Réglages**. Gemini ne propose ensuite que des étapes compatibles avec les appareils activés.

## Synchroniser Apple Calendar ou Google Calendar

1. Ouvrir l’onglet **Semaine** puis toucher l’icône de calendrier en haut à droite.
2. Activer **Ajouter les repas au calendrier** et autoriser l’accès demandé par iOS.
3. Choisir le calendrier de destination puis régler les horaires du déjeuner, du dîner et la durée d’un repas.
4. Planifier une recette : Mijot crée l’événement à l’heure correspondante.

Google Calendar apparaît automatiquement dans cette liste si le compte Google est ajouté aux comptes Calendrier de l’iPhone. L’enregistrement EventKit se synchronise ensuite par le compte choisi ; aucune clé Google supplémentaire n’est nécessaire.

L’analyse des tickets utilise `gemini-3.5-flash` et les recettes utilisent `gemini-3.5-flash-lite`. L’application ne facture rien, mais le quota gratuit, la disponibilité des modèles et l’utilisation des données restent soumis aux conditions de Google. Sans accès à Gemini, aucune fausse recette locale n’est substituée.

### Données envoyées

Pour détecter correctement les colonnes et les libellés, le PDF sélectionné est envoyé à Gemini lorsqu’il fait moins de 12 Mo. Au-delà, l’app envoie le texte extrait localement, avec OCR Vision si nécessaire. La génération de recettes envoie les noms, quantités, unités, catégories, rangements, éventuelles dates limites et le profil alimentaire saisi sur l’accueil. Le profil reste enregistré localement. La clé est stockée dans le Trousseau avec une accessibilité limitée à cet appareil.

Cette approche avec une clé saisie par l’utilisateur convient à un prototype personnel. Pour publier l’app, placer les appels Gemini derrière un serveur intermédiaire avec authentification et quotas : une application distribuée ne doit contenir ni partager une clé de service.

## Limites du prototype

La structure des tickets varie selon les magasins. Le parseur couvre les lignes usuelles et l’écran de validation est volontairement obligatoire. L’OCR ne garantit pas une lecture parfaite des tickets flous ou inclinés. Le plus adapté est les .pdf directement récupérer dans les applications des supermarchés.

L’inventaire est mis à jour au moment où l’utilisateur confirme **Plat préparé**. L’app ne peut pas détecter physiquement, sans capteur, qu’un aliment a été consommé autrement ; les corrections manuelles restent donc possibles.


## Ajouts à venir 

- Ajout d'un mode famille
    - Modifier le nombre de personne
    - Option de calendrier partagé
    - Choix nutritionnel de chaque
 
