import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _copy(BuildContext ctx, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Copied $value')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.spaceLg),
        children: <Widget>[
          Text(
            'How can we help?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _ContactCard(
            icon: Icons.email_outlined,
            label: 'Email',
            value: 'support@rishfy.co',
            onCopy: () => _copy(context, 'support@rishfy.co'),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.chat_bubble_outline,
            label: 'WhatsApp',
            value: '+255 712 345 678',
            onCopy: () => _copy(context, '+255712345678'),
          ),
          const SizedBox(height: 8),
          _ContactCard(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: '+255 22 211 1111',
            onCopy: () => _copy(context, '+255222111111'),
          ),
          const SizedBox(height: 24),
          Text(
            'Frequently asked questions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._faq.map(
            (_FaqEntry e) => Card(
              child: ExpansionTile(
                title: Text(e.question),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(e.answer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'For emergencies, dial 112.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label),
        subtitle: Text(value),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Copy',
          onPressed: onCopy,
        ),
      ),
    );
  }
}

class _FaqEntry {
  const _FaqEntry({required this.question, required this.answer});
  final String question;
  final String answer;
}

const List<_FaqEntry> _faq = <_FaqEntry>[
  _FaqEntry(
    question: 'How do I book a ride?',
    answer:
        'From the home screen, tap "Where to?" and search for a route. '
        'Choose a matching ride, confirm seats, enter your mobile money '
        'number, and approve the payment prompt on your phone.',
  ),
  _FaqEntry(
    question: 'How do drivers get verified?',
    answer:
        'Drivers submit their licence number, expiry, and optional LATRA '
        'permit through the "Become a driver" flow. All routes are posted '
        'against a verified vehicle on the driver\'s profile.',
  ),
  _FaqEntry(
    question: 'How is the price calculated?',
    answer:
        'Drivers set a flat price per seat when they post a route. The '
        'total you pay equals price-per-seat times the number of seats '
        'you book. Rishfy adds no surcharges at booking time.',
  ),
  _FaqEntry(
    question: 'Can I cancel a booking?',
    answer:
        'Yes. Open the booking and tap "Cancel booking". Free cancellation '
        'is available within 2 hours of departure; after that a small fee '
        'may apply depending on driver policy.',
  ),
  _FaqEntry(
    question: 'How do I report a problem during a trip?',
    answer:
        'During an active trip, tap the red emergency icon in the top bar. '
        'You will see the national emergency number (112) plus your saved '
        'emergency contacts.',
  ),
  _FaqEntry(
    question: 'Where is my data stored?',
    answer:
        'Your account data sits on Rishfy servers in Tanzania. Tokens and '
        'sensitive local data (emergency contacts, payment methods) are '
        'stored encrypted on your device only.',
  ),
];
