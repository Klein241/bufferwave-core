/// ════════════════════════════════════════════════════════════════
/// BufferWave Core — 122 Cloudflare PoP Nodes (Offline Fallback)
///
/// Works even 100% offline. Based on real Cloudflare data center locations.
/// ════════════════════════════════════════════════════════════════
class CloudflareNodes {
  static const Map<String, Map<String, String>> nodes = {
    // ═══ AFRIQUE (15) ═══
    'cf-douala':       {'country': 'CM', 'city': 'Douala',        'region': 'Africa'},
    'cf-yaounde':      {'country': 'CM', 'city': 'Yaoundé',      'region': 'Africa'},
    'cf-abidjan':      {'country': 'CI', 'city': 'Abidjan',      'region': 'Africa'},
    'cf-dakar':        {'country': 'SN', 'city': 'Dakar',        'region': 'Africa'},
    'cf-kinshasa':     {'country': 'CD', 'city': 'Kinshasa',     'region': 'Africa'},
    'cf-libreville':   {'country': 'GA', 'city': 'Libreville',   'region': 'Africa'},
    'cf-lagos':        {'country': 'NG', 'city': 'Lagos',        'region': 'Africa'},
    'cf-johannesburg': {'country': 'ZA', 'city': 'Johannesburg', 'region': 'Africa'},
    'cf-capetown':     {'country': 'ZA', 'city': 'Le Cap',       'region': 'Africa'},
    'cf-nairobi':      {'country': 'KE', 'city': 'Nairobi',      'region': 'Africa'},
    'cf-accra':        {'country': 'GH', 'city': 'Accra',        'region': 'Africa'},
    'cf-addisababa':   {'country': 'ET', 'city': 'Addis-Abeba',  'region': 'Africa'},
    'cf-casablanca':   {'country': 'MA', 'city': 'Casablanca',   'region': 'Africa'},
    'cf-tunis':        {'country': 'TN', 'city': 'Tunis',        'region': 'Africa'},
    'cf-maputo':       {'country': 'MZ', 'city': 'Maputo',       'region': 'Africa'},
    // ═══ EUROPE (35) ═══
    'cf-paris':        {'country': 'FR', 'city': 'Paris',        'region': 'Europe'},
    'cf-marseille':    {'country': 'FR', 'city': 'Marseille',    'region': 'Europe'},
    'cf-lyon':         {'country': 'FR', 'city': 'Lyon',         'region': 'Europe'},
    'cf-london':       {'country': 'GB', 'city': 'London',       'region': 'Europe'},
    'cf-manchester':   {'country': 'GB', 'city': 'Manchester',   'region': 'Europe'},
    'cf-edinburgh':    {'country': 'GB', 'city': 'Edinburgh',    'region': 'Europe'},
    'cf-amsterdam':    {'country': 'NL', 'city': 'Amsterdam',    'region': 'Europe'},
    'cf-frankfurt':    {'country': 'DE', 'city': 'Frankfurt',    'region': 'Europe'},
    'cf-berlin':       {'country': 'DE', 'city': 'Berlin',       'region': 'Europe'},
    'cf-munich':       {'country': 'DE', 'city': 'Munich',       'region': 'Europe'},
    'cf-hamburg':      {'country': 'DE', 'city': 'Hambourg',     'region': 'Europe'},
    'cf-dusseldorf':   {'country': 'DE', 'city': 'Düsseldorf',   'region': 'Europe'},
    'cf-bruxelles':    {'country': 'BE', 'city': 'Bruxelles',    'region': 'Europe'},
    'cf-zurich':       {'country': 'CH', 'city': 'Zürich',       'region': 'Europe'},
    'cf-geneve':       {'country': 'CH', 'city': 'Genève',       'region': 'Europe'},
    'cf-madrid':       {'country': 'ES', 'city': 'Madrid',       'region': 'Europe'},
    'cf-barcelona':    {'country': 'ES', 'city': 'Barcelona',    'region': 'Europe'},
    'cf-milan':        {'country': 'IT', 'city': 'Milan',        'region': 'Europe'},
    'cf-rome':         {'country': 'IT', 'city': 'Rome',         'region': 'Europe'},
    'cf-vienna':       {'country': 'AT', 'city': 'Vienne',       'region': 'Europe'},
    'cf-prague':       {'country': 'CZ', 'city': 'Prague',       'region': 'Europe'},
    'cf-warsaw':       {'country': 'PL', 'city': 'Varsovie',     'region': 'Europe'},
    'cf-budapest':     {'country': 'HU', 'city': 'Budapest',     'region': 'Europe'},
    'cf-bucharest':    {'country': 'RO', 'city': 'Bucarest',     'region': 'Europe'},
    'cf-sofia':        {'country': 'BG', 'city': 'Sofia',        'region': 'Europe'},
    'cf-stockholm':    {'country': 'SE', 'city': 'Stockholm',    'region': 'Europe'},
    'cf-oslo':         {'country': 'NO', 'city': 'Oslo',         'region': 'Europe'},
    'cf-copenhagen':   {'country': 'DK', 'city': 'Copenhague',   'region': 'Europe'},
    'cf-helsinki':     {'country': 'FI', 'city': 'Helsinki',     'region': 'Europe'},
    'cf-dublin':       {'country': 'IE', 'city': 'Dublin',       'region': 'Europe'},
    'cf-lisbon':       {'country': 'PT', 'city': 'Lisbonne',     'region': 'Europe'},
    'cf-athens':       {'country': 'GR', 'city': 'Athènes',     'region': 'Europe'},
    'cf-istanbul':     {'country': 'TR', 'city': 'Istanbul',     'region': 'Europe'},
    'cf-kiev':         {'country': 'UA', 'city': 'Kiev',         'region': 'Europe'},
    'cf-luxembourg':   {'country': 'LU', 'city': 'Luxembourg',   'region': 'Europe'},
    // ═══ ASIE (30) ═══
    'cf-tokyo':        {'country': 'JP', 'city': 'Tokyo',        'region': 'Asia'},
    'cf-osaka':        {'country': 'JP', 'city': 'Osaka',        'region': 'Asia'},
    'cf-singapore':    {'country': 'SG', 'city': 'Singapore',    'region': 'Asia'},
    'cf-hongkong':     {'country': 'HK', 'city': 'Hong Kong',    'region': 'Asia'},
    'cf-seoul':        {'country': 'KR', 'city': 'Séoul',        'region': 'Asia'},
    'cf-taipei':       {'country': 'TW', 'city': 'Taipei',       'region': 'Asia'},
    'cf-mumbai':       {'country': 'IN', 'city': 'Mumbai',       'region': 'Asia'},
    'cf-delhi':        {'country': 'IN', 'city': 'New Delhi',    'region': 'Asia'},
    'cf-chennai':      {'country': 'IN', 'city': 'Chennai',      'region': 'Asia'},
    'cf-bangalore':    {'country': 'IN', 'city': 'Bangalore',    'region': 'Asia'},
    'cf-kolkata':      {'country': 'IN', 'city': 'Kolkata',      'region': 'Asia'},
    'cf-bangkok':      {'country': 'TH', 'city': 'Bangkok',      'region': 'Asia'},
    'cf-jakarta':      {'country': 'ID', 'city': 'Jakarta',      'region': 'Asia'},
    'cf-kualalumpur':  {'country': 'MY', 'city': 'Kuala Lumpur', 'region': 'Asia'},
    'cf-manila':       {'country': 'PH', 'city': 'Manille',      'region': 'Asia'},
    'cf-hanoi':        {'country': 'VN', 'city': 'Hanoï',        'region': 'Asia'},
    'cf-dhaka':        {'country': 'BD', 'city': 'Dhaka',        'region': 'Asia'},
    'cf-karachi':      {'country': 'PK', 'city': 'Karachi',      'region': 'Asia'},
    'cf-lahore':       {'country': 'PK', 'city': 'Lahore',       'region': 'Asia'},
    'cf-colombo':      {'country': 'LK', 'city': 'Colombo',      'region': 'Asia'},
    'cf-kathmandu':    {'country': 'NP', 'city': 'Katmandou',    'region': 'Asia'},
    'cf-tashkent':     {'country': 'UZ', 'city': 'Tachkent',     'region': 'Asia'},
    'cf-almaty':       {'country': 'KZ', 'city': 'Almaty',       'region': 'Asia'},
    'cf-tbilisi':      {'country': 'GE', 'city': 'Tbilissi',     'region': 'Asia'},
    'cf-yerevan':      {'country': 'AM', 'city': 'Erevan',       'region': 'Asia'},
    'cf-baku':         {'country': 'AZ', 'city': 'Bakou',        'region': 'Asia'},
    'cf-beijing':      {'country': 'CN', 'city': 'Pékin',        'region': 'Asia'},
    'cf-shanghai':     {'country': 'CN', 'city': 'Shanghai',     'region': 'Asia'},
    'cf-guangzhou':    {'country': 'CN', 'city': 'Guangzhou',    'region': 'Asia'},
    'cf-ulaanbaatar':  {'country': 'MN', 'city': 'Oulan-Bator', 'region': 'Asia'},
    // ═══ AMÉRIQUES (25) ═══
    'cf-newyork':      {'country': 'US', 'city': 'New York',      'region': 'Americas'},
    'cf-losangeles':   {'country': 'US', 'city': 'Los Angeles',   'region': 'Americas'},
    'cf-chicago':      {'country': 'US', 'city': 'Chicago',       'region': 'Americas'},
    'cf-dallas':       {'country': 'US', 'city': 'Dallas',        'region': 'Americas'},
    'cf-miami':        {'country': 'US', 'city': 'Miami',         'region': 'Americas'},
    'cf-seattle':      {'country': 'US', 'city': 'Seattle',       'region': 'Americas'},
    'cf-sanfrancisco': {'country': 'US', 'city': 'San Francisco', 'region': 'Americas'},
    'cf-washington':   {'country': 'US', 'city': 'Washington DC', 'region': 'Americas'},
    'cf-atlanta':      {'country': 'US', 'city': 'Atlanta',       'region': 'Americas'},
    'cf-denver':       {'country': 'US', 'city': 'Denver',        'region': 'Americas'},
    'cf-phoenix':      {'country': 'US', 'city': 'Phoenix',       'region': 'Americas'},
    'cf-boston':        {'country': 'US', 'city': 'Boston',        'region': 'Americas'},
    'cf-toronto':      {'country': 'CA', 'city': 'Toronto',       'region': 'Americas'},
    'cf-vancouver':    {'country': 'CA', 'city': 'Vancouver',     'region': 'Americas'},
    'cf-montreal':     {'country': 'CA', 'city': 'Montréal',      'region': 'Americas'},
    'cf-mexicocity':   {'country': 'MX', 'city': 'Mexico City',   'region': 'Americas'},
    'cf-guadalajara':  {'country': 'MX', 'city': 'Guadalajara',   'region': 'Americas'},
    'cf-saopaulo':     {'country': 'BR', 'city': 'São Paulo',     'region': 'Americas'},
    'cf-riodejaneiro': {'country': 'BR', 'city': 'Rio de Janeiro', 'region': 'Americas'},
    'cf-buenosaires':  {'country': 'AR', 'city': 'Buenos Aires',  'region': 'Americas'},
    'cf-santiago':     {'country': 'CL', 'city': 'Santiago',      'region': 'Americas'},
    'cf-bogota':       {'country': 'CO', 'city': 'Bogotá',        'region': 'Americas'},
    'cf-lima':         {'country': 'PE', 'city': 'Lima',          'region': 'Americas'},
    'cf-quito':        {'country': 'EC', 'city': 'Quito',         'region': 'Americas'},
    'cf-panama':       {'country': 'PA', 'city': 'Panama City',   'region': 'Americas'},
    // ═══ MOYEN-ORIENT (10) ═══
    'cf-dubai':        {'country': 'AE', 'city': 'Dubai',         'region': 'MiddleEast'},
    'cf-abudhabi':     {'country': 'AE', 'city': 'Abu Dhabi',     'region': 'MiddleEast'},
    'cf-doha':         {'country': 'QA', 'city': 'Doha',          'region': 'MiddleEast'},
    'cf-riyadh':       {'country': 'SA', 'city': 'Riyad',         'region': 'MiddleEast'},
    'cf-jeddah':       {'country': 'SA', 'city': 'Djeddah',       'region': 'MiddleEast'},
    'cf-muscat':       {'country': 'OM', 'city': 'Mascate',       'region': 'MiddleEast'},
    'cf-kuwait':       {'country': 'KW', 'city': 'Koweït',        'region': 'MiddleEast'},
    'cf-manama':       {'country': 'BH', 'city': 'Manama',        'region': 'MiddleEast'},
    'cf-telaviv':      {'country': 'IL', 'city': 'Tel Aviv',      'region': 'MiddleEast'},
    'cf-amman':        {'country': 'JO', 'city': 'Amman',         'region': 'MiddleEast'},
    // ═══ OCÉANIE (7) ═══
    'cf-sydney':       {'country': 'AU', 'city': 'Sydney',        'region': 'Oceania'},
    'cf-melbourne':    {'country': 'AU', 'city': 'Melbourne',     'region': 'Oceania'},
    'cf-perth':        {'country': 'AU', 'city': 'Perth',         'region': 'Oceania'},
    'cf-brisbane':     {'country': 'AU', 'city': 'Brisbane',      'region': 'Oceania'},
    'cf-auckland':     {'country': 'NZ', 'city': 'Auckland',      'region': 'Oceania'},
    'cf-wellington':   {'country': 'NZ', 'city': 'Wellington',    'region': 'Oceania'},
    'cf-noumea':       {'country': 'NC', 'city': 'Nouméa',        'region': 'Oceania'},
  };

  /// Get fallback list (works offline)
  static List<Map<String, dynamic>> fallbackList() {
    return nodes.entries.map((e) {
      return <String, dynamic>{
        'id': e.key,
        'country': e.value['country']!,
        'city': e.value['city']!,
        'region': e.value['region']!,
        'bandwidthMbps': 1000,
        'online': true,
        'hasWebSocket': true,
        'type': 'cloudflare',
      };
    }).toList();
  }

  /// Get nodes by region
  static List<Map<String, dynamic>> byRegion(String region) {
    return fallbackList().where((n) => n['region'] == region).toList();
  }

  /// Get nodes by country code
  static List<Map<String, dynamic>> byCountry(String countryCode) {
    return fallbackList().where((n) => n['country'] == countryCode).toList();
  }

  /// Total node count
  static int get totalCount => nodes.length;
}
