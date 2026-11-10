import 'dart:convert';

import 'auth_service.dart';

String buildUekLoginScript(Credentials credentials) {
  final username = jsonEncode(credentials.username);
  final password = jsonEncode(credentials.password);
  return '''
(() => {
  const allowedHosts = ['portal.uek.krakow.pl', 'logowanie.uek.krakow.pl', 'usosweb.uek.krakow.pl'];
  const isTrusted = (url) => url.protocol === 'https:' &&
    allowedHosts.includes(url.hostname) && (!url.port || url.port === '443');
  if (!isTrusted(location)) return false;
  const passwordInput = document.querySelector('input[type="password"]');
  const form = passwordInput?.form;
  if (!form || !isTrusted(new URL(form.action || location.href, location.href))) return false;
  const visibleInputs = Array.from(document.querySelectorAll('input')).filter((input) =>
    input.type !== 'hidden' && input.type !== 'submit' && input.type !== 'button'
  );
  const usernameInput = visibleInputs.find((input) =>
    input !== passwordInput && /login|user|uid|username|email|identyfikator/i.test(input.name || input.id || input.type || '')
  ) || visibleInputs.find((input) => input !== passwordInput);
  if (!usernameInput) return false;
  const setValue = (input, value) => {
    input.focus();
    input.value = value;
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
  };
  setValue(usernameInput, $username);
  setValue(passwordInput, $password);
  const submitter = form.querySelector('button[type="submit"][name], input[type="submit"][name]');
  if (submitter && !Array.from(form.elements).some((element) =>
      element !== submitter && element.name === submitter.name)) {
    const field = document.createElement('input');
    field.type = 'hidden';
    field.name = submitter.name;
    field.value = submitter.value;
    form.appendChild(field);
  }
  // Omijamy wadliwe skrypty CAS, zachowując pola formularza.
  HTMLFormElement.prototype.submit.call(form);
  return true;
})()
''';
}
