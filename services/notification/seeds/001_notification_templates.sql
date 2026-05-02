-- Notification template seeds — EN + SW
-- Variables use {{handlebars}} syntax. Renderer does key substitution.

INSERT INTO notification_templates (key, lang, channel, subject, body_template, variables) VALUES

-- booking.created
('booking.created', 'en', 'push',   NULL, 'Your booking is confirmed! Code: {{confirmation_code}}. Driver {{driver_name}} picks you up at {{departure_time}}.', '["confirmation_code","driver_name","departure_time"]'),
('booking.created', 'sw', 'push',   NULL, 'Nafasi yako imehifadhiwa! Nambari: {{confirmation_code}}. Dereva {{driver_name}} atakuchukua {{departure_time}}.', '["confirmation_code","driver_name","departure_time"]'),
('booking.created', 'en', 'sms',    NULL, 'RISHFY: Booking confirmed. Code {{confirmation_code}}. Driver {{driver_name}} | {{departure_time}}. Reply CANCEL to cancel.', '["confirmation_code","driver_name","departure_time"]'),
('booking.created', 'sw', 'sms',    NULL, 'RISHFY: Nafasi imehifadhiwa. Nambari {{confirmation_code}}. Dereva {{driver_name}} | {{departure_time}}. Jibu CANCEL kukanusha.', '["confirmation_code","driver_name","departure_time"]'),
('booking.created', 'en', 'in_app', 'Booking Confirmed', 'Your seat is reserved with {{driver_name}} for {{departure_time}}. Confirmation code: {{confirmation_code}}.', '["driver_name","departure_time","confirmation_code"]'),
('booking.created', 'sw', 'in_app', 'Nafasi Imehifadhiwa', 'Nafasi yako imehifadhiwa na {{driver_name}} kwa {{departure_time}}. Nambari: {{confirmation_code}}.', '["driver_name","departure_time","confirmation_code"]'),

-- booking.cancelled (passenger initiated)
('booking.cancelled.passenger', 'en', 'push',   NULL, 'You cancelled your booking with {{driver_name}} on {{departure_time}}.', '["driver_name","departure_time"]'),
('booking.cancelled.passenger', 'sw', 'push',   NULL, 'Umefuta nafasi yako na {{driver_name}} tarehe {{departure_time}}.', '["driver_name","departure_time"]'),
('booking.cancelled.passenger', 'en', 'in_app', 'Booking Cancelled', 'Your booking with {{driver_name}} has been cancelled. {{refund_message}}', '["driver_name","refund_message"]'),
('booking.cancelled.passenger', 'sw', 'in_app', 'Nafasi Imefutwa', 'Nafasi yako na {{driver_name}} imefutwa. {{refund_message}}', '["driver_name","refund_message"]'),

-- booking.cancelled (driver initiated — notify passenger)
('booking.cancelled.by_driver', 'en', 'push',   NULL, 'Your driver {{driver_name}} cancelled the trip on {{departure_time}}. We are sorry for the inconvenience.', '["driver_name","departure_time"]'),
('booking.cancelled.by_driver', 'sw', 'push',   NULL, 'Dereva wako {{driver_name}} amefuta safari ya {{departure_time}}. Tunakuomba msamaha.', '["driver_name","departure_time"]'),
('booking.cancelled.by_driver', 'en', 'sms',    NULL, 'RISHFY: Driver {{driver_name}} cancelled your trip ({{departure_time}}). Full refund will be processed within 24h.', '["driver_name","departure_time"]'),
('booking.cancelled.by_driver', 'sw', 'sms',    NULL, 'RISHFY: Dereva {{driver_name}} amefuta safari yako ({{departure_time}}). Fedha zitarudishwa ndani ya saa 24.', '["driver_name","departure_time"]'),

-- payment.completed
('payment.completed', 'en', 'push',   NULL, 'Payment of TZS {{amount}} received for your booking {{confirmation_code}}.', '["amount","confirmation_code"]'),
('payment.completed', 'sw', 'push',   NULL, 'Malipo ya TZS {{amount}} yamepokelewa kwa nafasi {{confirmation_code}}.', '["amount","confirmation_code"]'),
('payment.completed', 'en', 'sms',    NULL, 'RISHFY: Payment TZS {{amount}} confirmed. Ref: {{provider_reference}}. Booking: {{confirmation_code}}.', '["amount","provider_reference","confirmation_code"]'),
('payment.completed', 'sw', 'sms',    NULL, 'RISHFY: Malipo TZS {{amount}} yamethibitishwa. Kumb: {{provider_reference}}. Nafasi: {{confirmation_code}}.', '["amount","provider_reference","confirmation_code"]'),

