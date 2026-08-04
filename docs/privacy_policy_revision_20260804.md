# REVV 개인정보 처리방침 개정 문안 (EN / KR / FR) — 2026-08-04

Notion 페이지에 붙여넣을 전체 문안. 근거는 `docs/privacy_data_inventory_20260730.md`.

**바뀐 곳은 §4와 §5 두 군데다.** 나머지 섹션은 현행 문안을 그대로 유지하고
프랑스어만 추가했다. 앱이 한/영/불 3개 언어를 지원하므로 처리방침도 맞춘다.

- **§4**: 제3자 4곳 추가 (OpenStreetMap/Overpass · OpenWeatherMap · Google Fonts),
  Mapbox 설명에 목적지 검색(지오코딩) 포함
- **§5**: 백그라운드 위치·자동 기록 항목 **삭제** — 앱에 없는 기능이다
  (`UIBackgroundModes`는 `audio` 하나뿐, always 권한 요청 없음)

> ⚠️ **폰트를 번들하기로 하면** §4의 Google Fonts 항목을 빼야 한다. 아래 문안에
> 해당 문단은 `[폰트 번들 시 삭제]`로 표시해 두었다.

---

# REVV Privacy Policy / 개인정보 처리방침 / Politique de confidentialité

**Last updated / 마지막 업데이트 / Dernière mise à jour: 2026-08-04**

## 1. Overview / 개요 / Aperçu

REVV is a route discovery and driving rhythm copilot app. REVV helps drivers find
available curvy routes, preview route details, follow route progress during a
drive, and save post-drive summaries.

REVV는 운전자가 이용 가능한 와인딩 루트를 찾고, 루트 정보를 확인하며, 주행 중 루트
진행을 보고, 주행 후 요약을 저장하기 위한 앱입니다.

REVV est une application de découverte d'itinéraires et de copilote de rythme de
conduite. REVV aide les conducteurs à trouver des routes sinueuses disponibles, à
consulter les détails d'un itinéraire, à suivre leur progression pendant un trajet
et à enregistrer des résumés après le trajet.

## 2. Data We Collect / 수집하는 데이터 / Données collectées

REVV may collect or process the following data to provide app functionality:

- **Location data**: used for nearby route discovery, current location display,
  route progress, and drive tracking. Location is used only while the app is open.
- **Driving data**: distance, duration, route samples, speed, G-force values,
  selected route, and drive summaries.
- **User identifier**: a Supabase anonymous identifier used to separate each
  user's records. REVV does not collect your name, email address, or phone number.
- **Route feedback**: route ratings, safety feedback, hidden routes, and
  "do not recommend again" choices.
- **Destination searches**: the text you type when searching for a destination.
- **Exploration progress**: coarse map cell identifiers derived after a saved real
  drive. The exploration feature does not upload an additional ordered GPS
  breadcrumb stream.

REVV는 앱 기능 제공을 위해 다음 데이터를 수집하거나 처리할 수 있습니다.

- **위치 데이터**: 주변 루트 탐색, 현재 위치 표시, 루트 진행률 계산, 주행 기록에
  사용됩니다. 위치는 앱이 열려 있는 동안에만 사용됩니다.
- **주행 데이터**: 거리, 시간, 경로 샘플, 속도, G값, 선택 루트, 주행 요약이
  포함될 수 있습니다.
- **사용자 식별자**: Supabase 익명 ID를 사용해 사용자별 기록을 분리합니다. REVV는
  이름, 이메일 주소, 전화번호를 수집하지 않습니다.
- **루트 피드백**: 루트 평가, 위험 신고, 숨김, 다시 추천하지 않기 선택을 저장할
  수 있습니다.
- **목적지 검색어**: 목적지를 검색할 때 입력한 텍스트입니다.
- **탐험 진행 정보**: 실제 주행을 저장한 뒤 생성되는 저해상도 지도 셀 ID입니다.
  탐험 기능을 위해 별도의 시간순 GPS 원본 경로를 추가 업로드하지 않습니다.

