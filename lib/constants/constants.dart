import 'package:livekit_client/livekit_client.dart';
import 'package:meet/rust/proton_meet/user_config.dart';

/// ui constants
const double defaultPadding = 16.0;

/// used for desktop
const double maxDeskTopSheetWidth = 600.0;
const double drawerMaxWidth = 400;
const double maxMobileSheetWidth = 500.0;

/// default animation duration
const Duration defaultAnimationDuration = Duration(milliseconds: 260);
const Duration defaultAnimationDurationLong = Duration(milliseconds: 500);

/// database versions
const int driftDatabaseVersion = 1;
const int rustDatabaseVersion = 2;

/// meet
const String systemMessageIdentity = "ProtonMeetSystemMessageIdentity";

/// LiveKit
const String livekitRoomKey = "ProtonMeetStaticRoomKey2025042118";

/// Hive files
const String hiveFilesName = "protono_meet_shared_preference";

const String defaultRoomId = "Proton-Meet-For-MSA";

/// user settings
const VideoResolution defaultCameraResolution = VideoResolution.p720;
const VideoResolution defaultScreenSharingResolution = VideoResolution.p1080;
const VideoMaxBitrate defaultCameraMaxBitrate = VideoMaxBitrate.kbps500;
const VideoMaxBitrate defaultScreenSharingMaxBitrate = VideoMaxBitrate.kbps1000;
const CameraPosition defaultCameraPosition = CameraPosition.front;
const int maxDisplayNameLength = 50;

/// Dart-side watchdog for meeting-link join/auth calls that reach the server
/// over the muon HTTP path, which has no request timeout. A reused-but-dead
/// keep-alive connection can otherwise hang these calls forever and leave the
/// loading spinner stuck. Used by both the pre-join `authenticateForJoin` SRP
/// auth and the waiting-room `RoomManager.connectToRoom` join, so either screen
/// can surface an error and let the user retry instead of spinning indefinitely.
const Duration kAuthenticateMeetingLinkTimeout = Duration(seconds: 20);

/// Earliest start when scheduling a new meeting (buffer while the user fills the form).
const int scheduleMeetingMinLeadMinutes = 15;

/// Round schedule start times up to this minute interval.
const int scheduleMeetingTimeRoundMinutes = 5;

/// guest meeting room size
const int guestMeetingRoomSize = 4;

/// delay subscription update
const Duration delaySubscriptionUpdate = Duration(milliseconds: 5000);

/// Remote participant count below which we poll for late camera track attachment.
const int smallMeetingRemoteParticipantThreshold = 20;

/// Interval for re-running [SortParticipants] while a remote user has camera
/// enabled but the video track is not attached yet (small meetings only).
const Duration pendingCameraVideoTrackCheckInterval = Duration(seconds: 5);

/// Initial delay before retrying a failed visible-camera bind.
const Duration videoSubscriptionBindRetryDelay = Duration(seconds: 2);

/// Max retries after [waitForVideoTrackBound] times out for a visible tile.
const int maxVideoSubscriptionBindRetries = 3;

const Duration audioSubscribeTimeout = Duration(seconds: 10);
const Duration audioSubscribeRetryBaseDelay = Duration(seconds: 2);
const Duration audioSubscribeRetryMaxDelay = Duration(seconds: 8);
const int maxAudioSubscribeRetries = 3;

/// Min interval between sort-path [reconcileInFlightAudioSubscribes] passes.
const Duration audioReconcileMinInterval = Duration(seconds: 2);

/// How long to let LiveKit's built-in reconnect (resume / full-restart) run
/// before escalating to a fresh App-level rejoin ([StartRejoinMeeting]).
const Duration livekitReconnectEscalationTimeout = Duration(seconds: 20);

/// Maximum number of consecutive App-level rejoins triggered by an MLS
/// out-of-sync failure before we stop auto-rejoining and surface the error
/// dialog instead of looping forever.
const int kMaxMlsRecoveryRejoins = 3;

/// When to snapshot remote audio publication + audio engine state after join,
/// for diagnosing "joined muted and nobody is audible" reports.
const List<Duration> audioDiagnosticSnapshotDelays = [
  Duration(seconds: 3),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 40),
];

