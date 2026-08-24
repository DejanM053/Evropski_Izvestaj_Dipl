/// Realistic placeholder data for the "fill with sample data" buttons on
/// the Accident details and My details steps — added so the two-device
/// demo/test flow doesn't require retyping the same two dozen fields every
/// run. The one fixed requirement: party A's driver is always "Dejan
/// Mihajlović" and party B's is "Mihajlo Dejanović"; everything else here
/// is plausible filler.
library;

class SampleAccidentData {
  SampleAccidentData._();

  static const address = 'Bulevar kralja Aleksandra 73, Beograd';
  static const lat = 44.8125;
  static const lng = 20.4612;
  static const witnessName = 'Ana Petrović';
  static const witnessPhone = '+381 60 222 3344';

  /// Today's date at a fixed sample time, so repeated fills stay stable
  /// within a single day instead of drifting by seconds each tap.
  static DateTime dateTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 14, 30);
  }
}

class SamplePartyData {
  const SamplePartyData({
    required this.firstName,
    required this.lastName,
    required this.address,
    required this.phone,
    required this.email,
    required this.licenceNumber,
    required this.licenceCategory,
    required this.licenceValidUntil,
    required this.make,
    required this.model,
    required this.plate,
    required this.country,
    required this.vin,
    required this.insurerCompany,
    required this.policyNumber,
    required this.greenCardNumber,
    required this.insurerValidFrom,
    required this.insurerValidTo,
    required this.agency,
    required this.visibleDamage,
    required this.remarks,
  });

  final String firstName;
  final String lastName;
  final String address;
  final String phone;
  final String email;
  final String licenceNumber;
  final String licenceCategory;
  final DateTime licenceValidUntil;
  final String make;
  final String model;
  final String plate;
  final String country;
  final String vin;
  final String insurerCompany;
  final String policyNumber;
  final String greenCardNumber;
  final DateTime insurerValidFrom;
  final DateTime insurerValidTo;
  final String agency;
  final String visibleDamage;
  final String remarks;

  static final a = SamplePartyData(
    firstName: 'Dejan',
    lastName: 'Mihajlović',
    address: 'Bulevar kralja Aleksandra 73, Beograd',
    phone: '+381 63 123 4567',
    email: 'dejan.mihajlovic@example.com',
    licenceNumber: '041-8827',
    licenceCategory: 'B',
    licenceValidUntil: DateTime(2031, 3, 12),
    make: 'Škoda',
    model: 'Octavia',
    plate: 'BG 482-ŽD',
    country: 'SRB',
    vin: 'TMBJJ7NE7K0123456',
    insurerCompany: 'Dunav osiguranje a.d.o.',
    policyNumber: 'AO-2026-114-773902',
    greenCardNumber: 'GC-2026-001122',
    insurerValidFrom: DateTime(2026, 1, 1),
    insurerValidTo: DateTime(2027, 1, 1),
    agency: 'Filijala Beograd centar',
    visibleDamage: 'Ulubljen prednji branik i polomljen far',
    remarks: 'Vozilo se kretalo pravo kada je došlo do sudara.',
  );

  static final b = SamplePartyData(
    firstName: 'Mihajlo',
    lastName: 'Dejanović',
    address: 'Zmaj Jovina 15, Novi Sad',
    phone: '+381 64 987 6543',
    email: 'mihajlo.dejanovic@example.com',
    licenceNumber: '118-3391',
    licenceCategory: 'B',
    licenceValidUntil: DateTime(2029, 11, 2),
    make: 'Volkswagen',
    model: 'Golf',
    plate: 'NS 118-KM',
    country: 'SRB',
    vin: 'WVWZZZ1KZAW123456',
    insurerCompany: 'Triglav osiguranje a.d.o.',
    policyNumber: 'AO-2026-098-441207',
    greenCardNumber: 'GC-2026-005566',
    insurerValidFrom: DateTime(2026, 2, 15),
    insurerValidTo: DateTime(2027, 2, 15),
    agency: 'Filijala Novi Sad',
    visibleDamage: 'Ogrebotina i udubljenje na zadnjem braniku',
    remarks: 'Vozač A je iznenada promenio traku.',
  );

  static SamplePartyData forParty(String party) => party == 'A' ? a : b;
}