REVV peut collecter ou traiter les données suivantes pour fournir les
fonctionnalités de l'application :

- **Données de localisation** : utilisées pour découvrir les itinéraires à
  proximité, afficher votre position, suivre la progression et enregistrer le
  trajet. La position est utilisée uniquement lorsque l'application est ouverte.
- **Données de conduite** : distance, durée, échantillons d'itinéraire, vitesse,
  valeurs de force G, itinéraire sélectionné et résumés de trajet.
- **Identifiant utilisateur** : un identifiant anonyme Supabase servant à séparer
  les enregistrements de chaque utilisateur. REVV ne collecte ni votre nom, ni
  votre adresse e-mail, ni votre numéro de téléphone.
- **Retours sur les itinéraires** : évaluations, signalements de sécurité,
  itinéraires masqués et choix « ne plus recommander ».
- **Recherches de destination** : le texte saisi lors d'une recherche.
- **Progression d'exploration** : identifiants de cellules de carte à faible
  résolution générés après l'enregistrement d'un trajet réel. Cette fonction
  n'envoie aucun flux GPS ordonné supplémentaire.

## 3. How We Use Data / 데이터 사용 목적 / Utilisation des données

We use data only for app functionality, including: finding relevant driving
routes; showing route progress during a drive; saving and restoring drive
history; restoring coarse explored-map progress for the current anonymous REVV
cloud identity; improving route recommendation quality; and responding to route
feedback and resolving app issues.

수집한 데이터는 다음 목적에만 사용합니다. 관련성 높은 주행 루트 추천, 주행 중 루트
진행 안내, 주행 기록 저장 및 복원, 현재 REVV 익명 클라우드 ID에 연결된 저해상도
탐험 진행 복원, 루트 추천 품질 개선, 루트 피드백 대응 및 앱 문제 해결.

Nous utilisons les données uniquement pour le fonctionnement de l'application :
trouver des itinéraires pertinents, afficher la progression pendant un trajet,
enregistrer et restaurer l'historique, restaurer la progression d'exploration à
faible résolution liée à l'identité cloud anonyme REVV en cours, améliorer la
qualité des recommandations, et traiter les retours et les problèmes techniques.

## 4. Data Sharing / 데이터 공유 / Partage des données  ← **개정**

REVV does not sell personal data and does not use collected data for third-party
advertising tracking.

REVV uses the following service providers to deliver app functionality. Each
processes data only as needed for that purpose:

- **Supabase** — data storage and anonymous authentication. Stores your drive
  records, telemetry, and feedback when cloud storage is enabled.
- **Mapbox** — map display **and destination search**. Map tiles are requested as
  you move the map. When you search for a destination, your search term and your
  approximate location are sent to Mapbox to return matching places.
- **OpenStreetMap / Overpass API** — road data used to discover curvy routes.
  Queries covering the map area you are viewing are sent to public Overpass
  servers.
- **OpenWeatherMap** — weather conditions shown for a drive. Your coordinates are
  sent through our own server rather than directly from your device.
- **Google Fonts** — the app loads its typefaces from Google's font service at
  runtime, which makes your device's IP address visible to Google.
  *[폰트 번들 시 이 항목 삭제]*

When you choose to open external navigation, REVV sends the selected route
coordinates, and when applicable your current or saved home location, to Google
Maps or Waze through an HTTPS link so that the provider can calculate and display
directions. This transfer occurs only after you select the external navigation
action and is then governed by that provider's privacy policy.

REVV는 개인정보를 판매하지 않으며, 제3자 광고 추적 목적으로 데이터를 사용하지
않습니다.

REVV는 앱 기능 제공을 위해 다음 서비스 제공자를 사용합니다. 각 제공자는 해당 목적에
필요한 범위에서만 데이터를 처리합니다.

