import 'package:fladder/models/items/item_shared_models.dart';

/// Parses a TMDB person numeric id from Jellyfin virtual ids or plain numeric strings.
int? oxTmdbPersonIdFromRawId(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  for (final prefix in const ['tmdb-person-', 'tmdb-']) {
    if (s.startsWith(prefix)) {
      return int.tryParse(s.substring(prefix.length));
    }
  }
  return int.tryParse(s);
}

bool oxPersonHasNavigableTmdbId(String personId) {
  final id = oxTmdbPersonIdFromRawId(personId);
  return id != null && id > 0;
}

/// Canonical Jellyfin virtual person id used by oxplayer-be.
String oxCanonicalTmdbPersonItemId(int tmdbPersonId) => 'tmdb-person-$tmdbPersonId';

Person oxPersonWithCanonicalId(Person person) {
  final tmdbId = oxTmdbPersonIdFromRawId(person.id);
  if (tmdbId == null || tmdbId <= 0) return person;
  final canonicalId = oxCanonicalTmdbPersonItemId(tmdbId);
  if (person.id == canonicalId) return person;
  return Person(
    id: canonicalId,
    name: person.name,
    image: person.image,
    role: person.role,
    type: person.type,
  );
}