/// delay unsubscribe track
const Duration delayUnsubscribeTrack = Duration(milliseconds: 2000);

/// Room auto fullscreen
const Duration autoFullScreenDelay = Duration(seconds: 10);

/// How often the host room polls for expired waiting-room join requests.
const Duration waitingRoomJoinRequestExpirationPollInterval = Duration(
  seconds: 1,
);

/// Retries for resolving a waiting-room guest display name (participants API
/// may lag behind the join-request websocket). Retried on the existing 1s poll
/// tick, batched into a single getParticipants call.
const int waitingRoomJoinRequestDisplayNameRetryCount = 3;

/// Debounced interval between waiting-room display-name resolve attempts.
const Duration waitingRoomJoinRequestDisplayNameRetryDelay = Duration(
  seconds: 2,
);

/// Expired waiting-room join requests received in one host session before
/// reporting to Sentry (report when count exceeds this value).
const int waitingRoomExpiredJoinRequestSentryThreshold = 3;

/// Simulation
const int defaultSimulationParticipantCount = 1;
const bool defaultSimulationEnableVideo = true;

/// Error dialog settings
const bool showExpandableErrorDetails = true;

/// Emoji reactions
const int reactionDisplayDurationMs = 3000;
const List<String> availableEmojiReactions = [
  '👍',
  '👎',
  '👏',
  '😁',
  '❤️',
  '🎉',
  '🙌',
];
const String raisedHandEmoji = '🤚';