- **Supabase** — 데이터 저장 및 익명 인증. 클라우드 저장을 켠 경우 주행 기록,
  텔레메트리, 피드백이 저장됩니다.
- **Mapbox** — 지도 표시 **및 목적지 검색**. 지도를 움직이면 타일이 요청되며,
  목적지를 검색하면 검색어와 대략적인 위치가 Mapbox로 전달되어 장소를 반환합니다.
- **OpenStreetMap / Overpass API** — 와인딩 루트를 찾기 위한 도로 데이터. 보고 있는
  지도 영역에 대한 쿼리가 공개 Overpass 서버로 전달됩니다.
- **OpenWeatherMap** — 주행 날씨 표시. 좌표가 기기에서 직접이 아니라 REVV 서버를
  거쳐 전달됩니다.
- **Google Fonts** — 앱 실행 시 Google 폰트 서비스에서 서체를 불러오며, 이 과정에서
  기기 IP 주소가 Google에 노출됩니다. *[폰트 번들 시 이 항목 삭제]*

사용자가 외부 내비게이션 열기를 선택하면 REVV는 경로 계산과 표시를 위해 선택한 루트
좌표와 필요한 경우 현재 위치 또는 저장한 집 위치를 HTTPS 링크로 Google Maps 또는
Waze에 전달합니다. 이 전달은 사용자가 외부 내비게이션 동작을 직접 선택한 경우에만
발생하며, 이후 처리는 각 제공자의 개인정보 처리방침을 따릅니다.

REVV ne vend aucune donnée personnelle et n'utilise pas les données collectées à
des fins de suivi publicitaire par des tiers.

REVV fait appel aux prestataires suivants pour fournir ses fonctionnalités. Chacun
ne traite les données que dans la mesure nécessaire :

- **Supabase** — stockage des données et authentification anonyme. Enregistre vos
  trajets, télémétries et retours lorsque le stockage cloud est activé.
- **Mapbox** — affichage de la carte **et recherche de destination**. Les tuiles
  sont demandées lorsque vous déplacez la carte. Lors d'une recherche, votre terme
  de recherche et votre position approximative sont envoyés à Mapbox.
- **OpenStreetMap / API Overpass** — données routières servant à découvrir les
  routes sinueuses. Les requêtes couvrant la zone affichée sont envoyées à des
  serveurs Overpass publics.
- **OpenWeatherMap** — conditions météo affichées pour un trajet. Vos coordonnées
  transitent par notre serveur plutôt que directement depuis votre appareil.
- **Google Fonts** — l'application charge ses polices depuis le service Google au
  moment de l'exécution, ce qui rend l'adresse IP de votre appareil visible par
  Google. *[폰트 번들 시 이 항목 삭제]*

Lorsque vous choisissez d'ouvrir une navigation externe, REVV transmet les
coordonnées de l'itinéraire sélectionné, et le cas échéant votre position actuelle
ou votre domicile enregistré, à Google Maps ou Waze via un lien HTTPS afin que le
fournisseur puisse calculer et afficher l'itinéraire. Ce transfert n'a lieu
qu'après votre sélection et relève ensuite de la politique de ce fournisseur.

## 5. User Controls / 사용자 제어 / Contrôles utilisateur  ← **개정**

You can:

- Turn cloud drive history storage on or off in the app. It is **off by default**,
  so drive records stay on your device unless you enable it.
- Delete saved driving records in the app.
- Delete explored-map progress together with saved driving records.
- Delete the guest cloud account and its associated server-side data in the app.
- Change or revoke location permission in iOS Settings.

REVV does not use background location. Location is requested only while the app is
open and in use.

사용자는 다음을 제어할 수 있습니다.

- 앱에서 클라우드 주행 기록 저장을 켜거나 끌 수 있습니다. **기본값은 꺼짐**이며,
  켜기 전까지 주행 기록은 기기에만 남습니다.
