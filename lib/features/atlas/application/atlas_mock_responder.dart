bool isSupplementQuestion(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('supplement') ||
      normalized.contains('creatine') ||
      normalized.contains('whey') ||
      normalized.contains('protein powder') ||
      normalized.contains('pre workout') ||
      normalized.contains('pre-workout');
}

String atlasMockResponseFor(String message) {
  // Temporary ATLAS mock response logic for marketing/demo chat.
  // Replace this function with the real ATLAS API call when backend AI exists.
  if (isSupplementQuestion(message)) {
    return 'You don\'t need supplements to build muscle. The foundation is still consistent training, enough protein, enough calories, sleep, and progressive overload.\n\n'
        'Supplements can help, but they should support the basics, not replace them.\n\n'
        'For most people, the only ones worth considering are:\n'
        '- protein powder, if hitting protein through food is difficult\n'
        '- creatine monohydrate, if it suits you and you tolerate it well\n\n'
        'Start with food, training, and recovery first. This is general guidance, not medical advice.';
  }

  return 'I can help with that soon. For now, keep the basics steady: show up for your next workout, eat enough protein, stay hydrated, and recover well. ATLAS will get more personal as the full coaching brain comes online.';
}