-- payment.failed
('payment.failed', 'en', 'push',   NULL, 'Payment failed for booking {{confirmation_code}}. Please try again or use a different method.', '["confirmation_code"]'),
('payment.failed', 'sw', 'push',   NULL, 'Malipo yameshindwa kwa nafasi {{confirmation_code}}. Tafadhali jaribu tena au tumia njia nyingine.', '["confirmation_code"]'),
('payment.failed', 'en', 'sms',    NULL, 'RISHFY: Payment failed for booking {{confirmation_code}}. Booking expires in 2 minutes. Open the app to retry.', '["confirmation_code"]'),
('payment.failed', 'sw', 'sms',    NULL, 'RISHFY: Malipo yameshindwa kwa {{confirmation_code}}. Nafasi inafutwa baada ya dakika 2. Fungua programu kujaribu tena.', '["confirmation_code"]'),

-- trip.started (driver action — notify passenger)
('trip.started', 'en', 'push', NULL, 'Your trip has started! Driver {{driver_name}} is on the way.', '["driver_name"]'),
('trip.started', 'sw', 'push', NULL, 'Safari yako imeanza! Dereva {{driver_name}} yuko njiani.', '["driver_name"]'),

-- trip.completed
('trip.completed', 'en', 'push',   NULL, 'Trip completed! Please rate your experience with {{driver_name}}.', '["driver_name"]'),
('trip.completed', 'sw', 'push',   NULL, 'Safari imekamilika! Tafadhali tathmini uzoefu wako na {{driver_name}}.', '["driver_name"]'),
('trip.completed', 'en', 'in_app', 'Rate Your Trip', 'How was your ride with {{driver_name}}? Tap to leave a rating.', '["driver_name"]'),
('trip.completed', 'sw', 'in_app', 'Tathmini Safari Yako', 'Safari ilikuwaje na {{driver_name}}? Gonga kutoa tathmini.', '["driver_name"]'),

-- driver.arrived (passenger notification)
('driver.arrived', 'en', 'push', NULL, 'Your driver {{driver_name}} has arrived at {{pickup_address}}!', '["driver_name","pickup_address"]'),
('driver.arrived', 'sw', 'push', NULL, 'Dereva wako {{driver_name}} amefika {{pickup_address}}!', '["driver_name","pickup_address"]'),

-- booking.expiry_warning (2 min before expiry)
('booking.expiry_warning', 'en', 'push', NULL, 'Your booking {{confirmation_code}} expires in 2 minutes. Complete payment now.', '["confirmation_code"]'),
('booking.expiry_warning', 'sw', 'push', NULL, 'Nafasi yako {{confirmation_code}} inakwisha baada ya dakika 2. Lipia sasa.', '["confirmation_code"]'),

-- settlement.processed (driver)
('settlement.processed', 'en', 'push',   NULL, 'Your earnings of TZS {{amount}} for {{trip_count}} trips have been sent to your {{payout_method}}.', '["amount","trip_count","payout_method"]'),
('settlement.processed', 'sw', 'push',   NULL, 'Mapato yako ya TZS {{amount}} kwa safari {{trip_count}} yametumwa kwenye {{payout_method}} yako.', '["amount","trip_count","payout_method"]'),
('settlement.processed', 'en', 'sms',    NULL, 'RISHFY: TZS {{amount}} sent to your {{payout_method}}. {{trip_count}} trips processed.', '["amount","payout_method","trip_count"]'),
('settlement.processed', 'sw', 'sms',    NULL, 'RISHFY: TZS {{amount}} zimetumwa kwenye {{payout_method}} yako. Safari {{trip_count}} zimeshughulikiwa.', '["amount","payout_method","trip_count"]')

ON CONFLICT (key, lang, channel) DO UPDATE
  SET body_template = EXCLUDED.body_template,
      subject = EXCLUDED.subject,
      variables = EXCLUDED.variables,
      updated_at = now();