/// Valid IANA timezone identifiers for timezone selection.
/// This list excludes deprecated and invalid timezones.
const List<String> validTimeZones = [
  'Africa/Abidjan',
  'Africa/Accra',
  'Africa/Algiers',
  'Africa/Bissau',
  'Africa/Cairo',
  'Africa/Casablanca',
  'Africa/Ceuta',
  'Africa/El_Aaiun',
  'Africa/Johannesburg',
  'Africa/Juba',
  'Africa/Khartoum',
  'Africa/Lagos',
  'Africa/Maputo',
  'Africa/Monrovia',
  'Africa/Nairobi',
  'Africa/Ndjamena',
  'Africa/Sao_Tome',
  'Africa/Tripoli',
  'Africa/Tunis',
  'Africa/Windhoek',
  'America/Adak',
  'America/Anchorage',
  'America/Araguaina',
  'America/Argentina/Buenos_Aires',
  'America/Argentina/Catamarca',
  'America/Argentina/Cordoba',
  'America/Argentina/Jujuy',
  'America/Argentina/La_Rioja',
  'America/Argentina/Mendoza',
  'America/Argentina/Rio_Gallegos',
  'America/Argentina/Salta',
  'America/Argentina/San_Juan',
  'America/Argentina/San_Luis',
  'America/Argentina/Tucuman',
  'America/Argentina/Ushuaia',
  'America/Asuncion',
  'America/Atikokan',
  'America/Bahia',
  'America/Bahia_Banderas',
  'America/Barbados',
  'America/Belem',
  'America/Belize',
  'America/Blanc-Sablon',
  'America/Boa_Vista',
  'America/Bogota',
  'America/Boise',
  'America/Cambridge_Bay',
  'America/Campo_Grande',
  'America/Cancun',
  'America/Caracas',
  'America/Cayenne',
  'America/Chicago',
  'America/Chihuahua',
  'America/Costa_Rica',
  'America/Creston',
  'America/Cuiaba',
  'America/Curacao',
  'America/Danmarkshavn',
  'America/Dawson',
  'America/Dawson_Creek',
  'America/Denver',
  'America/Detroit',
  'America/Edmonton',
  'America/Eirunepe',
  'America/El_Salvador',
  'America/Fort_Nelson',
  'America/Fortaleza',
  'America/Glace_Bay',
  'America/Goose_Bay',
  'America/Grand_Turk',
  'America/Guatemala',
  'America/Guayaquil',
  'America/Guyana',
  'America/Halifax',
  'America/Havana',
  'America/Hermosillo',
  'America/Indiana/Knox',
  'America/Indiana/Marengo',
  'America/Indiana/Petersburg',
  'America/Indiana/Tell_City',
  'America/Indiana/Vevay',
  'America/Indiana/Vincennes',
  'America/Indiana/Winamac',
  'America/Inuvik',
  'America/Iqaluit',
  'America/Jamaica',
  'America/Juneau',
  'America/Kentucky/Louisville',
  'America/Kentucky/Monticello',
  'America/La_Paz',
  'America/Lima',
  'America/Los_Angeles',
  'America/Maceio',
  'America/Managua',
  'America/Manaus',
  'America/Martinique',
  'America/Matamoros',
  'America/Mazatlan',
  'America/Menominee',
  'America/Merida',
  'America/Metlakatla',
  'America/Mexico_City',
  'America/Miquelon',
  'America/Moncton',
  'America/Monterrey',
  'America/Montevideo',
  'America/Nassau',
  'America/New_York',
  'America/Nipigon',
  'America/Nome',
  'America/Noronha',
  'America/North_Dakota/Beulah',
  'America/North_Dakota/Center',
  'America/North_Dakota/New_Salem',
  'America/Ojinaga',
  'America/Panama',
  'America/Pangnirtung',
  'America/Paramaribo',
  'America/Phoenix',
  'America/Port-au-Prince',
  'America/Port_of_Spain',
  'America/Porto_Velho',
  'America/Puerto_Rico',
  'America/Punta_Arenas',
  'America/Rainy_River',
  'America/Rankin_Inlet',
  'America/Recife',
  'America/Regina',
  'America/Resolute',
  'America/Rio_Branco',
  'America/Santarem',
  'America/Santiago',
  'America/Santo_Domingo',
  'America/Sao_Paulo',
  'America/Scoresbysund',
  'America/Sitka',
  'America/St_Johns',
  'America/Swift_Current',
  'America/Tegucigalpa',
  'America/Thule',
  'America/Thunder_Bay',
  'America/Tijuana',
  'America/Toronto',
  'America/Vancouver',
  'America/Whitehorse',
  'America/Winnipeg',
  'America/Yakutat',
  'America/Yellowknife',
  'Antarctica/Casey',
  'Antarctica/Davis',
  'Antarctica/DumontDUrville',
  'Antarctica/Macquarie',
  'Antarctica/Mawson',
  'Antarctica/Palmer',
  'Antarctica/Rothera',
  'Antarctica/Syowa',
  'Antarctica/Troll',
  'Antarctica/Vostok',
  'Asia/Almaty',
  'Asia/Amman',
  'Asia/Anadyr',
  'Asia/Aqtau',
  'Asia/Aqtobe',
  'Asia/Ashgabat',
  'Asia/Atyrau',
  'Asia/Baghdad',
  'Asia/Baku',
  'Asia/Bangkok',
  'Asia/Barnaul',
  'Asia/Beirut',
  'Asia/Bishkek',
  'Asia/Brunei',
  'Asia/Chita',
  'Asia/Choibalsan',
  'Asia/Colombo',
  'Asia/Damascus',
  'Asia/Dhaka',
  'Asia/Dili',
  'Asia/Dubai',
  'Asia/Dushanbe',
  'Asia/Famagusta',
  'Asia/Gaza',
  'Asia/Hebron',
  'Asia/Ho_Chi_Minh',
  'Asia/Hong_Kong',
  'Asia/Hovd',
  'Asia/Irkutsk',
  'Asia/Jakarta',
  'Asia/Jayapura',
  'Asia/Jerusalem',
  'Asia/Kabul',
  'Asia/Kamchatka',
  'Asia/Karachi',
  'Asia/Kathmandu',
  'Asia/Khandyga',
  'Asia/Kolkata',
  'Asia/Krasnoyarsk',
  'Asia/Kuala_Lumpur',
  'Asia/Kuching',
  'Asia/Macau',
  'Asia/Magadan',
  'Asia/Makassar',
  'Asia/Manila',
  'Asia/Nicosia',
  'Asia/Novokuznetsk',
  'Asia/Novosibirsk',
  'Asia/Omsk',
  'Asia/Oral',
  'Asia/Pontianak',
  'Asia/Pyongyang',
  'Asia/Qatar',
  'Asia/Qostanay',
  'Asia/Qyzylorda',
  'Asia/Riyadh',
  'Asia/Sakhalin',
  'Asia/Samarkand',
  'Asia/Seoul',
  'Asia/Shanghai',
  'Asia/Srednekolymsk',
  'Asia/Taipei',
  'Asia/Tashkent',
  'Asia/Tbilisi',
  'Asia/Tehran',
  'Asia/Thimphu',
  'Asia/Tokyo',
  'Asia/Tomsk',
  'Asia/Ulaanbaatar',
  'Asia/Urumqi',
  'Asia/Ust-Nera',
  'Asia/Vladivostok',
  'Asia/Yakutsk',
  'Asia/Yekaterinburg',
  'Asia/Yerevan',
  'Atlantic/Azores',
  'Atlantic/Bermuda',
  'Atlantic/Canary',
  'Atlantic/Cape_Verde',
  'Atlantic/Faroe',
  'Atlantic/Madeira',
  'Atlantic/Reykjavik',
  'Atlantic/South_Georgia',
  'Atlantic/Stanley',
  'Australia/Adelaide',
  'Australia/Brisbane',
  'Australia/Broken_Hill',
  'Australia/Darwin',
  'Australia/Eucla',
  'Australia/Hobart',
  'Australia/Lindeman',
  'Australia/Lord_Howe',
  'Australia/Melbourne',
  'Australia/Perth',
  'Australia/Sydney',
  'Europe/Amsterdam',
  'Europe/Andorra',
  'Europe/Astrakhan',
  'Europe/Athens',
  'Europe/Belgrade',
  'Europe/Berlin',
  'Europe/Brussels',
  'Europe/Bucharest',
  'Europe/Budapest',
  'Europe/Chisinau',
  'Europe/Copenhagen',
  'Europe/Dublin',
  'Europe/Gibraltar',
  'Europe/Helsinki',
  'Europe/Istanbul',
  'Europe/Kaliningrad',
  'Europe/Kiev',
  'Europe/Kirov',
  'Europe/Lisbon',
  'Europe/London',
  'Europe/Luxembourg',
  'Europe/Madrid',
  'Europe/Malta',
  'Europe/Minsk',
  'Europe/Monaco',
  'Europe/Moscow',
  'Europe/Oslo',
  'Europe/Paris',
  'Europe/Prague',
  'Europe/Riga',
  'Europe/Rome',
  'Europe/Samara',
  'Europe/Saratov',
  'Europe/Simferopol',
  'Europe/Sofia',
  'Europe/Stockholm',
  'Europe/Tallinn',
  'Europe/Tirane',
  'Europe/Ulyanovsk',
  'Europe/Uzhgorod',
  'Europe/Vienna',
  'Europe/Vilnius',
  'Europe/Volgograd',
  'Europe/Warsaw',
  'Europe/Zaporozhye',
  'Europe/Zurich',
  'Indian/Chagos',
  'Indian/Christmas',
  'Indian/Cocos',
  'Indian/Kerguelen',
  'Indian/Mahe',
  'Indian/Maldives',
  'Indian/Mauritius',
  'Indian/Reunion',
  'Pacific/Apia',
  'Pacific/Auckland',
  'Pacific/Bougainville',
  'Pacific/Chatham',
  'Pacific/Chuuk',
  'Pacific/Easter',
  'Pacific/Efate',
  'Pacific/Fakaofo',
  'Pacific/Fiji',
  'Pacific/Galapagos',
  'Pacific/Gambier',
  'Pacific/Guadalcanal',
  'Pacific/Guam',
  'Pacific/Honolulu',
  'Pacific/Kiritimati',
  'Pacific/Kosrae',
  'Pacific/Kwajalein',
  'Pacific/Majuro',
  'Pacific/Marquesas',
  'Pacific/Nauru',
  'Pacific/Niue',
  'Pacific/Norfolk',
  'Pacific/Noumea',
  'Pacific/Pago_Pago',
  'Pacific/Palau',
  'Pacific/Pitcairn',
  'Pacific/Pohnpei',
  'Pacific/Port_Moresby',
  'Pacific/Rarotonga',
  'Pacific/Tahiti',
  'Pacific/Tarawa',
  'Pacific/Tongatapu',
  'UTC',
];
