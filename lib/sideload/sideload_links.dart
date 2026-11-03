/// Where a sideloaded install looks for and sends people to updates. The source is AltStore's format, which
/// SideStore, AltStore and Feather read; GitHub's latest-release address keeps it at one place across releases.
const sourceUrl = 'https://github.com/KaiC5504/BiliFast/releases/latest/download/source.json';

const releasesPage = 'https://github.com/KaiC5504/BiliFast/releases/latest';

/// GitHub's API for the newest release; asked at most once per launch and once per 检查更新 tap.
const latestReleaseApi = 'https://api.github.com/repos/KaiC5504/BiliFast/releases/latest';

/// The signers' own add-source links, as their Info.plist schemes and other projects' buttons use them.
final sideStoreAddSource = Uri.parse('sidestore://source?url=${Uri.encodeComponent(sourceUrl)}');
final altStoreAddSource = Uri.parse('altstore://source?url=${Uri.encodeComponent(sourceUrl)}');
final featherAddSource = Uri.parse('feather://source/$sourceUrl');

final sideStoreOpen = Uri.parse('sidestore://');
