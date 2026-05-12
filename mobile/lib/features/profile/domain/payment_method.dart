import 'package:equatable/equatable.dart';

/// A saved mobile money payer profile. Local-only for now.
class PaymentMethod extends Equatable {
  const PaymentMethod({
    required this.id,
    required this.label,
    required this.provider,
    required this.phone,
  });

  /// e.g. mpesa_tz, tigopesa, airtel_money, halopesa.
  final String provider;
  final String id;
  final String label;
  final String phone;

  static const Map<String, String> providerLabels = <String, String>{
    'mpesa_tz': 'M-Pesa',
    'tigopesa': 'TigoPesa',
    'airtel_money': 'Airtel Money',
    'halopesa': 'HaloPesa',
  };

  String get providerDisplayName => providerLabels[provider] ?? provider;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'provider': provider,
        'phone': phone,
      };

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        provider: json['provider'] as String,
        phone: json['phone'] as String,
      );

  PaymentMethod copyWith({String? label, String? provider, String? phone}) =>
      PaymentMethod(
        id: id,
        label: label ?? this.label,
        provider: provider ?? this.provider,
        phone: phone ?? this.phone,
      );

  @override
  List<Object?> get props => <Object?>[id, label, provider, phone];
}
