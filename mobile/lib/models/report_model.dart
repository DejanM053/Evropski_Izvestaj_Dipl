/// Dart mirrors of the backend `Report` document and its embedded
/// sub-schemas (docs/master_plan.md §5.1, `backend/src/models/Report.js`).
///
/// Phase 6 only needs `sessionId`/`status` off this model (for the session
/// shell); the rest of the tree is mirrored now, fromJson/toJson included,
/// so Phases 7+ can start patching/reading real fields immediately instead
/// of re-deriving the schema. No validation lives here — that belongs to
/// the form screens that produce these values.
library;

class LocationModel {
  const LocationModel({this.address, this.lat, this.lng});

  final String? address;
  final double? lat;
  final double? lng;

  factory LocationModel.fromJson(Map<String, dynamic> json) => LocationModel(
        address: json['address'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {'address': address, 'lat': lat, 'lng': lng};
}

class WitnessModel {
  const WitnessModel({this.name, this.phone});

  final String? name;
  final String? phone;

  factory WitnessModel.fromJson(Map<String, dynamic> json) =>
      WitnessModel(name: json['name'] as String?, phone: json['phone'] as String?);

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone};
}

class AccidentModel {
  const AccidentModel({
    this.dateTime,
    this.location = const LocationModel(),
    this.injuries = false,
    this.otherVehicleDamage = false,
    this.thirdPartyDamage = false,
    this.witnesses = const [],
  });

  final DateTime? dateTime;
  final LocationModel location;
  final bool injuries;
  final bool otherVehicleDamage;
  final bool thirdPartyDamage;
  final List<WitnessModel> witnesses;