- 앱에서 저장된 주행 기록을 삭제할 수 있습니다.
- 저장된 주행 기록과 함께 탐험 지도 진행을 삭제할 수 있습니다.
- 앱에서 게스트 클라우드 계정과 연결된 서버 데이터를 삭제할 수 있습니다.
- iOS 설정에서 위치 권한을 변경하거나 철회할 수 있습니다.

REVV는 백그라운드 위치를 사용하지 않습니다. 위치는 앱이 열려 사용 중일 때만
요청됩니다.

Vous pouvez :

- Activer ou désactiver le stockage cloud de l'historique dans l'application. Il
  est **désactivé par défaut** : vos trajets restent sur votre appareil tant que
  vous ne l'activez pas.
- Supprimer les trajets enregistrés dans l'application.
- Supprimer la progression d'exploration en même temps que les trajets.
- Supprimer le compte cloud invité et les données serveur associées.
- Modifier ou révoquer l'autorisation de localisation dans les Réglages iOS.

REVV n'utilise pas la localisation en arrière-plan. La position n'est demandée que
lorsque l'application est ouverte et utilisée.

## 6. Data Retention / 데이터 보관 / Conservation des données

Drive records may be stored until you delete them. Pending local upload data may be
temporarily stored on the device to prevent drive data loss when the network is
unavailable.

주행 기록은 사용자가 삭제할 때까지 저장될 수 있습니다. 네트워크가 불안정할 때 주행
데이터 손실을 막기 위해 업로드 대기 데이터가 기기에 일시적으로 저장될 수 있습니다.

Les trajets peuvent être conservés jusqu'à leur suppression par vos soins. Des
données en attente d'envoi peuvent être stockées temporairement sur l'appareil afin
d'éviter toute perte lorsque le réseau est indisponible.

## 7. Contact / 문의 / Contact

For privacy questions or deletion requests, contact: **gksalsdn1234559@gmail.com**

개인정보 관련 문의 또는 삭제 요청은 **gksalsdn1234559@gmail.com** 으로 연락해 주세요.

Pour toute question relative à la confidentialité ou une demande de suppression :
**gksalsdn1234559@gmail.com**

## 8. App Support / 앱 지원 / Assistance

For help with REVV, email gksalsdn1234559@gmail.com. Include the app version, iOS
version, device model, and a short description of the issue. Do not send passwords,
authentication codes, or precise trip and location history.

REVV 사용 관련 지원은 gksalsdn1234559@gmail.com으로 문의해 주세요. 앱 버전, iOS 버전,
기기 모델, 문제에 대한 간단한 설명을 포함해 주세요. 비밀번호, 인증 코드, 상세 주행
또는 위치 기록은 보내지 마세요.

Pour obtenir de l'aide, écrivez à gksalsdn1234559@gmail.com en précisant la version
de l'application, la version d'iOS, le modèle d'appareil et une brève description du
problème. N'envoyez jamais de mots de passe, de codes d'authentification, ni
d'historique précis de trajets ou de positions.

---

## 붙여넣기 전 확인할 것

1. **§2 "탐험 진행 정보"** — 이 문단은 현행 문안을 그대로 옮겼다. 대응 코드를
   확인하지 못했으므로 실제 구현과 맞는지 민우가 확인할 것
2. **§5 "게스트 클라우드 계정 삭제"** — 마찬가지로 현행 문안 유지. 앱에서
   `deleteAllRunData`는 확인했으나 서버 계정 삭제까지 되는지는 미확인
3. **Google Fonts 문단** — 폰트를 번들하기로 하면 3개 언어 모두에서 삭제
4. **마이크·음성인식**은 처리방침에 없다. 워키토키가 심사 빌드에서 제외되므로
   현재는 맞지만, 나중에 켜면 §2·§4에 추가해야 한다
5. **Sentry**는 현재 `SENTRY_DSN` 미설정으로 비활성이라 뺐다. 켜면 §4에 추가
