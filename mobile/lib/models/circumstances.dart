/// The 17 standard boxes of the European Accident Statement's "circumstances"
/// grid (docs/master_plan.md §5.1 `PartyReportModel.circumstances`, a list
/// of checked indices into this array). Not present verbatim in the design
/// source (screen "1f" mocks only a handful of example labels plus a
/// "Prikaži još 11 okolnosti" — 6 shown + 11 more = 17 total, which is what
/// this list reproduces), so the exact wording here is drawn from the
/// standard statement rather than the mockup's placeholder copy.
///
/// Index 0-5 are shown by default; `CircumstancesStep` reveals 6-16 behind
/// the "show more" affordance, matching the design's 6-then-expand layout.
const List<String> kCircumstances = [
  'Nije se kretao / bio je parkiran ili zaustavljen',
  'Napuštao je parking mesto, vrata, ili privatni posed',
  'Ulazio je na parking mesto',
  'Ulazio je u kružni tok',
  'Udario je u zadnji deo vozila ispred, u istom smeru i traci',
  'Kretao se pravo, istom saobraćajnom trakom',
  'Menjao je saobraćajnu traku',
  'Preticao je drugo vozilo',
  'Skretao je desno',
  'Skretao je levo',
  'Vozio je unazad',
  'Zadirao je u deo puta namenjen za suprotni smer',
  'Dolazio je sa desne strane (raskrsnica)',
  'Nije poštovao znak koji reguliše prvenstvo prolaza',
  'Nije poštovao crveno svetlo na semaforu',
  'Nije primetio drugo vozilo (nepažnja)',
  'Izlazio je sa kružnog toka',
];