  factory AccidentModel.fromJson(Map<String, dynamic> json) => AccidentModel(
        dateTime: json['dateTime'] == null ? null : DateTime.parse(json['dateTime'] as String),
        location: json['location'] == null
            ? const LocationModel()
            : LocationModel.fromJson((json['location'] as Map).cast<String, dynamic>()),
        injuries: json['injuries'] as bool? ?? false,
        otherVehicleDamage: json['otherVehicleDamage'] as bool? ?? false,
        thirdPartyDamage: json['thirdPartyDamage'] as bool? ?? false,
        witnesses: (json['witnesses'] as List<dynamic>? ?? const [])
            .map((w) => WitnessModel.fromJson((w as Map).cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'dateTime': dateTime?.toIso8601String(),
        'location': location.toJson(),
        'injuries': injuries,
        'otherVehicleDamage': otherVehicleDamage,
        'thirdPartyDamage': thirdPartyDamage,
        'witnesses': witnesses.map((w) => w.toJson()).toList(),
      };
}

class DriverModel {
  const DriverModel({
    this.firstName,
    this.lastName,
    this.address,
    this.phone,
    this.email,
    this.licenceNumber,
    this.licenceCategory,
    this.licenceValidUntil,
  });

  final String? firstName;
  final String? lastName;
  final String? address;
  final String? phone;
  final String? email;
  final String? licenceNumber;
  final String? licenceCategory;
  final DateTime? licenceValidUntil;

  factory DriverModel.fromJson(Map<String, dynamic> json) => DriverModel(
        firstName: json['firstName'] as String?,
        lastName: json['lastName'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        licenceNumber: json['licenceNumber'] as String?,
        licenceCategory: json['licenceCategory'] as String?,
        licenceValidUntil:
            json['licenceValidUntil'] == null ? null : DateTime.parse(json['licenceValidUntil'] as String),
      );

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'address': address,
        'phone': phone,
        'email': email,
        'licenceNumber': licenceNumber,
        'licenceCategory': licenceCategory,
        'licenceValidUntil': licenceValidUntil?.toIso8601String(),
      };
}

class VehicleModel {
  const VehicleModel({this.make, this.model, this.plate, this.country, this.vin});

  final String? make;
  final String? model;
  final String? plate;
  final String? country;
  final String? vin;

  factory VehicleModel.fromJson(Map<String, dynamic> json) => VehicleModel(
        make: json['make'] as String?,
        model: json['model'] as String?,
        plate: json['plate'] as String?,
        country: json['country'] as String?,
        vin: json['vin'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        'plate': plate,
        'country': country,
        'vin': vin,
      };
}

class InsurerModel {
  const InsurerModel({
    this.company,
    this.policyNumber,
    this.greenCardNumber,
    this.validFrom,
    this.validTo,
    this.agency,
  });

  final String? company;
  final String? policyNumber;
  final String? greenCardNumber;
  final DateTime? validFrom;
  final DateTime? validTo;
  final String? agency;

  factory InsurerModel.fromJson(Map<String, dynamic> json) => InsurerModel(
        company: json['company'] as String?,
        policyNumber: json['policyNumber'] as String?,
        greenCardNumber: json['greenCardNumber'] as String?,
        validFrom: json['validFrom'] == null ? null : DateTime.parse(json['validFrom'] as String),
        validTo: json['validTo'] == null ? null : DateTime.parse(json['validTo'] as String),
        agency: json['agency'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'company': company,
        'policyNumber': policyNumber,
        'greenCardNumber': greenCardNumber,
        'validFrom': validFrom?.toIso8601String(),
        'validTo': validTo?.toIso8601String(),
        'agency': agency,
      };
}

class PolicyholderModel {
  const PolicyholderModel({this.name, this.address, this.phone});

  final String? name;
  final String? address;
  final String? phone;

  factory PolicyholderModel.fromJson(Map<String, dynamic> json) => PolicyholderModel(
        name: json['name'] as String?,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
      );

  Map<String, dynamic> toJson() => {'name': name, 'address': address, 'phone': phone};
}

class SignatureModel {
  const SignatureModel({this.fileId, this.signedAt});

  final String? fileId;
  final DateTime? signedAt;

  factory SignatureModel.fromJson(Map<String, dynamic> json) => SignatureModel(
        fileId: json['fileId'] as String?,
        signedAt: json['signedAt'] == null ? null : DateTime.parse(json['signedAt'] as String),
      );

  Map<String, dynamic> toJson() => {'fileId': fileId, 'signedAt': signedAt?.toIso8601String()};
}

class PartyReportModel {
  const PartyReportModel({
    this.driver = const DriverModel(),
    this.vehicle = const VehicleModel(),
    this.insurer = const InsurerModel(),
    this.policyholder = const PolicyholderModel(),
    this.circumstances = const [],
    this.visibleDamage = '',
    this.remarks = '',
    this.signature = const SignatureModel(),
    this.confirmedReview = false,
  });

  final DriverModel driver;
  final VehicleModel vehicle;
  final InsurerModel insurer;
  final PolicyholderModel policyholder;
  final List<int> circumstances;
  final String visibleDamage;
  final String remarks;
  final SignatureModel signature;
  final bool confirmedReview;

  factory PartyReportModel.fromJson(Map<String, dynamic> json) => PartyReportModel(
        driver: json['driver'] == null
            ? const DriverModel()
            : DriverModel.fromJson((json['driver'] as Map).cast<String, dynamic>()),
        vehicle: json['vehicle'] == null
            ? const VehicleModel()
            : VehicleModel.fromJson((json['vehicle'] as Map).cast<String, dynamic>()),
        insurer: json['insurer'] == null
            ? const InsurerModel()
            : InsurerModel.fromJson((json['insurer'] as Map).cast<String, dynamic>()),
        policyholder: json['policyholder'] == null
            ? const PolicyholderModel()
            : PolicyholderModel.fromJson((json['policyholder'] as Map).cast<String, dynamic>()),
        circumstances: (json['circumstances'] as List<dynamic>? ?? const []).map((e) => e as int).toList(),
        visibleDamage: json['visibleDamage'] as String? ?? '',
        remarks: json['remarks'] as String? ?? '',
        signature: json['signature'] == null
            ? const SignatureModel()
            : SignatureModel.fromJson((json['signature'] as Map).cast<String, dynamic>()),
        confirmedReview: json['confirmedReview'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'driver': driver.toJson(),
        'vehicle': vehicle.toJson(),
        'insurer': insurer.toJson(),
        'policyholder': policyholder.toJson(),
        'circumstances': circumstances,
        'visibleDamage': visibleDamage,
        'remarks': remarks,
        'signature': signature.toJson(),
        'confirmedReview': confirmedReview,
      };
}

class PhotoModel {
  const PhotoModel({required this.fileId, this.caption, this.party, this.takenAt});

  final String fileId;
  final String? caption;
  final String? party;
  final DateTime? takenAt;

  factory PhotoModel.fromJson(Map<String, dynamic> json) => PhotoModel(
        fileId: json['fileId'] as String,
        caption: json['caption'] as String?,
        party: json['party'] as String?,
        takenAt: json['takenAt'] == null ? null : DateTime.parse(json['takenAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'caption': caption,
        'party': party,
        'takenAt': takenAt?.toIso8601String(),
      };
}

class AttachmentHashModel {
  const AttachmentHashModel({required this.fileId, required this.sha256, required this.kind});

  final String fileId;
  final String sha256;
  final String kind;

  factory AttachmentHashModel.fromJson(Map<String, dynamic> json) => AttachmentHashModel(
        fileId: json['fileId'] as String,
        sha256: json['sha256'] as String,
        kind: json['kind'] as String,
      );

  Map<String, dynamic> toJson() => {'fileId': fileId, 'sha256': sha256, 'kind': kind};
}

class ChainModel {
  const ChainModel({this.txHash, this.blockNumber, this.contractAddress, this.network, this.anchoredAt});

  final String? txHash;
  final int? blockNumber;
  final String? contractAddress;
  final String? network;
  final DateTime? anchoredAt;

  factory ChainModel.fromJson(Map<String, dynamic> json) => ChainModel(
        txHash: json['txHash'] as String?,
        blockNumber: json['blockNumber'] as int?,
        contractAddress: json['contractAddress'] as String?,
        network: json['network'] as String?,
        anchoredAt: json['anchoredAt'] == null ? null : DateTime.parse(json['anchoredAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'txHash': txHash,
        'blockNumber': blockNumber,
        'contractAddress': contractAddress,
        'network': network,
        'anchoredAt': anchoredAt?.toIso8601String(),
      };
}

class ReportModel {
  const ReportModel({
    required this.id,
    this.sessionId,
    this.status = 'waiting',
    this.accident = const AccidentModel(),
    this.partyA = const PartyReportModel(),
    this.partyB = const PartyReportModel(),
    this.sketchFileId,
    this.photos = const [],
    this.pdfFileId,
    this.pdfSha256,
    this.pdfGeneratedAt,
    this.attachmentHashes = const [],
    this.bundleHash,
    this.chain = const ChainModel(),
    this.createdAt,
    this.sealedAt,
  });

  final String id;
  final String? sessionId;
  final String status;
  final AccidentModel accident;
  final PartyReportModel partyA;
  final PartyReportModel partyB;
  final String? sketchFileId;
  final List<PhotoModel> photos;
  final String? pdfFileId;
  final String? pdfSha256;
  final DateTime? pdfGeneratedAt;
  final List<AttachmentHashModel> attachmentHashes;
  final String? bundleHash;
  final ChainModel chain;
  final DateTime? createdAt;
  final DateTime? sealedAt;

  /// `'A'` or `'B'` -> that party's half of the report.
  PartyReportModel partyFor(String party) => party == 'A' ? partyA : partyB;

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final pdf = (json['pdf'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sketch = (json['sketch'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ReportModel(
      id: json['_id'] as String,
      sessionId: json['sessionId'] as String?,
      status: json['status'] as String? ?? 'waiting',
      accident: json['accident'] == null
          ? const AccidentModel()
          : AccidentModel.fromJson((json['accident'] as Map).cast<String, dynamic>()),
      partyA: json['partyA'] == null
          ? const PartyReportModel()
          : PartyReportModel.fromJson((json['partyA'] as Map).cast<String, dynamic>()),
      partyB: json['partyB'] == null
          ? const PartyReportModel()
          : PartyReportModel.fromJson((json['partyB'] as Map).cast<String, dynamic>()),
      sketchFileId: sketch['fileId'] as String?,
      photos: (json['photos'] as List<dynamic>? ?? const [])
          .map((p) => PhotoModel.fromJson((p as Map).cast<String, dynamic>()))
          .toList(),
      pdfFileId: pdf['fileId'] as String?,
      pdfSha256: pdf['sha256'] as String?,
      pdfGeneratedAt: pdf['generatedAt'] == null ? null : DateTime.parse(pdf['generatedAt'] as String),
      attachmentHashes: (json['attachmentHashes'] as List<dynamic>? ?? const [])
          .map((a) => AttachmentHashModel.fromJson((a as Map).cast<String, dynamic>()))
          .toList(),
      bundleHash: json['bundleHash'] as String?,
      chain: json['chain'] == null
          ? const ChainModel()
          : ChainModel.fromJson((json['chain'] as Map).cast<String, dynamic>()),
      createdAt: json['createdAt'] == null ? null : DateTime.parse(json['createdAt'] as String),
      sealedAt: json['sealedAt'] == null ? null : DateTime.parse(json['sealedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'sessionId': sessionId,
        'status': status,
        'accident': accident.toJson(),
        'partyA': partyA.toJson(),
        'partyB': partyB.toJson(),
        'sketch': {'fileId': sketchFileId},
        'photos': photos.map((p) => p.toJson()).toList(),
        'pdf': {'fileId': pdfFileId, 'sha256': pdfSha256, 'generatedAt': pdfGeneratedAt?.toIso8601String()},
        'attachmentHashes': attachmentHashes.map((a) => a.toJson()).toList(),
        'bundleHash': bundleHash,
        'chain': chain.toJson(),
        'createdAt': createdAt?.toIso8601String(),
        'sealedAt': sealedAt?.toIso8601String(),
      };
}
