import type { PaymentProvider } from '@/types/paymentLinks';
/** Reviewed provider contracts; keep aligned with app.normalize_payment_link. Never fetch URLs. */
export const paymentProviders = {
  monzo: { name: 'Monzo', host: 'monzo.me', help: 'Use your personal Monzo.me link from Payments → Request money → By QR code or link.' },
  revolut: { name: 'Revolut', host: 'revolut.me', help: 'Use your generic Revolut.me link from Payments → New → Link → Request money.' },
  paypal: { name: 'PayPal', host: 'paypal.me', help: 'Use your reusable PayPal.Me profile link, without an amount.' },
  custom: { name: 'Other / Custom', host: null, help: 'Paste an HTTPS payment link you want people to use to reimburse you.' },
} as const;
export function normalizePaymentUrl(provider: PaymentProvider, raw: string): string {
  if (!Object.prototype.hasOwnProperty.call(paymentProviders, provider)) throw new Error('Choose a supported payment provider.');
  const value = raw.trim();
  if (!value || value.length > 2048) throw new Error('Enter a payment link of at most 2048 characters.');
  const parts = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]+)(.*)$/.exec(value);
  if (!parts || parts[1]!.toLowerCase() !== 'https') throw new Error('Use an HTTPS payment link.');
  const host = parts[2]!.toLowerCase(), tail = parts[3]!;
  if (host.length > 253 || !/^[a-z0-9.-]+$/.test(host) || !/\.[a-z]{2,63}$/.test(host)
    || /(^|\.)(localhost|local|internal|lan|home|test|invalid|onion|arpa)$/.test(host)
    || host.split('.').some(label => label.length > 63 || !/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(label))) {
    throw new Error('Use a public website address without an IP address, port or login details.');
  }
  if (!/^[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]*$/.test(tail) || /%(?![0-9a-fA-F]{2})/.test(tail)) throw new Error('That payment link contains invalid characters.');
  const rule = paymentProviders[provider];
  if (!rule) throw new Error('Choose a supported payment provider.');
  if (rule.host && (host !== rule.host || !/^\/[^/?#]+/.test(tail))) throw new Error(`Use your personal ${rule.name} payment link.`);
  if (provider === 'paypal' && !/^\/[A-Za-z0-9]{1,20}\/?$/.test(tail)) throw new Error('Use your reusable PayPal.Me profile link without an amount, query or fragment.');
  // Parse again in the browser, without rewriting opaque path/query/fragment semantics.
  const result = `https://${host}${tail}`;
  if (new URL(result).hostname !== host) throw new Error('That website address is not valid.');
  return result;
}
