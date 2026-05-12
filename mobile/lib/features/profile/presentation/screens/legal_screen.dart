import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';

enum LegalDocument { privacy, terms }

class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.document, super.key});

  final LegalDocument document;

  String get _title => document == LegalDocument.privacy
      ? 'Privacy policy'
      : 'Terms of service';

  List<_LegalSection> get _sections => document == LegalDocument.privacy
      ? _privacySections
      : _termsSections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        children: <Widget>[
          Text(
            'Last updated: April 2026',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          ..._sections.expand(
            (_LegalSection s) => <Widget>[
              Text(
                s.heading,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                s.body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Questions? Email legal@rishfy.co.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

const List<_LegalSection> _privacySections = <_LegalSection>[
  _LegalSection(
    'Who we are',
    'Rishfy is a Tanzania D5-licensed ride-sharing platform operated from '
        'Dar es Salaam. This policy explains what personal information we '
        'collect when you use the Rishfy mobile app, why we collect it, and '
        'what choices you have.',
  ),
  _LegalSection(
    'Information we collect',
    'Account info: name, phone number, optional email, encrypted password.\n'
        'Driver info (if you sign up to drive): driving licence number, '
        'licence expiry date, and optional LATRA permit number, plus the '
        'vehicles you register on the platform.\n'
        'Trip info: pickup and drop-off locations, departure times, seats '
        'booked, and price paid.\n'
        'Device info: device model, OS version, and an anonymous device '
        'identifier used for push notifications.',
  ),
  _LegalSection(
    'How we use your data',
    'We use your data to match passengers with drivers, process payments, '
        'verify driver credentials, send you booking and trip notifications, '
        'comply with Tanzanian transport regulations (LATRA reporting), and '
        'improve safety on the platform.',
  ),
  _LegalSection(
    'Who we share data with',
    'Mobile money providers (M-Pesa, TigoPesa, Airtel Money, HaloPesa) to '
        'process payments; LATRA when required for safety or audit; '
        'emergency services if you authorise an alert. We do not sell your '
        'personal data.',
  ),
  _LegalSection(
    'Where your data lives',
    'Your account data is stored on Rishfy servers located in Tanzania. '
        'Authentication tokens, saved emergency contacts and saved payment '
        'numbers are stored encrypted on your device only — Rishfy does '
        'not receive them.',
  ),
  _LegalSection(
    'Your rights',
    'You can edit your profile from the app at any time. To delete your '
        'account or request a copy of your data, email support@rishfy.co. '
        'We respond within 30 days.',
  ),
];

const List<_LegalSection> _termsSections = <_LegalSection>[
  _LegalSection(
    'Acceptance',
    'By creating a Rishfy account or using the Rishfy mobile app, you '
        'agree to these terms. If you do not agree, please stop using the '
        'service.',
  ),
  _LegalSection(
    'Eligibility',
    'You must be at least 18 years old and provide a valid Tanzanian '
        'phone number to register. Drivers must additionally hold a valid '
        'driving licence and register a roadworthy vehicle on their '
        'profile.',
  ),
  _LegalSection(
    'Bookings and payments',
    'When you book a seat you authorise Rishfy to initiate a mobile money '
        'charge equal to the price-per-seat set by the driver, multiplied '
        'by the seats you book. Cancellation within 2 hours of departure '
        'is free; after that a small fee may apply.',
  ),
  _LegalSection(
    'Driver responsibilities',
    'Drivers are responsible for keeping their vehicle roadworthy, holding '
        'current insurance, driving safely, honouring confirmed bookings, '
        'and complying with all LATRA and Tanzanian traffic rules.',
  ),
  _LegalSection(
    'Conduct',
    'Harassment, intoxication, illegal goods, and discrimination based on '
        'protected characteristics will result in immediate suspension of '
        'the account. Report incidents to support@rishfy.co.',
  ),
  _LegalSection(
    'Liability',
    'Rishfy facilitates connections between passengers and drivers but is '
        'not the operator of any vehicle. To the maximum extent permitted '
        'by law, Rishfy is not liable for indirect damages arising from '
        'individual trips. Drivers retain their own insurance liabilities.',
  ),
  _LegalSection(
    'Changes',
    'We may update these terms; we will notify you in-app for material '
        'changes. Continued use after notification means you accept the '
        'updated terms.',
  ),
];
