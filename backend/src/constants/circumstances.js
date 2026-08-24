// Mirrors `mobile/lib/models/circumstances.dart` `kCircumstances` verbatim —
// same order, same wording — so the PDF's circumstances grid (§5.6) prints
// the exact same 17 labels the app's own circumstances screen showed the
// driver when they checked the boxes. `PartyReportModel.circumstances` (§5.1)
// only stores indices into this list, on both sides.
const CIRCUMSTANCES = [
  "Nije se kretao / bio je parkiran ili zaustavljen",
  "Napuštao je parking mesto, vrata, ili privatni posed",
  "Ulazio je na parking mesto",
  "Ulazio je u kružni tok",
  "Udario je u zadnji deo vozila ispred, u istom smeru i traci",
  "Kretao se pravo, istom saobraćajnom trakom",
  "Menjao je saobraćajnu traku",
  "Preticao je drugo vozilo",
  "Skretao je desno",
  "Skretao je levo",
  "Vozio je unazad",
  "Zadirao je u deo puta namenjen za suprotni smer",
  "Dolazio je sa desne strane (raskrsnica)",
  "Nije poštovao znak koji reguliše prvenstvo prolaza",
  "Nije poštovao crveno svetlo na semaforu",
  "Nije primetio drugo vozilo (nepažnja)",
  "Izlazio je sa kružnog toka",
];

module.exports = { CIRCUMSTANCES };
