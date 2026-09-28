import 'package:first_app/features/auth/join_invite_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('invite token from a bare code or a pasted link', () {
    expect(inviteTokenFrom('  abc123  '), 'abc123');
    expect(inviteTokenFrom('https://internhub-sas-production-b44c.up.railway.app/join/cbMrGbnHygVT-QA_1'),
        'cbMrGbnHygVT-QA_1');
    expect(inviteTokenFrom('https://example.test/join/tok9?utm_source=whatsapp'), 'tok9');
    expect(inviteTokenFrom('Join us: https://example.test/join/tok9/ thanks'), 'tok9');
    expect(inviteTokenFrom('Join here https://example.test/join/tok9 before Friday'), 'tok9');
    expect(inviteTokenFrom('https://example.test/join/sKs_is-2s'), 'sKs_is-2s');
    expect(inviteTokenFrom(''), '');
  });
}
