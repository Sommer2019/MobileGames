/// Continents that can be blocked as a whole.
const Map<String, String> continents = {
  'EU': 'Europa',
  'AS': 'Asien',
  'AF': 'Afrika',
  'NA': 'Nordamerika',
  'SA': 'Südamerika',
  'OC': 'Ozeanien',
  'AN': 'Antarktis',
};

/// A country (or territory) as reverse geocoding names it.
class Country {
  const Country(this.code, this.continent, this.name);

  /// ISO 3166-1 alpha-2, lower case (as OpenStreetMap returns it).
  final String code;
  final String continent;
  final String name;
}

/// "code continent name", one per line.
const _table = '''
ad EU Andorra
ae AS Vereinigte Arabische Emirate
af AS Afghanistan
ag NA Antigua und Barbuda
al EU Albanien
am AS Armenien
ao AF Angola
aq AN Antarktis
ar SA Argentinien
as OC Amerikanisch-Samoa
at EU Österreich
au OC Australien
aw NA Aruba
ax EU Åland
az AS Aserbaidschan
ba EU Bosnien und Herzegowina
bb NA Barbados
bd AS Bangladesch
be EU Belgien
bf AF Burkina Faso
bg EU Bulgarien
bh AS Bahrain
bi AF Burundi
bj AF Benin
bm NA Bermuda
bn AS Brunei
bo SA Bolivien
br SA Brasilien
bs NA Bahamas
bt AS Bhutan
bw AF Botswana
by EU Belarus
bz NA Belize
ca NA Kanada
cd AF Kongo (Dem. Rep.)
cf AF Zentralafrikanische Republik
cg AF Kongo
ch EU Schweiz
ci AF Elfenbeinküste
cl SA Chile
cm AF Kamerun
cn AS China
co SA Kolumbien
cr NA Costa Rica
cu NA Kuba
cv AF Kap Verde
cw NA Curaçao
cy EU Zypern
cz EU Tschechien
de EU Deutschland
dj AF Dschibuti
dk EU Dänemark
dm NA Dominica
do NA Dominikanische Republik
dz AF Algerien
ec SA Ecuador
ee EU Estland
eg AF Ägypten
er AF Eritrea
es EU Spanien
et AF Äthiopien
fi EU Finnland
fj OC Fidschi
fk SA Falklandinseln
fm OC Mikronesien
fo EU Färöer
fr EU Frankreich
ga AF Gabun
gb EU Vereinigtes Königreich
gd NA Grenada
ge AS Georgien
gf SA Französisch-Guayana
gg EU Guernsey
gh AF Ghana
gi EU Gibraltar
gl NA Grönland
gm AF Gambia
gn AF Guinea
gp NA Guadeloupe
gq AF Äquatorialguinea
gr EU Griechenland
gt NA Guatemala
gu OC Guam
gw AF Guinea-Bissau
gy SA Guyana
hk AS Hongkong
hn NA Honduras
hr EU Kroatien
ht NA Haiti
hu EU Ungarn
id AS Indonesien
ie EU Irland
il AS Israel
im EU Isle of Man
in AS Indien
iq AS Irak
ir AS Iran
is EU Island
it EU Italien
je EU Jersey
jm NA Jamaika
jo AS Jordanien
jp AS Japan
ke AF Kenia
kg AS Kirgisistan
kh AS Kambodscha
ki OC Kiribati
km AF Komoren
kn NA St. Kitts und Nevis
kp AS Nordkorea
kr AS Südkorea
kw AS Kuwait
ky NA Kaimaninseln
kz AS Kasachstan
la AS Laos
lb AS Libanon
lc NA St. Lucia
li EU Liechtenstein
lk AS Sri Lanka
lr AF Liberia
ls AF Lesotho
lt EU Litauen
lu EU Luxemburg
lv EU Lettland
ly AF Libyen
ma AF Marokko
mc EU Monaco
md EU Moldau
me EU Montenegro
mg AF Madagaskar
mh OC Marshallinseln
mk EU Nordmazedonien
ml AF Mali
mm AS Myanmar
mn AS Mongolei
mo AS Macau
mp OC Nördliche Marianen
mq NA Martinique
mr AF Mauretanien
mt EU Malta
mu AF Mauritius
mv AS Malediven
mw AF Malawi
mx NA Mexiko
my AS Malaysia
mz AF Mosambik
na AF Namibia
nc OC Neukaledonien
ne AF Niger
ng AF Nigeria
ni NA Nicaragua
nl EU Niederlande
no EU Norwegen
np AS Nepal
nr OC Nauru
nz OC Neuseeland
om AS Oman
pa NA Panama
pe SA Peru
pf OC Französisch-Polynesien
pg OC Papua-Neuguinea
ph AS Philippinen
pk AS Pakistan
pl EU Polen
pr NA Puerto Rico
ps AS Palästina
pt EU Portugal
pw OC Palau
py SA Paraguay
qa AS Katar
re AF Réunion
ro EU Rumänien
rs EU Serbien
ru EU Russland
rw AF Ruanda
sa AS Saudi-Arabien
sb OC Salomonen
sc AF Seychellen
sd AF Sudan
se EU Schweden
sg AS Singapur
si EU Slowenien
sj EU Spitzbergen
sk EU Slowakei
sl AF Sierra Leone
sm EU San Marino
sn AF Senegal
so AF Somalia
sr SA Suriname
ss AF Südsudan
st AF São Tomé und Príncipe
sv NA El Salvador
sx NA Sint Maarten
sy AS Syrien
sz AF Eswatini
tc NA Turks- und Caicosinseln
td AF Tschad
tg AF Togo
th AS Thailand
tj AS Tadschikistan
tl AS Osttimor
tm AS Turkmenistan
tn AF Tunesien
to OC Tonga
tr AS Türkei
tt NA Trinidad und Tobago
tv OC Tuvalu
tw AS Taiwan
tz AF Tansania
ua EU Ukraine
ug AF Uganda
us NA Vereinigte Staaten
uy SA Uruguay
uz AS Usbekistan
va EU Vatikanstadt
vc NA St. Vincent und die Grenadinen
ve SA Venezuela
vg NA Britische Jungferninseln
vi NA Amerikanische Jungferninseln
vn AS Vietnam
vu OC Vanuatu
ws OC Samoa
xk EU Kosovo
ye AS Jemen
yt AF Mayotte
za AF Südafrika
zm AF Sambia
zw AF Simbabwe''';

/// All countries, sorted by their German name.
final List<Country> countries = () {
  final list = [
    for (final line in _table.split('\n'))
      if (line.trim().isNotEmpty)
        Country(line.substring(0, 2), line.substring(3, 5), line.substring(6)),
  ];
  list.sort((a, b) => a.name.compareTo(b.name));
  return list;
}();

final Map<String, Country> countryByCode = {
  for (final c in countries) c.code: c,
};

/// Whether a place in country [code] (lower case, '' if unknown) is blocked
/// by [blocked] (country codes, and `c:XX` for whole continents).
bool isBlocked(String code, Iterable<String> blocked) {
  if (code.isEmpty) return false;
  final set = blocked.toSet();
  if (set.contains(code)) return true;
  final c = countryByCode[code];
  return c != null && set.contains('c:${c.continent}');
}

/// Short text for the blocked regions, e.g. "Asien, Frankreich".
String blockedLabel(Iterable<String> blocked) {
  final names = [
    for (final b in blocked)
      b.startsWith('c:')
          ? continents[b.substring(2)] ?? b
          : countryByCode[b]?.name ?? b.toUpperCase(),
  ];
  return names.isEmpty ? 'keine' : names.join(', ');
}
